import asyncio
from typing import AsyncIterator


class FasterWhisperSTTProvider:
    def __init__(self, model_size: str = "tiny"):
        self.model_size = model_size
        self.model = None

    async def load(self):
        from faster_whisper import WhisperModel

        loop = asyncio.get_event_loop()
        self.model = await loop.run_in_executor(
            None, lambda: WhisperModel(self.model_size, device="cpu", compute_type="int8")
        )

    async def transcribe(self, audio_bytes: bytes) -> str:
        if self.model is None:
            await self.load()

        import io
        import wave

        with io.BytesIO(audio_bytes) as wav_file:
            segments, _ = self.model.transcribe(wav_file, language="en")
            text = " ".join(seg.text for seg in segments)
            return text
