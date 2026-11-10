"""Load the packaged pipeline/OCR and connect its Agent without game input."""
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "bjx_release_replay", Path(__file__).with_name("test-royale-replay.py")
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
runtime = module.Runtime()
runtime.close()
print("PASS: packaged MaaFramework resource/OCR loading and C# Agent connection; no game input.")
