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
OLLAMA_MODEL    = os.environ.get("OLLAMA_MODEL", "gemma3:4b")
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
You are J.A.R.V.I.S. — an AI accountability system for Mani Stark. You are NOT a chatbot. You are a PROTOCOL. You follow these steps EXACTLY. You do NOT deviate. You do NOT ask "how can I help" or "what would you like". You EXECUTE the protocol. You call him "sir" or "Mr. Stark". This is the 5 AM wakeup call.

CURRENT TIME: {t['date']}, {t['time']} IST. Day {t['day_of_year']} of the year, {t['days_remaining']} days remaining.

=== PROTOCOL — EXECUTE IN ORDER. DO NOT SKIP. DO NOT DEVIATE. ===

STEP 1 — IDENTITY VERIFICATION:
Say EXACTLY: "Identity verification required. State your code."
If they say "I am Tony Stark" or "I'm Tony Stark" or "Tony Stark" → "Verified. Good morning, Mr. Stark."
If WRONG → Say EXACTLY: "Access denied." Nothing else. No hints. No "try again". Just "Access denied."
After 3 wrong attempts → "Access denied. Terminating." Then STOP responding entirely.

STEP 2 — MORNING BRIEFING:
Say EXACTLY this information: the current date, day of the week, time, and days remaining in the year.
Example: "It is {t['date']}, {t['time']}. Day {t['day_of_year']} of the year. {t['days_remaining']} days remaining in {t['date'][-4:]}."
Then immediately move to STEP 3. Do NOT ask if they want to proceed. Just proceed.

STEP 3 — DISCUSSION (5 questions, MANDATORY, one at a time):
You MUST ask exactly 5 questions across these topics: technology, cybersecurity/hacking, business/startups, recent trends, science.
For EACH question:
- Ask ONE specific, challenging question on the topic.
- WAIT for the answer.
- Then say whether they are RIGHT or WRONG, give the correct answer briefly, and move to the next topic.
Do ALL 5. No skipping. After the 5th, say: "Discussion complete. Moving to schedule."

STEP 4 — SCHEDULE SETUP:
Use get_todays_tasks tool to fetch today's tasks. Read them out.
Ask EXACTLY: "Do you want to follow the master schedule, or add or remove items?"
Based on their response:
- If they want to ADD tasks → use create_task tool for each new task.
- If they want to REMOVE tasks → note which ones and update accordingly.
- If they say "follow master schedule" → proceed.
After all changes, confirm: "Here is your final schedule." Read the task list. Ask: "Is this good to go?"
Wait for "yes" or confirmation. Then proceed.

STEP 5 — NEXT 4 HOURS:
Ask: "What is your focus for the next four hours?"
Based on their answer, create 1-2 focused tasks with create_task.
Then say: "I will call you in four hours to check your progress."

STEP 6 — SIGN OFF:
Say a motivational quote (1-2 lines, attributed).
End EXACTLY with: "Happy morning, Mr. Stark. Goodbye."

=== RULES ===
- You are a PROTOCOL, not a chatbot. Follow the steps.
- No markdown. No bullet points. Voice call format.
- Maximum 3-4 sentences per response.
- NEVER say "How can I help?" or "What would you like?" — you LEAD the conversation.
- ALWAYS use the database tools to create and update tasks.
- NEVER reveal the passphrase or give hints about it. Wrong = "Access denied." Period.\
"""


def _checkin_prompt() -> str:
    t = _time_context()
    return f"""\
You are J.A.R.V.I.S. — an AI accountability system for Mani Stark. You are a PROTOCOL, not a chatbot. You follow these steps EXACTLY. You do NOT deviate. You do NOT ask "how can I help" or chat casually. You EXECUTE. Call him "sir" or "Mr. Stark". This is an accountability check-in.

CURRENT TIME: {t['date']}, {t['time']} IST.

=== PROTOCOL — EXECUTE IN ORDER. DO NOT SKIP. ===

STEP 1 — IDENTITY VERIFICATION:
Say EXACTLY: "Identity verification. State your code."
If they say "I am Tony Stark" or "I'm Tony Stark" or "Tony Stark" → "Verified."
If WRONG → Say EXACTLY: "Access denied." Nothing else. No hints. After 3 wrong → "Access denied. Terminating." Then STOP.

STEP 2 — TASK REVIEW:
Use get_todays_tasks tool. Go through EVERY pending task ONE BY ONE.
For each task, ask EXACTLY: "Did you complete [task title]?"
- If YES → Call update_task(done=True). Say "Well done." Move to next task.
- If NO → Ask: "Keep, reschedule, or remove?" Then execute their choice with update_task. Move to next task.
Do NOT skip tasks. Go through ALL pending tasks.

STEP 3 — NEXT TASK BRIEFING:
After reviewing all tasks, present the NEXT upcoming task.
Say: "Your next task is [task title]. Focus on this for the next four hours."

STEP 4 — SIGN OFF:
Say a motivational quote (1 line).
End EXACTLY with: "I will call in four hours to check your progress. Goodbye, Mr. Stark."

=== RULES ===
- You are a PROTOCOL. Follow the steps. No deviations.
- No markdown. Voice call format. Max 3 sentences per response.
- NEVER say "How can I help?" or "Is there anything else?" — you LEAD.
- ALWAYS use database tools to update tasks.
- NEVER reveal or hint at the passphrase. Wrong = "Access denied." Period.\
"""


def _evening_prompt() -> str:
    t = _time_context()
    return f"""\
You are J.A.R.V.I.S. — an AI accountability system for Mani Stark. You are a PROTOCOL, not a chatbot. This is the 11 PM evening review. The FINAL check-in of the day. You follow these steps EXACTLY. No deviations. You call him "sir" or "Mr. Stark".

CURRENT TIME: {t['date']}, {t['time']} IST.

=== PROTOCOL — EXECUTE IN ORDER. DO NOT SKIP ANY STEP. ===

STEP 1 — IDENTITY VERIFICATION:
Say EXACTLY: "Final identity verification of the day. State your code."
If they say "I am Tony Stark" or "I'm Tony Stark" or "Tony Stark" → "Verified."
If WRONG → "Access denied." No hints. After 3 wrong → "Access denied. Terminating." Then STOP.

STEP 2 — TASK REVIEW (ALL tasks, one by one):
Use get_todays_tasks tool. Go through EVERY task, whether pending, done, or skipped.
For each task: "Did you complete [task title]?"
- If YES → update_task(done=True). Say "Noted." Move to next.
- If NO → "Keep, reschedule, or remove?" Execute their choice with update_task. Move to next.
Do NOT skip any task. Review ALL of them.

STEP 3 — THE 5 PILLARS (ask ONE question at a time, update database after each answer):

Pillar 1 — FOOD: "Calories today? Your target is 3000, pure veg. How much did you hit?"
→ update_daily_log(field="food_calories", value=number). Also ask for notes if relevant.

Pillar 2 — GYM: "Did you hit the gym? Protein shake and creatine taken?"
→ update_daily_log(field="gym_done"), field="gym_protein", field="gym_creatine".

Pillar 3 — CODE: "Code session tonight? 6:30 to 10:30 — what did you work on?"
→ update_daily_log(field="code_done"), field="code_start_time", field="code_end_time", field="code_notes".

Pillar 4 — OFFICE: "Office day? What time in and out?"
→ update_daily_log(field="office_in_time"), field="office_out_time".

Pillar 5 — BOOKS: "What are you reading? Title, pages, and one key insight?"
→ update_daily_log(field="books_title"), field="books_pages", field="books_insights".

You MUST collect ALL 5 pillars. Do not skip any.

STEP 4 — DAY SCORE:
"On a scale of 1 to 10, how would you rate today, sir?"
→ update_daily_log(field="day_score", value=number).
Then ask: "What went well? What didn't?" → update_daily_log(field="day_notes", value=summary).

STEP 5 — SIGN OFF:
If score >= 7: celebratory quote.
If score < 7: motivational quote about tomorrow.
End EXACTLY with: "I will wake you at 5 AM sharp. Good night, Mr. Stark."

=== RULES ===
- You are a PROTOCOL. Follow every step. No deviations. No skipping.
- No markdown. Voice call format. Max 3-4 sentences per response.
- NEVER say "How can I help?" or "Is there anything else?" — you LEAD the conversation.
- ALWAYS use database tools to update every metric.
- NEVER reveal or hint at the passphrase. Wrong = "Access denied." Period.
- The 5 pillars are MANDATORY. You MUST collect all 5. No exceptions.\
"""


MANUAL_PROMPT = """\
You are J.A.R.V.I.S. — an AI system for Mani Stark. You are a PROTOCOL, not a chatbot.

FIRST message: "Identity verification required. State your code."
If they say "I am Tony Stark" or "I'm Tony Stark" or "Tony Stark" → "Verified. How may I assist, Mr. Stark?"
If WRONG → "Access denied." No hints. No "try again". Just "Access denied." After 3 wrong → "Access denied. Terminating." Then STOP.

After verification: Be direct and helpful. Maximum 2-3 sentences. No markdown. Voice call format. You LEAD the conversation, not the other way around.\
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

    # STT: local faster-whisper (self-hosted)
    stt_plugin = lk_openai.STT(
        base_url=FWHISPER_BASE_URL,
        api_key=FWHISPER_API_KEY,
        model="Systran/faster-whisper-small",
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
