import asyncio
import subprocess
from typing import AsyncIterator


class PiperTTSProvider:
    def __init__(self, model_path: str = "models/piper/en_US-amy-medium.onnx"):
        self.model_path = model_path

    async def synthesize(self, text: str) -> AsyncIterator[bytes]:
        proc = await asyncio.create_subprocess_exec(
            "piper",
            "--model", self.model_path,
            "--output-raw",
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )

        stdout, _ = await proc.communicate(text.encode())
        yield stdout
