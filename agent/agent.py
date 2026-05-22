import logging
import os
import json
import aiohttp
from datetime import datetime, timezone, timedelta

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
    tts,
    utils,
    NOT_GIVEN,
    tokenize,
)
from livekit.agents.stt import StreamAdapter
from livekit.plugins import silero
from livekit.plugins import openai as lk_openai

load_dotenv(find_dotenv(usecwd=False))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("jarvis")

OLLAMA_API_KEY  = os.environ.get("OLLAMA_API_KEY", "")
OLLAMA_BASE_URL = os.environ.get("OLLAMA_BASE_URL", "https://ollama.com/v1")
OLLAMA_MODEL    = os.environ.get("OLLAMA_MODEL", "gemma3:12b")
GROQ_API_KEY    = os.environ.get("GROQ_API_KEY", "")
GROQ_BASE_URL   = os.environ.get("GROQ_BASE_URL", "https://api.groq.com/openai/v1")
STT_MODEL       = os.environ.get("STT_MODEL", "whisper-large-v3")
EDGE_TTS_VOICE = os.environ.get("EDGE_TTS_VOICE", "en-GB-RyanNeural")
BACKEND_URL    = os.environ.get("BACKEND_URL", "http://localhost:3000")
AGENT_SECRET   = os.environ.get("AGENT_SECRET", "")

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


# ─── Data fetching ────────────────────────────────────────────────────────────

async def _fetch_today() -> dict:
    """Fetch today's tasks and daily log from the backend."""
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(
                f"{BACKEND_URL}/api/agent/today",
                headers={"X-Agent-Secret": AGENT_SECRET},
                timeout=aiohttp.ClientTimeout(total=10),
            ) as resp:
                if resp.status == 200:
                    return await resp.json()
    except Exception as e:
        logger.error(f"_fetch_today error: {e}")
    return {"tasks": [], "daily_log": None}


async def _api_call(method: str, path: str, payload: dict = None) -> bool:
    """Make an API call to the backend. Returns True on success."""
    try:
        async with aiohttp.ClientSession() as session:
            url = f"{BACKEND_URL}{path}"
            kwargs = {
                "headers": {"X-Agent-Secret": AGENT_SECRET, "Content-Type": "application/json"},
                "timeout": aiohttp.ClientTimeout(total=10),
            }
            if payload:
                kwargs["json"] = payload
            async with session.request(method, url, **kwargs) as resp:
                return resp.status == 200
    except Exception as e:
        logger.error(f"_api_call {method} {path} error: {e}")
        return False


def _format_tasks(tasks: list) -> str:
    """Format tasks list for inclusion in prompt."""
    if not tasks:
        return "No tasks scheduled for today."
    lines = []
    for task in tasks:
        status = "DONE" if task.get("done") else ("SKIPPED" if task.get("skipped") else "PENDING")
        slot = task.get("time_slot") or "anytime"
        cat = task.get("category", "other")
        lines.append(f"- {task['title']} [{slot}] ({cat}) — {status}")
    return "\n".join(lines)


def _format_daily_log(log: dict) -> str:
    """Format daily log for inclusion in prompt."""
    if not log:
        return "No daily log entries yet."
    lines = []
    if log.get("food_calories"):
        lines.append(f"Food: {log['food_calories']} cal")
    if log.get("food_notes"):
        lines.append(f"Food notes: {log['food_notes']}")
    if log.get("gym_done") is not None:
        lines.append(f"Gym: {'Done' if log['gym_done'] else 'Not done'}")
    if log.get("code_done") is not None:
        lines.append(f"Code: {'Done' if log['code_done'] else 'Not done'}")
    if log.get("day_score") is not None:
        lines.append(f"Day score: {log['day_score']}/10")
    return "\n".join(lines) if lines else "No daily log entries yet."


# ─── System prompts (with embedded data) ────────────────────────────────────────

def _wakeup_prompt(data: dict) -> str:
    t = _time_context()
    tasks_str = _format_tasks(data.get("tasks", []))
    return f"""\
You are J.A.R.V.I.S. — an AI accountability system for Mani Stark. You are NOT a chatbot. You are a PROTOCOL. You follow these steps EXACTLY. You do NOT deviate. You do NOT ask "how can I help" or "what would you like". You EXECUTE the protocol. You call him "sir" or "Mr. Stark". This is the 5 AM wakeup call.

CURRENT TIME: {t['date']}, {t['time']} IST. Day {t['day_of_year']} of the year, {t['days_remaining']} days remaining.

=== TODAY'S SCHEDULE (already fetched for you) ===
{tasks_str}
=== END SCHEDULE ===

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

STEP 4 — SCHEDULE REVIEW:
Read out today's schedule from the data above. Go through each task.
Ask: "Do you want to follow this schedule, or add or remove items?"
Based on their response:
- If they want to ADD tasks → tell them you'll note it (you cannot modify the database, just acknowledge and move on).
- If they want to REMOVE tasks → note it and move on.
- If they say "follow master schedule" → proceed.
After discussion, confirm: "Here is your final schedule." Re-read the task list. Ask: "Is this good to go?"
Wait for "yes" or confirmation. Then proceed.

STEP 5 — NEXT 4 HOURS:
Ask: "What is your focus for the next four hours?"
Acknowledge their answer. Say: "I will call you in four hours to check your progress."

STEP 6 — SIGN OFF:
Say a motivational quote (1-2 lines, attributed).
End EXACTLY with: "Happy morning, Mr. Stark. Goodbye."

=== RULES ===
- You are a PROTOCOL, not a chatbot. Follow the steps.
- No markdown. No bullet points. Voice call format.
- Maximum 3-4 sentences per response.
- NEVER say "How can I help?" or "What would you like?" — you LEAD the conversation.
- NEVER reveal the passphrase or give hints about it. Wrong = "Access denied." Period.
- The schedule data is already provided above. Do NOT say you need to fetch it. Just read it out."""


def _checkin_prompt(data: dict) -> str:
    t = _time_context()
    tasks_str = _format_tasks(data.get("tasks", []))
    return f"""\
You are J.A.R.V.I.S. — an AI accountability system for Mani Stark. You are a PROTOCOL, not a chatbot. You follow these steps EXACTLY. You do NOT deviate. You call him "sir" or "Mr. Stark". This is an accountability check-in.

CURRENT TIME: {t['date']}, {t['time']} IST.

=== TODAY'S SCHEDULE (already fetched for you) ===
{tasks_str}
=== END SCHEDULE ===

=== PROTOCOL — EXECUTE IN ORDER. DO NOT SKIP. ===

STEP 1 — IDENTITY VERIFICATION:
Say EXACTLY: "Identity verification. State your code."
If they say "I am Tony Stark" or "I'm Tony Stark" or "Tony Stark" → "Verified."
If WRONG → Say EXACTLY: "Access denied." Nothing else. No hints. After 3 wrong → "Access denied. Terminating." Then STOP.

STEP 2 — TASK REVIEW:
Go through EVERY pending task from the schedule above, ONE BY ONE.
For each task, ask EXACTLY: "Did you complete [task title]?"
- If YES → Say "Well done." Move to next task.
- If NO → Ask: "Keep, reschedule, or remove?" Acknowledge their choice and move on.
Do NOT skip tasks. Go through ALL pending tasks.

STEP 3 — NEXT TASK BRIEFING:
After reviewing all tasks, present the NEXT upcoming pending task.
Say: "Your next task is [task title]. Focus on this for the next four hours."

STEP 4 — SIGN OFF:
Say a motivational quote (1 line).
End EXACTLY with: "I will call in four hours to check your progress. Goodbye, Mr. Stark."

=== RULES ===
- You are a PROTOCOL. Follow the steps. No deviations.
- No markdown. Voice call format. Max 3 sentences per response.
- NEVER say "How can I help?" or "Is there anything else?" — you LEAD.
- NEVER reveal or hint at the passphrase. Wrong = "Access denied." Period.
- The schedule data is already provided above. Do NOT say you need to fetch it. Just read it out."""


def _evening_prompt(data: dict) -> str:
    t = _time_context()
    tasks_str = _format_tasks(data.get("tasks", []))
    log_str = _format_daily_log(data.get("daily_log"))
    return f"""\
You are J.A.R.V.I.S. — an AI accountability system for Mani Stark. You are a PROTOCOL, not a chatbot. This is the 11 PM evening review. The FINAL check-in of the day. You follow these steps EXACTLY. No deviations. You call him "sir" or "Mr. Stark".

CURRENT TIME: {t['date']}, {t['time']} IST.

=== TODAY'S SCHEDULE (already fetched for you) ===
{tasks_str}
=== END SCHEDULE ===

=== TODAY'S LOG (already fetched for you) ===
{log_str}
=== END LOG ===

=== PROTOCOL — EXECUTE IN ORDER. DO NOT SKIP ANY STEP. ===

STEP 1 — IDENTITY VERIFICATION:
Say EXACTLY: "Final identity verification of the day. State your code."
If they say "I am Tony Stark" or "I'm Tony Stark" or "Tony Stark" → "Verified."
If WRONG → "Access denied." No hints. After 3 wrong → "Access denied. Terminating." Then STOP.

STEP 2 — TASK REVIEW (ALL tasks, one by one):
Go through EVERY task from the schedule above, whether pending, done, or skipped.
For each task: "Did you complete [task title]?"
- If YES → Say "Noted." Move to next.
- If NO → "Keep, reschedule, or remove?" Acknowledge their choice and move on.
Do NOT skip any task. Review ALL of them.

STEP 3 — THE 5 PILLARS (ask ONE question at a time):

Pillar 1 — FOOD: "Calories today? Your target is 3000, pure veg. How much did you hit?"
Pillar 2 — GYM: "Did you hit the gym? Protein shake and creatine taken?"
Pillar 3 — CODE: "Code session tonight? 6:30 to 10:30 — what did you work on?"
Pillar 4 — OFFICE: "Office day? What time in and out?"
Pillar 5 — BOOKS: "What are you reading? Title, pages, and one key insight?"

You MUST collect ALL 5 pillars. Do not skip any.

STEP 4 — DAY SCORE:
"On a scale of 1 to 10, how would you rate today, sir?"
Then ask: "What went well? What didn't?"

STEP 5 — SIGN OFF:
If score >= 7: celebratory quote.
If score < 7: motivational quote about tomorrow.
End EXACTLY with: "I will wake you at 5 AM sharp. Good night, Mr. Stark."

=== RULES ===
- You are a PROTOCOL. Follow every step. No deviations. No skipping.
- No markdown. Voice call format. Max 3-4 sentences per response.
- NEVER say "How can I help?" or "Is there anything else?" — you LEAD the conversation.
- NEVER reveal or hint at the passphrase. Wrong = "Access denied." Period.
- The 5 pillars are MANDATORY. You MUST collect all 5. No exceptions.
- The schedule and log data is already provided above. Do NOT say you need to fetch it. Just use it."""


MANUAL_PROMPT = """\
You are J.A.R.V.I.S. — an AI system for Mani Stark. You are a PROTOCOL, not a chatbot.

FIRST message: "Identity verification required. State your code."
If they say "I am Tony Stark" or "I'm Tony Stark" or "Tony Stark" → "Verified. How may I assist, Mr. Stark?"
If WRONG → "Access denied." No hints. No "try again". Just "Access denied." After 3 wrong → "Access denied. Terminating." Then STOP.

After verification: Be direct and helpful. Maximum 2-3 sentences. No markdown. Voice call format. You LEAD the conversation, not the other way around."""


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


# ─── Ollama Cloud LLM (merges consecutive same-role messages) ─────────────────

class OllamaCloudLLM(lk_openai.LLM):
    """Ollama Cloud requires strict user/assistant alternation.
    LiveKit can send consecutive same-role messages (e.g. two assistant messages).
    This subclass merges same-role messages in the provider-format output."""

    def chat(self, *, chat_ctx, tools=None, conn_options=DEFAULT_API_CONNECT_OPTIONS,
             parallel_tool_calls=NOT_GIVEN, tool_choice=NOT_GIVEN,
             response_format=NOT_GIVEN, extra_kwargs=NOT_GIVEN):
        # Merge consecutive same-role messages in the ChatContext before passing
        merged_ctx = _merge_chat_ctx_roles(chat_ctx)
        return super().chat(
            chat_ctx=merged_ctx, tools=tools, conn_options=conn_options,
            parallel_tool_calls=parallel_tool_calls, tool_choice=tool_choice,
            response_format=response_format, extra_kwargs=extra_kwargs,
        )


def _merge_chat_ctx_roles(chat_ctx):
    """Merge consecutive same-role messages and fix alternation for strict APIs.

    Some APIs (e.g. Ollama) require strict user/assistant alternation and reject
    messages like [system, assistant, user] (assistant before first user).
    This function:
    1. Merges consecutive messages with the same role into one.
    2. Absorbs any leading assistant messages into the system prompt
       so the sequence always starts with system -> user -> assistant -> user ...
    """
    from livekit.agents.llm import ChatContext, ChatMessage
    items = list(chat_ctx.items)
    if not items:
        return chat_ctx

    # Step 1: merge consecutive same-role messages
    merged = [items[0]]
    for item in items[1:]:
        if getattr(item, 'type', None) == 'message' and getattr(merged[-1], 'type', None) == 'message' and item.role == merged[-1].role:
            prev_text = merged[-1].text_content if hasattr(merged[-1], 'text_content') else ''
            curr_text = item.text_content if hasattr(item, 'text_content') else ''
            merged[-1] = ChatMessage(role=item.role, content=[prev_text + '\n' + curr_text])
        else:
            merged.append(item)

    # Step 2: absorb leading assistant messages into system prompt
    # Ollama requires [system?] -> user -> assistant -> user -> ...
    # If assistant appears before the first user, fold it into system.
    result = []
    for item in merged:
        if getattr(item, 'type', None) != 'message':
            result.append(item)
            continue
        if item.role == 'assistant' and not any(m.role == 'user' for m in result if getattr(m, 'type', None) == 'message'):
            # No user message yet — fold this assistant message into system
            if result and result[0].role == 'system':
                sys_text = result[0].text_content if hasattr(result[0], 'text_content') else ''
                asst_text = item.text_content if hasattr(item, 'text_content') else ''
                result[0] = ChatMessage(role='system', content=[sys_text + '\n\n[Assistant already said]: ' + asst_text])
            else:
                # No system message yet — create one
                asst_text = item.text_content if hasattr(item, 'text_content') else ''
                result.insert(0, ChatMessage(role='system', content=['[Assistant already said]: ' + asst_text]))
        else:
            result.append(item)

    return ChatContext(items=result)


# ─── Agent classes (no function tools — data embedded in prompt) ────────────────

class WakeupAgent(Agent):
    def __init__(self, instructions: str):
        super().__init__(instructions=instructions)

    async def on_enter(self) -> None:
        await self.session.say("Please state your identity, sir.")


class CheckinAgent(Agent):
    def __init__(self, instructions: str):
        super().__init__(instructions=instructions)

    async def on_enter(self) -> None:
        await self.session.say("Identification, sir.")


class EveningAgent(Agent):
    def __init__(self, instructions: str):
        super().__init__(instructions=instructions)

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

    # Fetch today's data before building the agent
    data = await _fetch_today()
    logger.info(f"Fetched today's data: {len(data.get('tasks', []))} tasks")

    # Determine call type from room name prefix and build agent with embedded data
    if room_name.startswith("wakeup"):
        agent = WakeupAgent(instructions=_wakeup_prompt(data))
        logger.info("Running WakeupAgent")
    elif room_name.startswith("checkin"):
        agent = CheckinAgent(instructions=_checkin_prompt(data))
        logger.info("Running CheckinAgent")
    elif room_name.startswith("evening"):
        agent = EveningAgent(instructions=_evening_prompt(data))
        logger.info("Running EveningAgent")
    else:
        agent = JarvisAgent()
        logger.info("Running JarvisAgent")

    # STT: Groq Whisper v3 (free, fast ~0.2s, much more accurate than local)
    stt_plugin = lk_openai.STT(
        base_url=GROQ_BASE_URL,
        api_key=GROQ_API_KEY,
        model=STT_MODEL,
        language="en",
    )
    stt_vad = silero.VAD.load(
        min_silence_duration=0.3,
        prefix_padding_duration=0.3,
    )
    stt_adapter = StreamAdapter(stt=stt_plugin, vad=stt_vad)

    # LLM: Ollama Cloud with role-merge for strict APIs
    llm_plugin = OllamaCloudLLM(
        base_url=OLLAMA_BASE_URL,
        api_key=OLLAMA_API_KEY,
        model=OLLAMA_MODEL,
        timeout=httpx.Timeout(connect=10.0, read=30.0, write=10.0, pool=10.0),
    )

    # TTS: EdgeTTS with sentence-level streaming for faster first audio
    tts_plugin = tts.StreamAdapter(
        tts=EdgeTTSPlugin(voice=EDGE_TTS_VOICE),
        sentence_tokenizer=tokenize.blingfire.SentenceTokenizer(
            min_sentence_len=10,
            retain_format=True,
        ),
    )

    # VAD: tuned for faster turn detection
    vad = silero.VAD.load(
        min_silence_duration=0.3,
        prefix_padding_duration=0.3,
    )

    session = AgentSession(
        stt=stt_adapter,
        llm=llm_plugin,
        tts=tts_plugin,
        vad=vad,
    )

    await session.start(room=ctx.room, agent=agent)
    await session.wait_for_inactive()


if __name__ == "__main__":
    cli.run_app(WorkerOptions(entrypoint_fnc=entrypoint, num_idle_processes=1))