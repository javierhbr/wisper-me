#!/usr/bin/env python3
"""Local JSON-line ASR worker. Model repositories are data, never executable code."""
import gc
import json
import os
from pathlib import Path
import re
import signal
import sys
sys.dont_write_bytecode = True

from audio_pipeline import (AudioDecodeError, AudioLimits, SAMPLE_RATE, SAMPLE_BYTES,
                            decode_audio_chunks, pcm_wave_file)

os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")
os.environ.setdefault("DO_NOT_TRACK", "1")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
os.environ["PATH"] = str(Path(sys.executable).parent) + os.pathsep + os.environ.get("PATH", "")
_protocol = None
MAX_REQUEST_BYTES = 65536
DEFAULT_MODELS = frozenset({
    "mlx-community/whisper-tiny", "mlx-community/whisper-base-mlx",
    "mlx-community/whisper-small-mlx", "mlx-community/parakeet-tdt-0.6b-v3"})

def emit(value):
    destination = _protocol if _protocol is not None else sys.stdout
    destination.write(json.dumps(value, ensure_ascii=False) + "\n")
    destination.flush()

def establish_process_group():
    if os.getpgrp() != os.getpid():
        os.setsid()
    if os.getpgrp() != os.getpid():
        raise RuntimeError("The local worker could not create an owned process group")
    return {"event": "ready", "pid": os.getpid(), "process_group": os.getpgrp()}

def terminate(signum, frame):
    # Raise through the normal stack so owned decoder and audio-file finally blocks run.
    raise SystemExit(128 + signum)

def model_reference(model_id, lock_path=None):
    if not isinstance(model_id, str) or not model_id.strip() or len(model_id) > 4096:
        raise ValueError("Choose a model ID or an absolute local model directory")
    model_id = model_id.strip()
    path = Path(model_id).expanduser()
    if path.is_absolute():
        if not path.is_dir():
            raise ValueError("Local model directory does not exist")
        return str(path.resolve()), None, True
    repository, separator, explicit_revision = model_id.rpartition("@")
    if not separator:
        repository, explicit_revision = model_id, None
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", repository):
        raise ValueError("A remote model must use an owner/repository ID")
    if explicit_revision is not None and not re.fullmatch(r"[a-fA-F0-9]{40}", explicit_revision):
        raise ValueError("A custom model revision must be a complete 40-character commit hash")
    locks = {}
    lock_path = Path(lock_path) if lock_path else Path(__file__).with_name("models.lock.json")
    if lock_path.is_file():
        with lock_path.open(encoding="utf-8") as source:
            recorded = json.load(source)
        locks = recorded.get("models", recorded)
    entry = locks.get(repository)
    locked_revision = entry.get("revision") if isinstance(entry, dict) else entry
    if repository in DEFAULT_MODELS:
        if not isinstance(locked_revision, str) or not re.fullmatch(r"[a-fA-F0-9]{40}", locked_revision):
            raise ValueError("The bundled model revision lock is missing or invalid")
        if explicit_revision is not None and explicit_revision.lower() != locked_revision.lower():
            raise ValueError("Bundled presets must use their verified locked model revision")
        return repository, locked_revision, False
    return repository, explicit_revision, False

def complete_snapshot(path, engine):
    path = Path(path)
    names = ("weights.npz", "weights.safetensors") if engine == "Whisper" else ("model.safetensors",)
    return (path / "config.json").is_file() and any((path / name).is_file() for name in names)

def download_snapshot(repository, revision, engine):
    from huggingface_hub import snapshot_download
    from huggingface_hub.errors import LocalEntryNotFoundError
    options = {"repo_id": repository, "revision": revision, "allow_patterns": [
        "config.json", "*.safetensors", "*.npz", "tokenizer.json",
        "tokenizer_config.json", "vocab.json", "merges.txt", "README.md"]}
    if revision is not None:
        try:
            cached = snapshot_download(**options, local_files_only=True)
            if not complete_snapshot(cached, engine):
                raise LocalEntryNotFoundError("The pinned local snapshot is incomplete")
            return cached
        except LocalEntryNotFoundError:
            pass
    downloaded = snapshot_download(**options)
    if not complete_snapshot(downloaded, engine):
        raise ValueError("The downloaded model has no complete compatible config and weights")
    return downloaded

def merge_text(previous, current):
    """Remove only multiword overlap between adjacent, overlapping audio windows."""
    previous, current = previous.strip(), current.strip()
    if not previous:
        return current
    if not current:
        return previous
    left, right = previous.split(), current.split()
    normalize = lambda value: re.sub(r"[^\w]+", "", value).casefold()
    for length in range(min(24, len(left), len(right)), 1, -1):
        suffix = [normalize(value) for value in left[-length:]]
        prefix = [normalize(value) for value in right[:length]]
        if all(suffix) and suffix == prefix:
            return previous + (" " + " ".join(right[length:]) if right[length:] else "")
    return previous + " " + current

class Recognizer:
    def __init__(self, chunk_directory=None):
        self.model = self.engine = self.path = None
        self.chunk_directory = Path(chunk_directory) if chunk_directory else (
            Path(os.environ.get("WISPRM_RECORDINGS_DIR", str(Path.home() / "Library/Application Support/wisprM/Recordings"))))

    def prepare(self, engine, model_id):
        if engine not in ("Whisper", "Parakeet"):
            raise ValueError("Unsupported speech engine")
        repository, revision, local = model_reference(model_id)
        if local:
            model_path = repository
        else:
            model_path = download_snapshot(repository, revision, engine)
        self.model = None
        if "mlx_whisper.transcribe" in sys.modules:
            from mlx_whisper.transcribe import ModelHolder
            ModelHolder.model = None
            ModelHolder.model_path = None
        gc.collect()
        import mlx.core as mx
        mx.clear_cache()
        if engine == "Whisper":
            from mlx_whisper.transcribe import ModelHolder
            self.model = ModelHolder.get_model(model_path, mx.float16)
        else:
            from parakeet_mlx import from_pretrained
            self.model = from_pretrained(model_path)
        mx.eval(self.model.parameters())
        self.engine, self.path = engine, model_path
        return {"model": model_id, "engine": engine, "revision": revision}

    def transcribe(self, audio, language):
        if self.model is None:
            raise RuntimeError("Load a speech model first")
        if not isinstance(language, str) or not re.fullmatch(r"[A-Za-z-]{2,16}", language):
            raise ValueError("Choose a supported language code or auto")
        detected_language, text = language, ""
        previous_tail = b""
        # A 29-second new window plus at most one second of context is <=30 seconds.
        with decode_audio_chunks(audio, limits=AudioLimits(chunk_seconds=29)) as chunks:
            for chunk in chunks:
                pcm = previous_tail + chunk
                previous_tail = chunk[-SAMPLE_RATE * SAMPLE_BYTES:]
                if self.engine == "Whisper":
                    import numpy as np
                    import mlx_whisper
                    waveform = np.frombuffer(pcm, dtype="<f4").copy()
                    if not np.isfinite(waveform).all():
                        raise AudioDecodeError("The audio decoder returned non-finite samples")
                    result = mlx_whisper.transcribe(
                        waveform, path_or_hf_repo=self.path,
                        language=None if detected_language == "auto" else detected_language,
                        verbose=None, condition_on_previous_text=False, temperature=0.0)
                    detected_language = result.get("language", detected_language)
                    words = "".join(segment["text"] for segment in result.get("segments", [])
                                    if segment.get("no_speech_prob", 0) < 0.8).strip()
                else:
                    self.chunk_directory.mkdir(mode=0o700, parents=True, exist_ok=True)
                    with pcm_wave_file(pcm, directory=self.chunk_directory) as path:
                        words = self.model.transcribe(str(path)).text.strip()
                text = merge_text(text, words)
                if len(text) > 200000:
                    raise AudioDecodeError("The model output exceeded the transcript size limit")
        return {"text": text, "language": detected_language}

def main():
    global _protocol
    _protocol = sys.stdout
    sys.stdout = sys.stderr
    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    emit(establish_process_group())
    recognizer = Recognizer()
    stream = sys.stdin.buffer
    while True:
        line = stream.readline(MAX_REQUEST_BYTES + 1)
        if not line:
            return
        if len(line) > MAX_REQUEST_BYTES:
            while line and not line.endswith(b"\n"):
                line = stream.readline(MAX_REQUEST_BYTES + 1)
            emit({"id": None, "ok": False, "error": "Request exceeds the protocol size limit"})
            continue
        request_id = None
        try:
            request = json.loads(line)
            if not isinstance(request, dict):
                raise ValueError("A request must be a JSON object")
            request_id = request.get("id")
            if not isinstance(request_id, str) or not 1 <= len(request_id) <= 128:
                raise ValueError("A request needs a bounded string ID")
            operation = request.get("op")
            if operation == "prepare":
                emit({"id": request_id, "event": "progress", "message": "Downloading or loading local weights…"})
                result = recognizer.prepare(request["engine"], request["model"])
            elif operation == "transcribe":
                result = recognizer.transcribe(request["audio"], request.get("language", "auto"))
            elif operation == "ping":
                result = {"ready": True}
            elif operation == "quit":
                return
            else:
                raise ValueError("Unknown operation")
            emit({"id": request_id, "ok": True, **result})
        except Exception as error:
            emit({"id": request_id, "ok": False, "error": f"{type(error).__name__}: {str(error)[:2048]}"})

if __name__ == "__main__":
    main()
