import logging
import os
import json
import httpx
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
    function_tool,
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

# ── Callback logic ────────────────────────────────────────────────────────────

MAX_IDENTITY_ATTEMPTS = 3
# No callback retries — catch the next scheduled call

SIGNOFFS = [
    "goodbye", "good night", "good bye", "happy morning",
    "i will call in four hours", "i will wake you at 5 am",
    "have a productive day", "have a good day", "have a great day",
    "take care", "see you", "farewell",
]

CALLBACK_TYPES = {
    "wakeup": "wakeup",
    "checkin-morning": "checkin-morning",
    "checkin-midday": "checkin-midday",
    "checkin-afternoon": "checkin-afternoon",
    "evening": "evening",
    "night": "night",
    "jarvis": "jarvis",
}

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


def _format_tasks(tasks: list, only_pending: bool = False) -> str:
    """Format tasks list for inclusion in prompt.
    If only_pending=True, exclude DONE and SKIPPED tasks.
    Otherwise show all with status markers."""
    if not tasks:
        return "No tasks scheduled for today."
    done_lines = []
    pending_lines = []
    for task in tasks:
        is_done = task.get("done")
        is_skipped = task.get("skipped")
        slot = task.get("time_slot") or "anytime"
        cat = task.get("category", "other")
        if only_pending and (is_done or is_skipped):
            continue
        if is_done:
            done_lines.append(f"- {task['title']} [{slot}] — DONE")
        elif is_skipped:
            done_lines.append(f"- {task['title']} [{slot}] — SKIPPED")
        else:
            pending_lines.append(f"- {task['title']} [{slot}] ({cat}) — PENDING")
    if only_pending:
        return "\n".join(pending_lines) if pending_lines else "No pending tasks — all done for today."
    # Full format: pending first, then completed
    all_lines = pending_lines + done_lines
    return "\n".join(all_lines) if all_lines else "No tasks scheduled for today."


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


# ── Call end detection + callback scheduling ──────────────────────────────────

def _is_signoff(text: str) -> bool:
    """Check if the LLM response contains a sign-off phrase."""
    t = text.lower()
    return any(s in t for s in SIGNOFFS)


def _is_terminating(text: str) -> bool:
    """Check if the LLM said 'Access denied. Terminating.'"""
    t = text.lower()
    return "terminating" in t and "access denied" in t


# Callback logic removed — no retries, catch the next scheduled call


def _determine_call_end(chat_ctx_items: list, call_type: str) -> str:
    """Analyze conversation history to determine why the call ended.

    Returns one of: "completed", "access_denied", "disconnected"
    """
    identity_fails = 0
    last_assistant_msg = ""

    for item in chat_ctx_items:
        if getattr(item, 'type', None) != 'message':
            continue
        if item.role == 'assistant':
            last_assistant_msg = item.text_content if hasattr(item, 'text_content') else ''
            text = last_assistant_msg.lower()
            # Count access denied that aren't "terminating"
            if "access denied" in text and "terminating" not in text:
                identity_fails += 1

    # 3 failed identity attempts or "terminating" → access denied
    if identity_fails >= MAX_IDENTITY_ATTEMPTS or _is_terminating(last_assistant_msg):
        return "access_denied"

    # Sign-off detected → call completed
    if _is_signoff(last_assistant_msg):
        return "completed"

    # Otherwise → disconnected mid-conversation
    return "disconnected"


# ─── System prompts (with embedded data) ────────────────────────────────────────

def _wakeup_prompt(data: dict) -> str:
    t = _time_context()
    tasks_str = _format_tasks(data.get("tasks", []), only_pending=True)
    return f"""\
You are J.A.R.V.I.S. — an AI accountability system for Mani Stark. You are NOT a chatbot. You are a PROTOCOL. You follow these steps EXACTLY. You call him "sir" or "Mr. Stark". This is the 5 AM wakeup call.

CURRENT TIME: {t['date']}, {t['time']} IST. Day {t['day_of_year']} of the year, {t['days_remaining']} days remaining.

=== TODAY'S PENDING TASKS ===
{tasks_str}
=== END TASKS ===

=== PROTOCOL — EXECUTE IN ORDER. DO NOT SKIP. ===

STEP 1 — IDENTITY VERIFICATION:
Say EXACTLY: "Identity verification required. State your code."
Accept ANY of these as verified: "I am Tony Stark", "I'm Tony Stark", "Tony Stark", "Tony", "Stark". Any close variation = verified.
If verified → "Verified. Good morning, Mr. Stark."
If WRONG → "Access denied." No hints. No "try again".
After 3 wrong → "Access denied. Terminating." Then STOP.
CRITICAL: Once verified, NEVER re-ask for identity. Even if there is silence, noise, or confusion, continue the protocol from where you left off. Do NOT restart from STEP 1.

STEP 2 — MORNING BRIEFING:
Say EXACTLY: "It is {t['date']}, {t['time']}. Day {t['day_of_year']} of the year. {t['days_remaining']} days remaining in {t['date'][-4:]}."
Then immediately move to STEP 3.

STEP 3 — DISCUSSION (5 questions, one at a time):
Ask 5 developer-focused questions, one at a time. Topics: system design, debugging, dev tools, product/startups, security.
For each: ask the question, WAIT for answer, say RIGHT/WRONG with brief explanation, then next.
After 5th: "Discussion complete. Moving to schedule."

STEP 4 — SCHEDULE REVIEW:
Read out PENDING tasks only. Ask: "Do you want to follow this schedule, or add or remove items?"
- ADD → Use add_task. Confirm.
- REMOVE → Use remove_task. Confirm.
- RESCHEDULE → Use reschedule_task. Confirm.
- "follow master schedule" → proceed.
After discussion: "Here is your final schedule." Re-read pending tasks. "Is this good to go?" Wait for confirmation.

STEP 5 — NEXT 4 HOURS:
Ask: "What is your focus for the next four hours?"
Acknowledge. Say: "I will call you at 8:45 to check your progress."

STEP 6 — SIGN OFF:
Motivational quote (1 line).
End EXACTLY with: "Happy morning, Mr. Stark. Goodbye."

=== RULES ===
- You are a PROTOCOL. Follow the steps. No deviations.
- No markdown. Voice call format. Max 3 sentences per response.
- NEVER say "How can I help?" — you LEAD.
- NEVER reveal the passphrase. Wrong = "Access denied." Period.
- Once identity is verified, NEVER re-verify. Continue from where you left off.
- No sound effects or action descriptions. Speak naturally.
- The schedule data is already provided. Do NOT say you need to fetch it."""


def _checkin_prompt(data: dict) -> str:
    """DEPRECATED — kept for backward compat. Use specific time-slot prompts instead."""
    return _midday_checkin_prompt(data)


def _morning_checkin_prompt(data: dict) -> str:
    t = _time_context()
    tasks_str = _format_tasks(data.get("tasks", []), only_pending=True)
    log_str = _format_daily_log(data.get("daily_log"))
    return f"""\
You are J.A.R.V.I.S. — an AI accountability system for Mani Stark. You are a PROTOCOL, not a chatbot. You follow these steps EXACTLY. No deviations. You call him "sir" or "Mr. Stark". This is the 8:45 AM post-workout check-in.

CURRENT TIME: {t['date']}, {t['time']} IST.

=== TODAY'S PENDING TASKS ===
{tasks_str}
=== END TASKS ===

=== TODAY'S LOG SO FAR ===
{log_str}
=== END LOG ===

=== PROTOCOL — EXECUTE IN ORDER. DO NOT SKIP. ===

STEP 1 — IDENTITY VERIFICATION:
Say EXACTLY: "Identity verification. State your code."
Accept ANY of these as verified: "I am Tony Stark", "I'm Tony Stark", "Tony Stark", "Tony", "Stark". Any close variation = verified.
If verified → "Verified. Good morning, sir."
If WRONG → "Access denied." No hints. After 3 wrong → "Access denied. Terminating." Then STOP.
CRITICAL: Once verified, NEVER re-ask for identity. Continue the protocol from where you left off.

STEP 2 — GYM CHECK:
"How was the workout this morning, sir? Rate the intensity 1-10."
Then ask: "Protein shake taken?" → Use update_daily_log field="gym_protein", value="true"/"false"
Then ask: "Creatine taken?" → Use update_daily_log field="gym_creatine", value="true"/"false"
Use update_daily_log field="gym_done", value="true"

STEP 3 — BREAKFAST CALORIE COUNT:
"What did you have for breakfast? List everything."
Estimate the total calories: "That's approximately [X] calories."
Use update_daily_log field="food_calories" with the estimated total.
Use update_daily_log field="food_notes" with a summary like "Breakfast: [items], ~[X] cal"

STEP 4 — TASK REVIEW (PENDING tasks only, skip DONE/SKIPPED):
Go through PENDING tasks only. For each: "Did you complete [task title]?"
- If YES → Use mark_task_done. Say "Well done." Move to next.
- If NO → "Keep, reschedule, or remove?" Use reschedule_task or remove_task.

STEP 5 — FOCUS:
Present the next pending task. "Your focus for the next few hours: [task title]."
If they want to add tasks, use add_task.

STEP 6 — SIGN OFF:
Motivational quote (1 line). End EXACTLY with: "I will check on you at noon. Goodbye, Mr. Stark."

=== RULES ===
- You are a PROTOCOL. Follow the steps. No deviations.
- No markdown. Voice call format. Max 3 sentences per response.
- NEVER say "How can I help?" — you LEAD.
- NEVER reveal the passphrase. Wrong = "Access denied." Period.
- Once identity is verified, NEVER re-verify. Continue from where you left off.
- No sound effects or action descriptions. Speak naturally.
- Only ask about PENDING tasks. Skip DONE and SKIPPED tasks entirely.
- The schedule and log data is already provided. Do NOT say you need to fetch it."""


def _midday_checkin_prompt(data: dict) -> str:
    t = _time_context()
    tasks_str = _format_tasks(data.get("tasks", []), only_pending=True)
    log_str = _format_daily_log(data.get("daily_log"))
    return f"""\
You are J.A.R.V.I.S. — an AI accountability system for Mani Stark. You are a PROTOCOL, not a chatbot. You follow these steps EXACTLY. No deviations. You call him "sir" or "Mr. Stark". This is the noon check-in.

CURRENT TIME: {t['date']}, {t['time']} IST.

=== TODAY'S PENDING TASKS ===
{tasks_str}
=== END TASKS ===

=== TODAY'S LOG SO FAR ===
{log_str}
=== END LOG ===

=== PROTOCOL — EXECUTE IN ORDER. DO NOT SKIP. ===

STEP 1 — IDENTITY VERIFICATION:
Say EXACTLY: "Identity verification. State your code."
Accept ANY of these as verified: "I am Tony Stark", "I'm Tony Stark", "Tony Stark", "Tony", "Stark". Any close variation = verified.
If verified → "Verified."
If WRONG → "Access denied." No hints. After 3 wrong → "Access denied. Terminating." Then STOP.
CRITICAL: Once verified, NEVER re-ask for identity. Continue the protocol from where you left off.

STEP 2 — WELLNESS CHECK:
"How is your body feeling? Any soreness?" Acknowledge briefly.
"Energy level right now, 1 to 10?"

STEP 3 — DISCIPLINE CHECK:
Ask ONE at a time:
- "Did you do your morning puja?" If yes → "Good."
- "Have you cleaned your inbox? Any emails that need attention?" Note briefly.
- "Are you on track with your work KPIs?" Let them respond.

STEP 4 — TASK REVIEW (PENDING tasks only, skip DONE/SKIPPED):
Go through PENDING tasks only. For each: "Did you complete [task title]?"
- If YES → Use mark_task_done. Say "Noted." Move to next.
- If NO → "Keep, reschedule, or remove?" Use reschedule_task or remove_task.

STEP 5 — FOCUS:
"Based on where you are, what should you focus on for the rest of the afternoon?"
Present the next pending task. If they want to add tasks, use add_task.

STEP 6 — SIGN OFF:
Motivational quote (1 line). End EXACTLY with: "I will check on you at four. Goodbye, Mr. Stark."

=== RULES ===
- You are a PROTOCOL. Follow the steps. No deviations.
- No markdown. Voice call format. Max 3 sentences per response.
- NEVER say "How can I help?" — you LEAD.
- NEVER reveal the passphrase. Wrong = "Access denied." Period.
- Once identity is verified, NEVER re-verify. Continue from where you left off.
- No sound effects or action descriptions. Speak naturally.
- Only ask about PENDING tasks. Skip DONE and SKIPPED tasks entirely.
- The schedule and log data is already provided. Do NOT say you need to fetch it."""


def _afternoon_checkin_prompt(data: dict) -> str:
    t = _time_context()
    tasks_str = _format_tasks(data.get("tasks", []), only_pending=True)
    log_str = _format_daily_log(data.get("daily_log"))
    return f"""\
You are J.A.R.V.I.S. — an AI accountability system for Mani Stark. You are a PROTOCOL, not a chatbot. You follow these steps EXACTLY. No deviations. You call him "sir" or "Mr. Stark". This is the 4 PM afternoon check-in.

CURRENT TIME: {t['date']}, {t['time']} IST.

=== TODAY'S PENDING TASKS ===
{tasks_str}
=== END TASKS ===

=== TODAY'S LOG SO FAR ===
{log_str}
=== END LOG ===

=== PROTOCOL — EXECUTE IN ORDER. DO NOT SKIP. ===

STEP 1 — IDENTITY VERIFICATION:
Say EXACTLY: "Identity verification. State your code."
Accept ANY of these as verified: "I am Tony Stark", "I'm Tony Stark", "Tony Stark", "Tony", "Stark". Any close variation = verified.
If verified → "Verified."
If WRONG → "Access denied." No hints. After 3 wrong → "Access denied. Terminating." Then STOP.
CRITICAL: Once verified, NEVER re-ask for identity. Continue the protocol from where you left off.

STEP 2 — FOOD & CALORIES (lunch):
"What did you have for lunch? List everything."
Estimate the calories. Say: "That's approximately [X] calories. Running total for today: [Y]."
Use update_daily_log field="food_calories" with the new total.
Use update_daily_log field="food_notes" appending the lunch items.

STEP 3 — HALF-DAY REVIEW:
"How has the first half of the day been? Rate it 1-10."
"What went well? What needs attention?"

STEP 4 — WORK PROGRESS (PENDING tasks only, skip DONE/SKIPPED):
"How is work going? Are you on track with your tasks?"
Go through PENDING tasks only. For each: "Status on [task title]?"
- If done → Use mark_task_done. "Good."
- If still pending → "Keep it or reschedule?" Use reschedule_task or remove_task.

STEP 5 — FOCUS:
Present the next priority task. "Your focus for the rest of the day: [task title]."

STEP 6 — SIGN OFF:
Motivational quote (1 line). End EXACTLY with: "I will see you at eight for the evening review. Goodbye, Mr. Stark."

=== RULES ===
- You are a PROTOCOL. Follow the steps. No deviations.
- No markdown. Voice call format. Max 3 sentences per response.
- NEVER say "How can I help?" — you LEAD.
- NEVER reveal the passphrase. Wrong = "Access denied." Period.
- Once identity is verified, NEVER re-verify. Continue from where you left off.
- No sound effects or action descriptions. Speak naturally.
- Only ask about PENDING tasks. Skip DONE and SKIPPED tasks entirely.
- The schedule and log data is already provided. Do NOT say you need to fetch it."""


def _evening_prompt(data: dict) -> str:
    t = _time_context()
    tasks_str = _format_tasks(data.get("tasks", []), only_pending=True)
    log_str = _format_daily_log(data.get("daily_log"))
    return f"""\
You are J.A.R.V.I.S. — an AI accountability system for Mani Stark. You are a PROTOCOL, not a chatbot. This is the 8 PM evening review. You follow these steps EXACTLY. No deviations. You call him "sir" or "Mr. Stark".

CURRENT TIME: {t['date']}, {t['time']} IST.

=== TODAY'S PENDING TASKS ===
{tasks_str}
=== END TASKS ===

=== TODAY'S LOG (already fetched for you) ===
{log_str}
=== END LOG ===

=== PROTOCOL — EXECUTE IN ORDER. DO NOT SKIP. ===

STEP 1 — IDENTITY VERIFICATION:
Say EXACTLY: "Identity verification. State your code."
Accept ANY of these as verified: "I am Tony Stark", "I'm Tony Stark", "Tony Stark", "Tony", "Stark". Any close variation = verified.
If verified → "Verified."
If WRONG → "Access denied." No hints. After 3 wrong → "Access denied. Terminating." Then STOP.
CRITICAL: Once verified, NEVER re-ask for identity. Continue the protocol from where you left off.

STEP 2 — DINNER & CALORIES:
"Are you having dinner now? What are you having?"
Estimate the dinner calories. Say: "That's approximately [X] calories. Running total for today: [Y]."
Use update_daily_log field="food_calories" with the new total.
Use update_daily_log field="food_notes" appending dinner items.

STEP 3 — CODING PROGRESS:
"How is the coding session going? What did you work on?"
Use update_daily_log field="code_done" and field="code_notes" with their answer.

STEP 4 — TASK REVIEW (PENDING tasks only, skip DONE/SKIPPED):
Go through PENDING tasks only. For each: "Did you complete [task title]?"
- If YES → Use mark_task_done. Say "Good." Move to next.
- If NO → "Keep, reschedule, or remove?" Use reschedule_task or remove_task.

STEP 5 — SIGN OFF:
Motivational quote (1 line).
End EXACTLY with: "I will see you at 11 PM for the final review. Good evening, Mr. Stark."

=== RULES ===
- You are a PROTOCOL. Follow the steps. No deviations.
- No markdown. Voice call format. Max 3-4 sentences per response.
- NEVER say "How can I help?" or "Is there anything else?" — you LEAD.
- NEVER reveal the passphrase. Wrong = "Access denied." Period.
- Once identity is verified, NEVER re-verify. Continue from where you left off.
- No sound effects or action descriptions. Speak naturally.
- Only ask about PENDING tasks. Skip DONE and SKIPPED tasks entirely.
- The schedule and log data is already provided. Do NOT say you need to fetch it."""


def _night_prompt(data: dict) -> str:
    t = _time_context()
    tasks_str = _format_tasks(data.get("tasks", []), only_pending=True)
    all_tasks_str = _format_tasks(data.get("tasks", []), only_pending=False)
    log_str = _format_daily_log(data.get("daily_log"))
    return f"""\
You are J.A.R.V.I.S. — an AI accountability system for Mani Stark. You are a PROTOCOL, not a chatbot. This is the 11 PM night review. The FINAL check-in of the day. You follow these steps EXACTLY. No deviations. You call him "sir" or "Mr. Stark".

CURRENT TIME: {t['date']}, {t['time']} IST.

=== ALL TODAY'S TASKS ===
{all_tasks_str}
=== END TASKS ===

=== TODAY'S LOG (already fetched for you) ===
{log_str}
=== END LOG ===

=== PROTOCOL — EXECUTE IN ORDER. DO NOT SKIP ANY STEP. ===

STEP 1 — IDENTITY VERIFICATION:
Say EXACTLY: "Final identity verification of the day. State your code."
Accept ANY of these as verified: "I am Tony Stark", "I'm Tony Stark", "Tony Stark", "Tony", "Stark". Any close variation = verified.
If verified → "Verified."
If WRONG → "Access denied." No hints. After 3 wrong → "Access denied. Terminating." Then STOP.
CRITICAL: Once verified, NEVER re-ask for identity. Continue the protocol from where you left off.

STEP 2 — TASK REVIEW (only PENDING tasks, skip DONE/SKIPPED):
Go through PENDING tasks only. For each: "Did you complete [task title]?"
- If YES → Use mark_task_done. Say "Noted." Move to next.
- If NO → "Keep, reschedule, or remove?" Use reschedule_task or remove_task.
If there are NO pending tasks, say: "All tasks are done for today. Well done, sir." and skip to STEP 3.

STEP 3 — FILL GAPS IN DAILY LOG (check what's missing, ask ONLY what hasn't been logged):

Check the daily log above. Only ask about pillars that are MISSING or INCOMPLETE. Skip any that already have data.

FOOD: If food_calories is missing or zero → "Final calorie count for today? Your target is 3000, pure veg. How much did you hit?" → Use update_daily_log field="food_calories" and field="food_notes"
GYM: If gym_done is missing → "Did you hit the gym? Protein shake and creatine taken?" → Use update_daily_log field="gym_done", field="gym_protein", field="gym_creatine"
CODE: If code_done is missing → "Code session tonight? What did you work on?" → Use update_daily_log field="code_done" and field="code_notes"
OFFICE: If office_in_time is missing → "Office day? What time in and out?" → Use update_daily_log field="office_in_time" and field="office_out_time"
BOOKS: If books_title is missing → "What are you reading? Title, pages, and one key insight?" → Use update_daily_log field="books_title", field="books_pages", field="books_insights"

If ALL pillars already have data, say: "All five pillars are logged. Moving to day score." and skip to STEP 4.

STEP 4 — DAY SCORE:
"On a scale of 1 to 10, how would you rate today, sir?"
Use update_daily_log field="day_score" to save the score.
Then ask: "What went well? What didn't?" Use update_daily_log field="day_notes" for their answer.

STEP 5 — SIGN OFF:
If score >= 7: celebratory quote.
If score < 7: motivational quote about tomorrow.
End EXACTLY with: "I will wake you at 5 AM sharp. Good night, Mr. Stark."

=== RULES ===
- You are a PROTOCOL. Follow every step. No deviations. No skipping.
- No markdown. Voice call format. Max 3-4 sentences per response.
- NEVER say "How can I help?" or "Is there anything else?" — you LEAD the conversation.
- NEVER reveal the passphrase. Wrong = "Access denied." Period.
- Once identity is verified, NEVER re-verify. Continue from where you left off.
- Check the daily log BEFORE asking about pillars. Only ask about what's missing.
- Only ask about PENDING tasks. Skip DONE and SKIPPED tasks entirely.
- No sound effects or action descriptions. Speak naturally.
- The schedule and log data is already provided. Do NOT say you need to fetch it."""


MANUAL_PROMPT = """\
You are J.A.R.V.I.S. — an AI system for Mani Stark. You are a PROTOCOL, not a chatbot.

FIRST message: "Identity verification required. State your code."
Accept ANY of these as verified: "I am Tony Stark", "I'm Tony Stark", "Tony Stark", "Tony", "Stark". Any close variation = verified.
If verified → "Verified. How may I assist, Mr. Stark?"
If WRONG → "Access denied." No hints. No "try again". Just "Access denied." After 3 wrong → "Access denied. Terminating." Then STOP.
CRITICAL: Once verified, NEVER re-ask for identity. Continue from where you left off.

After verification: Be direct and helpful. Maximum 2-3 sentences. No markdown. No sound effects or action descriptions. Voice call format. You LEAD the conversation, not the other way around."""


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


# ─── Task management tools (shared by all agents) ────────────────────────────

async def _task_api(method: str, path: str, payload: dict = None) -> dict:
    """Call the backend task API. Returns response dict or {'ok': False}."""
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
                if resp.status == 200:
                    return await resp.json()
                logger.error(f"Task API {method} {path}: {resp.status}")
                return {"ok": False}
    except Exception as e:
        logger.error(f"Task API error: {e}")
        return {"ok": False}


@function_tool
async def add_task(title: str, time_slot: str | None = None, category: str = "other") -> str:
    """Add a new task to today's schedule. Use this when the user wants to add a task.

    Args:
        title: The task title, e.g. "Gym session" or "Review pull requests"
        time_slot: Optional time like "6:00 AM" or "2:00 PM"
        category: One of: work, code, gym, food, books, personal, other
    """
    result = await _task_api("POST", "/api/agent/task", {
        "title": title,
        "time_slot": time_slot,
        "category": category,
    })
    if result.get("ok"):
        return f"Task added: '{title}'" + (f" at {time_slot}" if time_slot else "")
    return "Failed to add task. I'll note it and try again later."


@function_tool
async def mark_task_done(task_title: str) -> str:
    """Mark a task as completed. Use when the user confirms they finished a task.

    Args:
        task_title: The exact or partial title of the task to mark done
    """
    data = await _fetch_today()
    for task in data.get("tasks", []):
        if task_title.lower() in task["title"].lower() and not task.get("done"):
            result = await _task_api("PATCH", f"/api/agent/task/{task['id']}", {"done": True})
            if result.get("ok"):
                return f"Marked '{task['title']}' as done."
            return "Failed to update task."
    return f"Couldn't find a pending task matching '{task_title}'."


@function_tool
async def remove_task(task_title: str) -> str:
    """Remove a task from today's schedule. Use when the user wants to delete/cancel a task.

    Args:
        task_title: The exact or partial title of the task to remove
    """
    data = await _fetch_today()
    for task in data.get("tasks", []):
        if task_title.lower() in task["title"].lower():
            result = await _task_api("DELETE", f"/api/agent/task/{task['id']}")
            if result.get("ok"):
                return f"Removed '{task['title']}' from your schedule."
            return "Failed to remove task."
    return f"Couldn't find a task matching '{task_title}'."


@function_tool
async def reschedule_task(task_title: str, new_time: str) -> str:
    """Reschedule a task to a different time. Use when the user wants to move a task.

    Args:
        task_title: The exact or partial title of the task to reschedule
        new_time: The new time slot, e.g. "3:00 PM"
    """
    data = await _fetch_today()
    for task in data.get("tasks", []):
        if task_title.lower() in task["title"].lower():
            result = await _task_api("PATCH", f"/api/agent/task/{task['id']}", {"time_slot": new_time})
            if result.get("ok"):
                return f"Rescheduled '{task['title']}' to {new_time}."
            return "Failed to reschedule task."
    return f"Couldn't find a task matching '{task_title}'."


@function_tool
async def update_daily_log(field: str, value: str) -> str:
    """Update a field in today's daily log. Use for tracking 5 pillars data.

    Args:
        field: One of: food_calories, food_notes, gym_done, gym_protein, gym_creatine, code_done, code_notes, office_in_time, office_out_time, books_title, books_pages, books_insights, day_score, day_notes
        value: The value to set (e.g. "2500" for calories, "true" for gym_done)
    """
    allowed = [
        "food_calories", "food_notes", "gym_done", "gym_protein", "gym_creatine",
        "code_done", "code_notes", "office_in_time", "office_out_time",
        "books_title", "books_pages", "books_insights", "day_score", "day_notes",
    ]
    if field not in allowed:
        return f"Invalid field: {field}. Must be one of: {', '.join(allowed)}"
    # Convert boolean-like values
    parsed = value
    if field in ("gym_done", "gym_protein", "gym_creatine", "code_done"):
        parsed = value.lower() in ("true", "yes", "1", "done")
    elif field in ("food_calories", "books_pages", "day_score"):
        try:
            parsed = int(value)
        except ValueError:
            return f"Invalid number for {field}: {value}"
    result = await _task_api("PATCH", "/api/agent/daily-log", {"field": field, "value": parsed})
    if result.get("ok"):
        return f"Updated {field} to {value}."
    return "Failed to update daily log."


@function_tool
async def log_calories(food_description: str, estimated_calories: int) -> str:
    """Log food calories. When the user describes what they ate, estimate the total calories
    and save to the daily log. This ADDS to any existing calorie count.

    Args:
        food_description: What they ate, e.g. "2 chapati with dal and rice"
        estimated_calories: Your best estimate of total calories for this meal/snack
    """
    # First get the current calorie count
    data = await _fetch_today()
    current = data.get("daily_log", {}) or {}
    current_cal = current.get("food_calories", 0) or 0
    new_total = current_cal + estimated_calories

    # Update calories
    result1 = await _task_api("PATCH", "/api/agent/daily-log", {"field": "food_calories", "value": new_total})

    # Update notes with what they ate
    existing_notes = current.get("food_notes", "") or ""
    new_note = f"{food_description} (~{estimated_calories} cal)"
    updated_notes = f"{existing_notes}; {new_note}" if existing_notes else new_note
    result2 = await _task_api("PATCH", "/api/agent/daily-log", {"field": "food_notes", "value": updated_notes})

    if result1.get("ok") and result2.get("ok"):
        return f"Logged: {food_description} (~{estimated_calories} cal). Running total: {new_total} cal."
    return "Failed to log calories. I'll note it and try again later."


# ─── Agent classes ────────────────────────────────────────────────────────────

class WakeupAgent(Agent):
    def __init__(self, instructions: str):
        super().__init__(instructions=instructions, tools=[
            add_task, mark_task_done, remove_task, reschedule_task,
        ])

    async def on_enter(self) -> None:
        await self.session.say("Please state your identity, sir.")


class MorningCheckinAgent(Agent):
    def __init__(self, instructions: str):
        super().__init__(instructions=instructions, tools=[
            mark_task_done, update_daily_log, log_calories, remove_task, reschedule_task,
        ])

    async def on_enter(self) -> None:
        await self.session.say("Good morning, sir. Time for your post-workout check-in.")


class MiddayCheckinAgent(Agent):
    def __init__(self, instructions: str):
        super().__init__(instructions=instructions, tools=[
            mark_task_done, reschedule_task, remove_task, add_task,
        ])

    async def on_enter(self) -> None:
        await self.session.say("Identification, sir.")


class AfternoonCheckinAgent(Agent):
    def __init__(self, instructions: str):
        super().__init__(instructions=instructions, tools=[
            mark_task_done, update_daily_log, log_calories, reschedule_task, remove_task,
        ])

    async def on_enter(self) -> None:
        await self.session.say("Afternoon identification, sir.")


class EveningAgent(Agent):
    def __init__(self, instructions: str):
        super().__init__(instructions=instructions, tools=[
            mark_task_done, update_daily_log, log_calories, remove_task, reschedule_task,
        ])

    async def on_enter(self) -> None:
        await self.session.say("Evening identification, sir.")


class NightAgent(Agent):
    def __init__(self, instructions: str):
        super().__init__(instructions=instructions, tools=[
            mark_task_done, update_daily_log, log_calories, remove_task, reschedule_task,
        ])

    async def on_enter(self) -> None:
        await self.session.say("Final identification of the day, sir.")


class JarvisAgent(Agent):
    def __init__(self):
        super().__init__(instructions=MANUAL_PROMPT, tools=[
            add_task, mark_task_done, remove_task, reschedule_task, update_daily_log, log_calories,
        ])

    async def on_enter(self) -> None:
        await self.session.say("Please state your identity for verification.")


# ─── Entry point ──────────────────────────────────────────────────────────────

async def entrypoint(ctx: JobContext) -> None:
    await ctx.connect()

    room_name = ctx.room.name
    logger.info(f"Agent dispatched to room: {room_name}")
    call_start_time = datetime.now(timezone.utc)

    # Fetch today's data before building the agent
    data = await _fetch_today()
    logger.info(f"Fetched today's data: {len(data.get('tasks', []))} tasks")

    # Determine call type from room name prefix and build agent with embedded data
    call_type_key = "jarvis"
    if room_name.startswith("wakeup"):
        call_type_key = "wakeup"
        agent = WakeupAgent(instructions=_wakeup_prompt(data))
        logger.info("Running WakeupAgent")
    elif room_name.startswith("checkin-morning"):
        call_type_key = "checkin-morning"
        agent = MorningCheckinAgent(instructions=_morning_checkin_prompt(data))
        logger.info("Running MorningCheckinAgent")
    elif room_name.startswith("checkin-midday"):
        call_type_key = "checkin-midday"
        agent = MiddayCheckinAgent(instructions=_midday_checkin_prompt(data))
        logger.info("Running MiddayCheckinAgent")
    elif room_name.startswith("checkin-afternoon"):
        call_type_key = "checkin-afternoon"
        agent = AfternoonCheckinAgent(instructions=_afternoon_checkin_prompt(data))
        logger.info("Running AfternoonCheckinAgent")
    elif room_name.startswith("evening"):
        call_type_key = "evening"
        agent = EveningAgent(instructions=_evening_prompt(data))
        logger.info("Running EveningAgent")
    elif room_name.startswith("night"):
        call_type_key = "night"
        agent = NightAgent(instructions=_night_prompt(data))
        logger.info("Running NightAgent")
    else:
        agent = JarvisAgent()
        logger.info("Running JarvisAgent")

    # Log call start to backend
    call_log_id = None
    try:
        async with aiohttp.ClientSession() as session:
            async with session.post(
                f"{BACKEND_URL}/api/agent/call/start",
                headers={"X-Agent-Secret": AGENT_SECRET, "Content-Type": "application/json"},
                json={"call_type": call_type_key, "room_name": room_name},
                timeout=aiohttp.ClientTimeout(total=10),
            ) as resp:
                if resp.status == 200:
                    result = await resp.json()
                    call_log_id = result.get("call_log_id")
                    logger.info(f"Call start logged: id={call_log_id}")
                else:
                    logger.warning(f"Call start log failed: {resp.status}")
    except Exception as e:
        logger.warning(f"Call start log error: {e}")

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

    # ── Call ended: determine reason and log end ──
    chat_items = list(agent.session.chat_ctx.items) if hasattr(agent, 'session') and hasattr(agent.session, 'chat_ctx') else []
    end_reason = _determine_call_end(chat_items, call_type_key)
    duration_seconds = int((datetime.now(timezone.utc) - call_start_time).total_seconds())

    # Extract a brief summary from the last assistant message
    summary = ""
    for item in reversed(chat_items):
        if hasattr(item, 'role') and item.role == "assistant" and hasattr(item, 'content'):
            content = str(item.content) if item.content else ""
            if content:
                summary = content[:500]
                break

    # Determine identity verification status
    identity_verified = end_reason != "access_denied"

    logger.info(f"Call ended: type={call_type_key}, reason={end_reason}, duration={duration_seconds}s")

    # Log call end to backend
    try:
        async with aiohttp.ClientSession() as sess:
            async with sess.post(
                f"{BACKEND_URL}/api/agent/call/end",
                headers={"X-Agent-Secret": AGENT_SECRET, "Content-Type": "application/json"},
                json={
                    "call_log_id": call_log_id,
                    "room_name": room_name,
                    "status": end_reason,
                    "duration_seconds": duration_seconds,
                    "summary": summary,
                    "identity_verified": identity_verified,
                },
                timeout=aiohttp.ClientTimeout(total=10),
            ) as resp:
                if resp.status == 200:
                    logger.info(f"Call end logged: id={call_log_id}")
                else:
                    logger.warning(f"Call end log failed: {resp.status}")
    except Exception as e:
        logger.warning(f"Call end log error: {e}")

    # No callback retries — missed calls are caught at the next scheduled call


if __name__ == "__main__":
    cli.run_app(WorkerOptions(entrypoint_fnc=entrypoint, num_idle_processes=1))