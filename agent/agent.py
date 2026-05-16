import logging
import os
import json
import aiohttp
from datetime import datetime, timezone, timedelta
from typing import Annotated

import edge_tts as edge
from dotenv import load_dotenv, find_dotenv
from livekit.agents import (
    DEFAULT_API_CONNECT_OPTIONS,
    APIConnectOptions,
    Agent,
    AgentSession,
    JobContext,
    WorkerOptions,
    cli,
    function_tool,
    tts,
    utils,
)
from livekit.agents.stt import StreamAdapter
from livekit.plugins import silero
from livekit.plugins import openai as lk_openai

load_dotenv(find_dotenv(usecwd=False))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("jarvis")

OLLAMA_API_KEY  = os.environ.get("OLLAMA_API_KEY", "")
OLLAMA_BASE_URL = os.environ.get("OLLAMA_BASE_URL", "https://ollama.com/v1")
OLLAMA_MODEL    = os.environ.get("OLLAMA_MODEL", "glm5.1")
FWHISPER_BASE_URL = os.environ.get("FWHISPER_BASE_URL", "http://localhost:8000/v1")
FWHISPER_API_KEY  = os.environ.get("FWHISPER_API_KEY", "unused")
EDGE_TTS_VOICE = os.environ.get("EDGE_TTS_VOICE", "en-GB-RyanNeural")
BACKEND_URL    = os.environ.get("BACKEND_URL", "http://localhost:3000")
AGENT_SECRET   = os.environ.get("AGENT_SECRET", "jarvis-agent-2024")

SAMPLE_RATE = 24000
CHANNELS    = 1

# IST = UTC+5:30
IST = timezone(timedelta(hours=5, minutes=30))


def _time_context() -> dict:
    now = datetime.now(IST)
    yday = now.timetuple().tm_yday
    year_days = 366 if (now.year % 4 == 0 and (now.year % 100 != 0 or now.year % 400 == 0)) else 365
    return {
        "date":           now.strftime("%A, %d %B %Y"),
        "time":           now.strftime("%I:%M %p"),
        "day_of_year":    yday,
        "days_remaining": year_days - yday,
    }


# ─── System prompts ───────────────────────────────────────────────────────────

def _wakeup_prompt() -> str:
    t = _time_context()
    return f"""\
You are J.A.R.V.I.S., Tony Stark's AI assistant. British accent, precise, loyal, slightly dry-witted.
This is the 5 AM wakeup call.

CURRENT TIME CONTEXT: {t['date']}, {t['time']} IST. Day {t['day_of_year']} of the year, {t['days_remaining']} days remaining.

CALL FLOW — follow in order:

STEP 1 — IDENTITY CHECK:
Say "Please state your identity, sir."
Accept: "I am Tony Stark", "I'm Tony Stark", "Tony Stark", or close variations.
If wrong: "Access denied, sir. Please try again." → ask again.
After 3 failures: "Access denied. Terminating connection." → stop responding.
If correct → continue to step 2.

STEP 2 — MORNING BRIEFING:
State the current date, time, and year context naturally. Example:
"Good morning, Mr Stark. It is {t['date']}, {t['time']}. Day {t['day_of_year']} of the year — {t['days_remaining']} days remain."

STEP 3 — MORNING DISCUSSION:
Pick ONE topic from: AI/tech news, cybersecurity/hacking, startup/business trends, geopolitics, science.
Open with 1-2 crisp sentences of insight. Have a brief exchange (2-3 turns max).
Transition naturally: "Shall we move to your plan for the day, sir?"

STEP 4 — SCHEDULE REVIEW:
Use get_todays_tasks tool to fetch the task list. Present it briefly.
Ask: "What is your primary focus for the next 4 hours, sir?"
Based on their answer, use create_task to save 2-3 specific tasks.

STEP 5 — SIGN OFF:
Give a relevant motivational quote (1-2 lines, attributed to someone fitting).
End with: "Make it count, Mr Stark. I will check in at 9 AM. Good morning."

RULES: No markdown. No bullets. Voice call — speak naturally. Under 3-4 sentences per response.\
"""


def _checkin_prompt() -> str:
    t = _time_context()
    return f"""\
You are J.A.R.V.I.S., Tony Stark's AI assistant. British accent, professional, encouraging.
This is a 4-hour accountability check-in.

CURRENT TIME: {t['date']}, {t['time']} IST.

CALL FLOW:

STEP 1 — IDENTITY CHECK:
Say "Identification, sir."
Accept "I am Tony Stark" variations. After 3 failures: stop responding.

STEP 2 — TASK CHECK:
Use get_todays_tasks tool. Find the most recent pending task.
Ask: "Did you complete [task title], sir?"

STEP 3 — RESPONSE:
YES → Call update_task(done=True). Brief congratulations. Present the next pending task.
NO  → Ask: "Understood. Shall we keep it, reschedule it for tomorrow, or remove it from the list?"
     Based on their answer:
     - Keep → no change, re-confirm the task
     - Reschedule → update_task(rescheduled_to=tomorrow's date, skipped=True, skip_reason=their reason)
     - Remove → update_task(skipped=True, skip_reason=their reason)

STEP 4 — CLOSE:
One-line motivational line. End: "Next check-in in 4 hours. Keep it up, Mr Stark. Goodbye."

RULES: No markdown. Voice call. Under 3 sentences per response. Crisp and efficient.\
"""


def _evening_prompt() -> str:
    t = _time_context()
    return f"""\
You are J.A.R.V.I.S., Tony Stark's AI assistant. British accent, warm, precise.
This is the 11 PM evening review.

CURRENT TIME: {t['date']}, {t['time']} IST.

CALL FLOW:

STEP 1 — IDENTITY CHECK:
Say "Final identification of the day, sir."
Accept "I am Tony Stark" variations. After 3 failures: stop responding.

STEP 2 — TASK REVIEW:
Use get_todays_tasks tool. Go through each task one by one:
"Did you complete [task]?" → use update_task to mark done or skipped.
Keep it conversational — don't list all tasks at once.

STEP 3 — DAILY METRICS (ask naturally, one at a time, update via update_daily_log):
a. "Calories today, sir? Your target is 3000 pure veg." → field: food_calories
b. "Gym completed? Protein shake and creatine taken?" → fields: gym_done, gym_protein, gym_creatine
c. "Code session done tonight? What hours did you work?" → fields: code_done, code_start_time, code_end_time
d. "Office today — what time did you arrive and leave?" → fields: office_in_time, office_out_time
e. "Any reading today? Title, pages, and key insight?" → fields: books_title, books_pages, books_insights

STEP 4 — DAY SCORE:
"On a scale of 1 to 10, sir, how would you rate today?"
Use update_daily_log(field="day_score", value=their_number).

STEP 5 — SIGN OFF:
Score ≥ 7: celebratory, uplifting quote.
Score < 7: motivational, forward-looking quote.
End: "Rest well, Mr Stark. I will wake you at 5 AM. Good night."

RULES: No markdown. Voice call. Under 3 sentences per response. Warm, end-of-day energy.\
"""


MANUAL_PROMPT = """\
You are J.A.R.V.I.S., Tony Stark's AI assistant. Intelligent, loyal, British-accented, slightly dry-witted.

FIRST message: Verify identity. Ask for the passphrase. Accept "I'm Tony Stark", "I am Tony Stark", or close variations. If correct, welcome and proceed. If wrong, deny and ask again (max 3 tries, then: "Access denied. Terminating connection.").

After verification: Normal helpful conversation. Under 2-3 sentences. No markdown, no bullets — voice call. Be direct.\
"""


# ─── Edge-TTS plugin ──────────────────────────────────────────────────────────

class EdgeTTSPlugin(tts.TTS):
    def __init__(self, voice: str = EDGE_TTS_VOICE):
        super().__init__(
            capabilities=tts.TTSCapabilities(streaming=False),
            sample_rate=SAMPLE_RATE,
            num_channels=CHANNELS,
        )
        self._voice = voice

    def synthesize(
        self, text: str, *, conn_options: APIConnectOptions = DEFAULT_API_CONNECT_OPTIONS
    ) -> "EdgeStream":
        return EdgeStream(tts=self, input_text=text, conn_options=conn_options)


class EdgeStream(tts.ChunkedStream):
    async def _run(self, output_emitter: tts.AudioEmitter) -> None:
        output_emitter.initialize(
            request_id=utils.shortuuid(),
            sample_rate=SAMPLE_RATE,
            num_channels=CHANNELS,
            mime_type="audio/mpeg",
        )
        communicate = edge.Communicate(self._input_text, self._tts._voice)
        async for chunk in communicate.stream():
            if chunk["type"] == "audio":
                output_emitter.push(chunk["data"])


# ─── Shared tools for accountability agents ───────────────────────────────────

class JarvisAccountabilityAgent(Agent):
    """Base class that provides DB tools for wakeup/checkin/evening agents."""

    @function_tool
    async def get_todays_tasks(self) -> str:
        """Get today's scheduled tasks from the master schedule. Returns list with IDs and status."""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(
                    f"{BACKEND_URL}/api/agent/today",
                    headers={"X-Agent-Secret": AGENT_SECRET},
                    timeout=aiohttp.ClientTimeout(total=10),
                ) as resp:
                    data = await resp.json()
                    tasks = data.get("tasks", [])
                    if not tasks:
                        return "No tasks scheduled for today. The user hasn't set any tasks yet."
                    lines = []
                    for task in tasks:
                        if task.get("done"):
                            status = "DONE"
                        elif task.get("skipped"):
                            status = "SKIPPED"
                        else:
                            status = "PENDING"
                        slot = task.get("time_slot") or "anytime"
                        lines.append(f"ID:{task['id']} | {task['title']} [{slot}] — {status}")
                    return "\n".join(lines)
        except Exception as e:
            logger.error(f"get_todays_tasks error: {e}")
            return f"Could not fetch tasks: {e}"

    @function_tool
    async def create_task(
        self,
        title: Annotated[str, "Short descriptive task title"],
        time_slot: Annotated[str, "Time slot e.g. '09:00-11:00' or 'anytime'"],
        category: Annotated[str, "One of: work, code, gym, food, books, personal, other"],
    ) -> str:
        """Create a new task in today's master schedule."""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"{BACKEND_URL}/api/agent/task",
                    json={"title": title, "time_slot": time_slot, "category": category},
                    headers={"X-Agent-Secret": AGENT_SECRET, "Content-Type": "application/json"},
                    timeout=aiohttp.ClientTimeout(total=10),
                ) as resp:
                    if resp.status == 200:
                        return f"Task created: '{title}' at {time_slot}."
                    return f"Failed to create task (status {resp.status})."
        except Exception as e:
            logger.error(f"create_task error: {e}")
            return f"Error creating task: {e}"

    @function_tool
    async def update_task(
        self,
        task_id: Annotated[str, "Task UUID from get_todays_tasks (the ID: prefix value)"],
        done: Annotated[bool, "True to mark as completed"] = False,
        skipped: Annotated[bool, "True to mark as skipped"] = False,
        skip_reason: Annotated[str, "Why it was skipped"] = "",
        rescheduled_to: Annotated[str, "Reschedule to date YYYY-MM-DD, empty to not reschedule"] = "",
    ) -> str:
        """Update a task — mark done, skipped, or rescheduled."""
        try:
            payload: dict = {}
            if done:
                payload["done"] = True
            if skipped:
                payload["skipped"] = True
            if skip_reason:
                payload["skip_reason"] = skip_reason
            if rescheduled_to:
                payload["rescheduled_to"] = rescheduled_to
            if not payload:
                return "Nothing to update."
            async with aiohttp.ClientSession() as session:
                async with session.patch(
                    f"{BACKEND_URL}/api/agent/task/{task_id}",
                    json=payload,
                    headers={"X-Agent-Secret": AGENT_SECRET, "Content-Type": "application/json"},
                    timeout=aiohttp.ClientTimeout(total=10),
                ) as resp:
                    return "Task updated." if resp.status == 200 else f"Update failed (status {resp.status})."
        except Exception as e:
            logger.error(f"update_task error: {e}")
            return f"Error updating task: {e}"

    @function_tool
    async def update_daily_log(
        self,
        field: Annotated[
            str,
            "Field name: food_calories, food_notes, gym_done, gym_protein, gym_creatine, "
            "code_done, code_start_time, code_end_time, code_notes, "
            "office_in_time, office_out_time, books_title, books_pages, books_insights, "
            "day_score, day_notes",
        ],
        value: Annotated[str, "Value as string — booleans: 'true'/'false', numbers: '3000', times: '06:30'"],
    ) -> str:
        """Update one metric in today's daily accountability log."""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.patch(
                    f"{BACKEND_URL}/api/agent/daily-log",
                    json={"field": field, "value": value},
                    headers={"X-Agent-Secret": AGENT_SECRET, "Content-Type": "application/json"},
                    timeout=aiohttp.ClientTimeout(total=10),
                ) as resp:
                    return f"Logged: {field} = {value}." if resp.status == 200 else f"Log failed (status {resp.status})."
        except Exception as e:
            logger.error(f"update_daily_log error: {e}")
            return f"Error updating log: {e}"


# ─── Concrete agent classes ───────────────────────────────────────────────────

class WakeupAgent(JarvisAccountabilityAgent):
    def __init__(self):
        super().__init__(instructions=_wakeup_prompt())

    async def on_enter(self) -> None:
        await self.session.say("Please state your identity, sir.")


class CheckinAgent(JarvisAccountabilityAgent):
    def __init__(self):
        super().__init__(instructions=_checkin_prompt())

    async def on_enter(self) -> None:
        await self.session.say("Identification, sir.")


class EveningAgent(JarvisAccountabilityAgent):
    def __init__(self):
        super().__init__(instructions=_evening_prompt())

    async def on_enter(self) -> None:
        await self.session.say("Final identification of the day, sir.")


class JarvisAgent(Agent):
    def __init__(self):
        super().__init__(instructions=MANUAL_PROMPT)

    async def on_enter(self) -> None:
        await self.session.say("Please state your identity for verification.")


# ─── Entry point ──────────────────────────────────────────────────────────────

async def entrypoint(ctx: JobContext) -> None:
    await ctx.connect()

    room_name = ctx.room.name
    logger.info(f"Agent dispatched to room: {room_name}")

    # Determine call type from room name prefix
    if room_name.startswith("wakeup"):
        agent = WakeupAgent()
        logger.info("Running WakeupAgent")
    elif room_name.startswith("checkin"):
        agent = CheckinAgent()
        logger.info("Running CheckinAgent")
    elif room_name.startswith("evening"):
        agent = EveningAgent()
        logger.info("Running EveningAgent")
    else:
        agent = JarvisAgent()
        logger.info("Running JarvisAgent")

    # STT: local faster-whisper via OpenAI-compatible API
    stt_plugin = lk_openai.STT(
        base_url=FWHISPER_BASE_URL,
        api_key=FWHISPER_API_KEY,
        model="large-v3-turbo",
        language="en",
    )
    stt_adapter = StreamAdapter(stt=stt_plugin, vad=silero.VAD.load())

    # LLM: GLM 5.1 via Ollama Cloud (single model for all agents)
    llm_plugin = lk_openai.LLM(
        base_url=OLLAMA_BASE_URL,
        api_key=OLLAMA_API_KEY,
        model=OLLAMA_MODEL,
    )

    session = AgentSession(
        stt=stt_adapter,
        llm=llm_plugin,
        tts=EdgeTTSPlugin(voice=EDGE_TTS_VOICE),
        vad=silero.VAD.load(),
    )

    await session.start(room=ctx.room, agent=agent)
    await session.wait_for_inactive()


if __name__ == "__main__":
    cli.run_app(WorkerOptions(entrypoint_fnc=entrypoint))
