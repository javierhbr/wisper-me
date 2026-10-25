"""Bounded, supervised local audio decoding. No ML dependencies are imported here."""
from array import array
from contextlib import contextmanager
from dataclasses import dataclass
import math
import os
from pathlib import Path
import selectors
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import wave

SAMPLE_RATE = 16000
SAMPLE_BYTES = 4
MAX_INPUT_BYTES = 100 * 1024 * 1024
MAX_DURATION_SECONDS = 600
SUPPORTED_EXTENSIONS = frozenset({
    ".wav", ".caf", ".aiff", ".aif", ".aifc", ".m4a", ".mp4", ".mp3",
    ".flac", ".ogg", ".opus", ".webm", ".weba", ".aac"})

class AudioDecodeError(ValueError):
    pass

class AudioLimitError(AudioDecodeError):
    pass

@dataclass(frozen=True)
class AudioLimits:
    max_input_bytes: int = MAX_INPUT_BYTES
    max_duration_seconds: float = MAX_DURATION_SECONDS
    chunk_seconds: float = 29
    read_timeout_seconds: float = 15
    decode_budget_seconds: float = 60

    def __post_init__(self):
        if not 0 < self.max_input_bytes <= MAX_INPUT_BYTES:
            raise ValueError("Input bound must be between one byte and 100 MiB")
        if not 0 < self.max_duration_seconds <= MAX_DURATION_SECONDS:
            raise ValueError("Audio duration bound must be at most 600 seconds")
        if not 1 <= int(self.chunk_seconds * SAMPLE_RATE) <= 30 * SAMPLE_RATE:
            raise ValueError("Audio windows must be at most 30 seconds")
        if self.read_timeout_seconds <= 0 or self.decode_budget_seconds <= 0:
            raise ValueError("Decoder timeouts must be positive")

def validate_audio_file(value, limits=AudioLimits()):
    try:
        path = Path(value).expanduser().resolve(strict=True)
        info = path.stat()
    except (OSError, TypeError, ValueError) as error:
        raise AudioDecodeError("Audio input must be an existing local file") from error
    if not stat.S_ISREG(info.st_mode) or path.suffix.lower() not in SUPPORTED_EXTENSIONS:
        raise AudioDecodeError("Choose a supported local audio file")
    if info.st_size > limits.max_input_bytes:
        raise AudioLimitError("Audio input exceeds the 100 MiB file limit")
    if info.st_size < 4:
        raise AudioDecodeError("The audio file is empty or incomplete")
    with path.open("rb") as source:
        header = source.read(32)
    extension = path.suffix.lower()
    valid = {
        ".wav": lambda: header[:4] in (b"RIFF", b"RF64") and header[8:12] == b"WAVE",
        ".caf": lambda: header[:4] == b"caff",
        ".aiff": lambda: header[:4] == b"FORM" and header[8:12] in (b"AIFF", b"AIFC"),
        ".aif": lambda: header[:4] == b"FORM" and header[8:12] in (b"AIFF", b"AIFC"),
        ".aifc": lambda: header[:4] == b"FORM" and header[8:12] in (b"AIFF", b"AIFC"),
        ".m4a": lambda: header[4:8] == b"ftyp",
        ".mp4": lambda: header[4:8] == b"ftyp",
        ".mp3": lambda: header[:3] == b"ID3" or (len(header) > 1 and header[0] == 0xff and header[1] & 0xe0 == 0xe0),
        ".flac": lambda: header[:4] == b"fLaC",
        ".ogg": lambda: header[:4] == b"OggS",
        ".opus": lambda: header[:4] == b"OggS",
        ".webm": lambda: header[:4] == b"\x1a\x45\xdf\xa3",
        ".weba": lambda: header[:4] == b"\x1a\x45\xdf\xa3",
        ".aac": lambda: len(header) > 1 and header[0] == 0xff and header[1] & 0xf0 == 0xf0,
    }[extension]()
    if not valid:
        raise AudioDecodeError("The file contents do not match its audio extension")
    return path

def _ffmpeg():
    candidates = [
        Path(sys.executable).parent / "ffmpeg",
        Path.home() / "Library/Application Support/wisprM/runtime/bin/ffmpeg",
    ]
    for path in candidates:
        if path.is_file() and os.access(path, os.X_OK):
            return str(path)
    found = shutil.which("ffmpeg")
    if found:
        return found
    raise AudioDecodeError("The local audio decoder is unavailable. Reinstall the runtime.")

def _reap(child):
    if child.stdout is not None:
        child.stdout.close()
    if child.poll() is None:
        child.terminate()
    try:
        child.wait(timeout=2)
    except subprocess.TimeoutExpired:
        child.kill()
        child.wait()

def _stream_chunks(path, limits, ffmpeg_command):
    command = list(ffmpeg_command) if ffmpeg_command is not None else [_ffmpeg()]
    command += [
        "-nostdin", "-hide_banner", "-loglevel", "error", "-max_alloc", "67108864",
        "-protocol_whitelist", "file,pipe", "-threads", "2", "-i", str(path),
        "-vn", "-sn", "-dn", "-t", str(limits.max_duration_seconds + 1),
        "-ac", "1", "-ar", str(SAMPLE_RATE), "-f", "f32le", "pipe:1"]
    child = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, bufsize=0)
    # In production the worker owns its process group; the decoder inherits that group.
    selector = selectors.DefaultSelector()
    maximum_bytes = int(limits.max_duration_seconds * SAMPLE_RATE) * SAMPLE_BYTES
    window_bytes = int(limits.chunk_seconds * SAMPLE_RATE) * SAMPLE_BYTES
    buffer = bytearray()
    decoded = 0
    budget = limits.decode_budget_seconds
    try:
        selector.register(child.stdout, selectors.EVENT_READ)
        while True:
            started = time.monotonic()
            events = selector.select(min(limits.read_timeout_seconds, max(0, budget)))
            budget -= time.monotonic() - started
            if not events or budget <= 0:
                raise AudioDecodeError("The local audio decoder timed out")
            data = os.read(child.stdout.fileno(), min(65536, max(4, window_bytes - len(buffer))))
            if not data:
                try:
                    status = child.wait(timeout=min(2, max(0.01, budget)))
                except subprocess.TimeoutExpired as error:
                    raise AudioDecodeError("The local audio decoder did not finish") from error
                if status:
                    raise AudioDecodeError("The local audio file could not be decoded")
                if decoded == 0 or len(buffer) % SAMPLE_BYTES:
                    raise AudioDecodeError("The audio file contains no complete PCM samples")
                if buffer:
                    yield bytes(buffer)
                return
            decoded += len(data)
            if decoded > maximum_bytes:
                raise AudioLimitError("Decoded audio exceeds the 600 second duration limit")
            buffer.extend(data)
            if len(buffer) == window_bytes:
                yield bytes(buffer)
                buffer.clear()
    finally:
        selector.close()
        _reap(child)

@contextmanager
def decode_audio_chunks(value, *, limits=AudioLimits(), ffmpeg_command=None):
    path = validate_audio_file(value, limits)
    chunks = _stream_chunks(path, limits, ffmpeg_command)
    try:
        yield chunks
    finally:
        chunks.close()

@contextmanager
def pcm_wave_file(pcm, *, directory=None):
    if len(pcm) % SAMPLE_BYTES:
        raise AudioDecodeError("PCM input is not sample-aligned")
    floats = array("f")
    floats.frombytes(pcm)
    if sys.byteorder != "little":
        floats.byteswap()
    if not all(math.isfinite(value) for value in floats):
        raise AudioDecodeError("The audio decoder returned non-finite samples")
    samples = array("h", (round(max(-1.0, min(1.0, value)) * 32767) for value in floats))
    if sys.byteorder != "little":
        samples.byteswap()
    descriptor, name = tempfile.mkstemp(prefix="wisprm-chunk-", suffix=".wav", dir=directory)
    path = Path(name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            with wave.open(handle, "wb") as output:
                output.setnchannels(1)
                output.setsampwidth(2)
                output.setframerate(SAMPLE_RATE)
                output.writeframes(samples.tobytes())
        yield path
    finally:
        path.unlink(missing_ok=True)
