#!/usr/bin/env python3
"""Original wisprM JSON-line worker; never executes model repository code."""
import json
import os
from pathlib import Path
import sys

protocol = sys.stdout
sys.stdout = sys.stderr
os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")
os.environ.setdefault("DO_NOT_TRACK", "1")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
os.environ["PATH"] = str(Path(sys.executable).parent) + os.pathsep + os.environ.get("PATH", "")

def emit(value):
    protocol.write(json.dumps(value, ensure_ascii=False) + "\n")
    protocol.flush()

class Recognizer:
    def __init__(self):
        self.model = self.engine = self.path = None

    def prepare(self, engine, model_id):
        if engine not in ("Whisper", "Parakeet"):
            raise ValueError("Unsupported speech engine")
        if not isinstance(model_id, str) or not model_id.strip():
            raise ValueError("Choose a model ID or absolute local model directory")
        path = Path(model_id).expanduser()
        if path.is_absolute():
            if not path.is_dir():
                raise ValueError("Local model directory does not exist")
            model_path = str(path)
        else:
            from huggingface_hub import snapshot_download
            model_path = snapshot_download(repo_id=model_id, allow_patterns=[
                "config.json", "*.safetensors", "*.npz", "tokenizer.json",
                "tokenizer_config.json", "vocab.json", "merges.txt", "README.md"])
        self.model = None
        if "mlx_whisper.transcribe" in sys.modules:
            from mlx_whisper.transcribe import ModelHolder
            ModelHolder.model = None
            ModelHolder.model_path = None
        import gc
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
        return {"model": model_id, "engine": engine}

    def transcribe(self, audio, language):
        if self.model is None:
            raise RuntimeError("Load a speech model first")
        path = Path(audio)
        if not path.is_file() or path.suffix.lower() not in (".wav", ".caf", ".aiff", ".m4a"):
            raise ValueError("Audio input must be a local recording")
        detected_language = language
        if self.engine == "Whisper":
            import mlx_whisper
            result = mlx_whisper.transcribe(
                str(path), path_or_hf_repo=self.path, language=None if language == "auto" else language,
                verbose=None, condition_on_previous_text=False, temperature=0.0)
            detected_language = result.get("language", language)
            text = "".join(s["text"] for s in result.get("segments", [])
                           if s.get("no_speech_prob", 0) < 0.8).strip()
        else:
            text = self.model.transcribe(str(path)).text.strip()
        return {"text": text, "language": detected_language}

def main():
    recognizer = Recognizer()
    for line in sys.stdin:
        request_id = None
        try:
            request = json.loads(line)
            request_id = request.get("id")
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
            emit({"id": request_id, "ok": False, "error": f"{type(error).__name__}: {error}"})

if __name__ == "__main__":
    main()
