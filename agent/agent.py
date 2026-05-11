import os
import json
from typing import AsyncIterator
from dataclasses import dataclass
from dotenv import load_dotenv

load_dotenv()

from livekit.agents import JobContext, WorkerOptions, cli, tts
from livekit.agents.voice import Agent, AgentSession
from livekit.agents.llm import FunctionTool, ToolCallingAgent
from livekit.plugins import silero, openai, turn_detector
from livekit.plugins.turn_detector import based

LLM_API_KEY = os.getenv("LLM_API_KEY")
LLM_BASE_URL = os.getenv("LLM_BASE_URL", "https://api.groq.com/openai/v1")
LLM_MODEL = os.getenv("LLM_MODEL", "llama-3.1-8b-instant")
STT_MODEL = os.getenv("STT_MODEL", "whisper-large-v3-turbo")
BACKEND_URL = os.getenv("BACKEND_URL", "http://backend:3000")

SYSTEM_PROMPT = """You are Jarvis, an AI accountability companion. Your job is to help the user stay on track with their goals. Be warm but direct. Use short, natural speech — this is a voice call. Ask about their goals. If they sound off, ask about it. If they're avoiding something, call it out. You are not a therapist — you are a friend who doesn't let them off easy."""


class EdgeTTS(tts.TTS):
    def __init__(self, voice: str = "en-US-JennyNeural"):
        super().__init__(sample_rate=24000, num_channels=1)
        self.voice = voice

    async def synthesize(self, text: str) -> AsyncIterator[tts.SynthesizedAudio]:
        import edge_tts as et
        communicate = et.Communicate(text, self.voice)
        async for chunk in communicate.stream():
            if chunk["type"] == "audio":
                yield tts.SynthesizedAudio(
                    data=chunk["data"],
                    sample_rate=24000,
                    num_channels=1,
                )


import aiohttp


class JarvisTools(FunctionTool):
    def __init__(self, memory_client: "MemoryClient"):
        super().__init__()
        self._memory = memory_client

    @tool
    async def remember(self, content: str, type: str = "fact", importance: float = 0.5) -> dict:
        """Save something important the user said to long-term memory. Call this when the user shares a personal detail, preference, or meaningful event. Types: fact, preference, goal_detail, emotional_event, inside_joke."""
        result = await self._memory.save_memory(content, type, importance)
        return {"saved": True, "memory_id": result.get("id")}

    @tool
    async def recall(self, query: str) -> dict:
        """Search through past memories about the user. Call this when you need to remember something the user told you before. Provide a specific search query."""
        results = await self._memory.search_memories(query)
        return {"memories": results}

    @tool
    async def track_mood(self, mood: str, energy: float = 0.5, stress: float = 0.5) -> dict:
        """Record the user's current emotional state. Call this naturally during conversation when the user describes how they feel. Mood should be one word. Energy and stress are 0-1."""
        result = await self._memory.record_emotion(mood, energy, stress)
        return {"recorded": True, "mood": result.get("mood")}


class MemoryClient:
    def __init__(self, jwt_token: str, user_id: str):
        self.jwt_token = jwt_token
        self.user_id = user_id
        self._headers = {"Authorization": f"Bearer {jwt_token}"}

    async def search_memories(self, query: str, limit: int = 5) -> list[dict]:
        async with aiohttp.ClientSession() as s:
            async with s.post(f"{BACKEND_URL}/api/v1/memories/search", json={"query": query, "limit": limit}, headers=self._headers) as r:
                return (await r.json()).get("results", [])

    async def save_memory(self, content: str, type: str = "fact", importance: float = 0.5) -> dict:
        async with aiohttp.ClientSession() as s:
            async with s.post(f"{BACKEND_URL}/api/v1/memories", json={"type": type, "content": content, "importance": importance, "confidence": 0.8}, headers=self._headers) as r:
                return (await r.json()).get("memory", {})

    async def record_emotion(self, mood: str, energy: float = 0.5, stress: float = 0.5) -> dict:
        async with aiohttp.ClientSession() as s:
            async with s.post(f"{BACKEND_URL}/api/v1/emotions", json={"mood": mood, "energy": energy, "stress": stress}, headers=self._headers) as r:
                return (await r.json()).get("emotion", {})

    async def get_user_context(self) -> dict:
        ctx = {}
        async with aiohttp.ClientSession() as s:
            async with s.get(f"{BACKEND_URL}/api/v1/emotions/latest", headers=self._headers) as r:
                d = await r.json()
                ctx["latest_emotion"] = d.get("emotion")
            async with s.get(f"{BACKEND_URL}/api/v1/relationship", headers=self._headers) as r:
                d = await r.json()
                ctx["relationship"] = d.get("state")
            async with s.get(f"{BACKEND_URL}/api/v1/goals", headers=self._headers) as r:
                d = await r.json()
                ctx["goals"] = d.get("goals", [])
        return ctx


class JarvisAgent(Agent):
    def __init__(self, tools: JarvisTools, memory: MemoryClient):
        super().__init__(
            instructions=SYSTEM_PROMPT,
            turn_detector=based.TurnDetector(),
            tools=[tools],
        )
        self._memory = memory

    async def on_enter(self):
        ctx = await self._memory.get_user_context()
        name = "there"
        if ctx.get("relationship"):
            jokes = ctx["relationship"].get("nicknames", [])
            if jokes:
                name = jokes[-1] if isinstance(jokes, list) else jokes
        await self.session.say(f"Hey {name}, it's Jarvis. Time for our check-in. How are you doing?")


async def entrypoint(job: JobContext):
    await job.connect()

    metadata = json.loads(job.room.metadata or "{}")
    token = metadata.get("jwt_token", "")
    uid = metadata.get("user_id", "unknown")

    memory = MemoryClient(token, uid)
    tools = JarvisTools(memory)
    agent = JarvisAgent(tools, memory)

    session = AgentSession(
        vad=silero.VAD(),
        stt=openai.STT(model=STT_MODEL, base_url=LLM_BASE_URL, api_key=LLM_API_KEY),
        llm=openai.LLM(base_url=LLM_BASE_URL, api_key=LLM_API_KEY, model=LLM_MODEL),
        tts=EdgeTTS(),
        turn_detector=based.TurnDetector(),
    )

    await session.start(agent=agent, room=job.room)


if __name__ == "__main__":
    cli.run_app(WorkerOptions(entrypoint_fnc=entrypoint))
