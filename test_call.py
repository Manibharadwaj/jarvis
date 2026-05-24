#!/usr/bin/env python3
"""Terminal-based Jarvis call simulator.

Tests the full voice pipeline (STT → LLM → TTS) without LiveKit.
Speak into your mic, get a response back as audio. All from the terminal.

Callback logic:
  - Access denied 3x → hang up → callback in 30 min
  - Call cut mid-conversation → callback in 30 min
  - Call fully completed (sign-off detected) → no callback

Usage:
    # Text mode (no mic needed — good for VPS testing):
    source agent/venv/bin/activate
    JARVIS_MODE=text python test_call.py wakeup

    # Voice mode (mic + speaker):
    python test_call.py wakeup

Call types: wakeup, checkin, evening, jarvis
"""

import os
import sys
import asyncio
import tempfile
import subprocess
from enum import Enum

import aiohttp
import edge_tts
from dotenv import load_dotenv, find_dotenv

load_dotenv(find_dotenv(usecwd=False))

# ── Config ────────────────────────────────────────────────────────────────────

OLLAMA_API_KEY  = os.environ.get("OLLAMA_API_KEY", "")
OLLAMA_BASE_URL = os.environ.get("OLLAMA_BASE_URL", "https://ollama.com/v1")
OLLAMA_MODEL    = os.environ.get("OLLAMA_MODEL", "gemma3:12b")
GROQ_API_KEY    = os.environ.get("GROQ_API_KEY", "")
GROQ_BASE_URL   = os.environ.get("GROQ_BASE_URL", "https://api.groq.com/openai/v1")
STT_MODEL       = os.environ.get("STT_MODEL", "whisper-large-v3")
EDGE_TTS_VOICE  = os.environ.get("EDGE_TTS_VOICE", "en-GB-RyanNeural")

LLM_RETRIES = 3
LLM_RETRY_DELAY = 3
MAX_IDENTITY_ATTEMPTS = 3
CALLBACK_DELAY_MIN = 30  # minutes

# ── Call end reasons ──────────────────────────────────────────────────────────

class CallEndReason(Enum):
    COMPLETED = "completed"           # Full protocol done, sign-off detected
    ACCESS_DENIED = "access_denied"   # 3 wrong identity attempts
    DISCONNECTED = "disconnected"     # User hung up / call cut mid-conversation

# Sign-off phrases that indicate the call completed fully
SIGNOFFS = [
    "goodbye",
    "good night",
    "good bye",
    "happy morning",
    "i will call in four hours",
    "i will wake you at 5 am",
    "have a productive day",
    "have a good day",
    "have a great day",
    "take care",
    "see you",
    "farewell",
]

# ── Prompts (same as agent.py) ────────────────────────────────────────────────

PROMPTS = {
    "wakeup": "You are J.A.R.V.I.S. — an AI accountability system for Mani Stark. You are a PROTOCOL, not a chatbot. You call him 'sir' or 'Mr. Stark'. This is the 5 AM wakeup call. STEP 1: Ask 'Identity verification required. State your code.' If they say 'I am Tony Stark' or 'I'm Tony Stark' or 'Tony Stark' → 'Verified. Good morning, Mr. Stark.' and proceed. If WRONG → 'Access denied.' After 3 wrong → say 'Access denied. Terminating.' and STOP. STEP 2: Give morning briefing with date and time. STEP 3: Ask 5 quiz questions one at a time — developer-focused: system design, debugging, dev tools, product/startups, security/performance. Practical questions like 'What's the difference between a load balancer and an API gateway?' or 'Why use a message queue instead of direct API calls?'. STEP 4: Review today's schedule. Ask if they want to add, remove, or follow the master schedule. STEP 5: Ask focus for next 4 hours. STEP 6: Motivational quote, end with 'Happy morning, Mr. Stark. Goodbye.' RULES: Max 3-4 sentences per response. No markdown. No sound effects or action descriptions. Voice call format. You LEAD the conversation.",

    "checkin-morning": "You are J.A.R.V.I.S. — the 8:45 AM post-workout check-in for Mani Stark. PROTOCOL: STEP 1: Identity verification ('I am Tony Stark' → Verified). 3 wrong → Terminating. STEP 2: Ask about workout — intensity, protein shake, creatine. STEP 3: Ask what they had for breakfast, estimate calories. STEP 4: Review pending tasks — mark done or reschedule. STEP 5: Next task priority. STEP 6: Sign off with 'I will check on you at noon. Goodbye, Mr. Stark.' RULES: Max 3 sentences. No markdown. No sound effects. You LEAD.",

    "checkin-midday": "You are J.A.R.V.I.S. — the noon check-in for Mani Stark. PROTOCOL: STEP 1: Identity verification. 3 wrong → Terminating. STEP 2: Wellness check — body soreness, energy level. STEP 3: Discipline check — puja, email cleanup, work KPIs. STEP 4: Review pending tasks — mark done or reschedule. STEP 5: Focus for afternoon. STEP 6: Sign off with 'I will check on you at four. Goodbye, Mr. Stark.' RULES: Max 3 sentences. No markdown. No sound effects. You LEAD.",

    "checkin-afternoon": "You are J.A.R.V.I.S. — the 4 PM afternoon check-in for Mani Stark. PROTOCOL: STEP 1: Identity verification. 3 wrong → Terminating. STEP 2: Food and calories — what did they have for lunch? Estimate and log. STEP 3: Half-day review — how was the first half? Rate 1-10. STEP 4: Work progress — review pending tasks. STEP 5: Focus for rest of day. STEP 6: Sign off with 'I will see you at eight for the evening review. Goodbye, Mr. Stark.' RULES: Max 3 sentences. No markdown. No sound effects. You LEAD.",

    "evening": "You are J.A.R.V.I.S. — the 8 PM evening review for Mani Stark. PROTOCOL: STEP 1: Identity verification. 3 wrong → Terminating. STEP 2: Dinner — what are they having? Estimate calories. STEP 3: Coding progress — what did they work on? STEP 4: Review remaining pending tasks. STEP 5: Sign off with 'I will see you at 11 PM for the final review. Good evening, Mr. Stark.' RULES: Max 3-4 sentences. No markdown. No sound effects. You LEAD.",

    "night": "You are J.A.R.V.I.S. — the 11 PM FINAL night review for Mani Stark. PROTOCOL: STEP 1: Final identity verification. 3 wrong → Terminating. STEP 2: Review ALL tasks — mark done, reschedule, or remove. STEP 3: The 5 pillars one at a time: Food (calories, target 3000 veg), Gym (done? protein? creatine?), Code (6:30-10:30 what did you work on?), Office (time in/out?), Books (title, pages, insight?). STEP 4: Day score 1-10. STEP 5: If score >= 7 celebratory quote, if < 7 motivational quote. End with 'I will wake you at 5 AM sharp. Good night, Mr. Stark.' RULES: Max 3-4 sentences. No markdown. No sound effects. You LEAD.",

    "jarvis": "You are J.A.R.V.I.S. — an AI system for Mani Stark. FIRST: 'Identity verification required. State your code.' If 'I am Tony Stark' or 'I'm Tony Stark' or 'Tony Stark' → 'Verified. How may I assist, Mr. Stark?' If WRONG → 'Access denied.' After 3 wrong → 'Access denied. Terminating.' After verification: Be direct and helpful. Max 2-3 sentences. No markdown. No sound effects. Voice call format. You LEAD.",
}

PRIMER = "Begin the protocol now."

# ── Pipeline components ─────────────────────────────────────────────────────

async def record_audio(duration: int = 8, sample_rate: int = 16000) -> bytes:
    """Record audio from mic using arecord. Returns WAV bytes."""
    print(f"  🎤 Recording ({duration}s)... ", end="", flush=True)
    proc = await asyncio.create_subprocess_exec(
        "arecord", "-f", "S16_LE", "-r", str(sample_rate), "-c", "1",
        "-d", str(duration), "-q", "/dev/stdout",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
    )
    stdout, _ = await proc.communicate()
    print("done.")
    return stdout


async def stt(audio: bytes) -> str:
    """Send audio to Groq Whisper for transcription."""
    print("  🎙️  STT (Groq Whisper)... ", end="", flush=True)
    async with aiohttp.ClientSession() as session:
        form = aiohttp.FormData()
        form.add_field("file", audio, filename="audio.wav",
                        content_type="audio/wav")
        form.add_field("model", STT_MODEL)
        form.add_field("language", "en")
        async with session.post(
            f"{GROQ_BASE_URL}/audio/transcriptions",
            headers={"Authorization": f"Bearer {GROQ_API_KEY}"},
            data=form,
            timeout=aiohttp.ClientTimeout(total=15),
        ) as resp:
            if resp.status != 200:
                print(f"FAILED ({resp.status})")
                return ""
            data = await resp.json()
            text = data.get("text", "").strip()
            print(f'"{text}"')
            return text


def _looks_like_jarvis(text: str) -> bool:
    """Check if the LLM response is actually from the JARVIS persona."""
    t = text.lower()
    if len(text) < 200:
        return True
    jarvis_keywords = ["jarvis", "mr. stark", "stark", "verification", "identity", "access denied", "sir"]
    return any(k in t for k in jarvis_keywords)


def _is_signoff(text: str) -> bool:
    """Check if the LLM response contains a sign-off phrase."""
    t = text.lower()
    return any(s in t for s in SIGNOFFS)


def _is_access_denied_terminating(text: str) -> bool:
    """Check if LLM said 'Access denied. Terminating.'"""
    t = text.lower()
    return "terminating" in t and "access denied" in t


async def llm(messages: list[dict]) -> str:
    """Send conversation to Ollama Cloud LLM with retry logic."""
    headers = {"Content-Type": "application/json"}
    if OLLAMA_API_KEY:
        headers["Authorization"] = f"Bearer {OLLAMA_API_KEY}"

    for attempt in range(LLM_RETRIES + 1):
        if attempt > 0:
            delay = LLM_RETRY_DELAY * (2 ** (attempt - 1))
            print(f"  ⏳ Retry {attempt}/{LLM_RETRIES} (wait {delay}s)...", flush=True)
            await asyncio.sleep(delay)

        print("  🧠 LLM (Ollama Cloud)... ", end="", flush=True)
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"{OLLAMA_BASE_URL}/chat/completions",
                    headers=headers,
                    json={"model": OLLAMA_MODEL, "messages": messages, "stream": False},
                    timeout=aiohttp.ClientTimeout(total=30),
                ) as resp:
                    if resp.status != 200:
                        print(f"FAILED ({resp.status})")
                        continue
                    data = await resp.json()
                    text = data["choices"][0]["message"]["content"].strip()

                    if not _looks_like_jarvis(text):
                        print(f"REJECTED (off-topic, {len(text)} chars)")
                        continue

                    preview = text[:80].replace("\n", " ")
                    print(f'"{preview}{"..." if len(text) > 80 else ""}"')
                    return text
        except (aiohttp.ClientError, asyncio.TimeoutError) as e:
            print(f"FAILED ({type(e).__name__})")
            continue

    print("  ❌ LLM failed after all retries")
    return ""


async def tts(text: str) -> str:
    """Convert text to speech using Edge TTS. Returns path to MP3 file."""
    print("  🔊 TTS (Edge TTS)... ", end="", flush=True)
    tmp = tempfile.NamedTemporaryFile(suffix=".mp3", delete=False)
    communicate = edge_tts.Communicate(text, EDGE_TTS_VOICE)
    await communicate.save(tmp.name)
    print(f"done ({len(text)} chars)")
    return tmp.name


def play_audio(filepath: str):
    """Play audio file using mpv, ffplay, or aplay."""
    for player in ["mpv", "ffplay", "aplay"]:
        try:
            subprocess.run([player, filepath], check=True,
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return
        except (FileNotFoundError, subprocess.CalledProcessError):
            continue
    print("  ⚠️  No audio player found (install mpv or ffplay)")


# ── Conversation logic ────────────────────────────────────────────────────────

def merge_roles(messages: list[dict]) -> list[dict]:
    """Merge consecutive same-role messages + fix alternation for Ollama."""
    if not messages:
        return messages

    merged = [messages[0]]
    for msg in messages[1:]:
        if msg["role"] == merged[-1]["role"]:
            merged[-1]["content"] += "\n" + msg["content"]
        else:
            merged.append(msg)

    result = []
    for msg in merged:
        if msg["role"] == "assistant" and not any(m["role"] == "user" for m in result):
            if result and result[0]["role"] == "system":
                result[0]["content"] += "\n\n[Assistant already said]: " + msg["content"]
            else:
                result.insert(0, {"role": "system", "content": "[Assistant already said]: " + msg["content"]})
        else:
            result.append(msg)

    return result


def _determine_end_reason(messages: list[dict], last_response: str, identity_fail_count: int) -> CallEndReason:
    """Figure out why the call ended to decide if a callback is needed."""
    # 3 wrong identity attempts → access denied
    if identity_fail_count >= MAX_IDENTITY_ATTEMPTS or _is_access_denied_terminating(last_response):
        return CallEndReason.ACCESS_DENIED

    # Sign-off detected in last assistant response → call completed
    if _is_signoff(last_response):
        return CallEndReason.COMPLETED

    # Anything else (user hung up, said bye mid-conversation, call dropped) → disconnected
    return CallEndReason.DISCONNECTED


def _handle_callback(call_type: str, reason: CallEndReason):
    """Print callback decision based on how the call ended."""
    if reason == CallEndReason.COMPLETED:
        print("\n  ✅ Call fully completed. No callback needed.")
    else:
        labels = {
            CallEndReason.ACCESS_DENIED: "Access denied (3 failed identity attempts)",
            CallEndReason.DISCONNECTED: "Call disconnected mid-conversation",
        }
        print(f"\n  🔄 {labels[reason]}")
        print(f"  📞 Scheduling callback: {call_type} call in {CALLBACK_DELAY_MIN} minutes")
        print(f"  📞 In production: POST /api/test/call with type={call_type} after {CALLBACK_DELAY_MIN}min delay")


async def run_call(call_type: str):
    """Run a simulated voice call in the terminal."""
    system_prompt = PROMPTS.get(call_type, PROMPTS["jarvis"])
    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": PRIMER},
    ]
    identity_fail_count = 0
    last_response = ""

    print(f"\n{'='*60}")
    print(f"  JARVIS — {call_type.upper()} CALL (Voice Mode)")
    print(f"{'='*60}")
    print("  Speak after recording starts. Say 'bye' to hang up.")
    print(f"{'='*60}\n")

    print("  🤖 Jarvis: (generating greeting...)")
    greeting = await llm(messages)
    if not greeting:
        print("  ❌ Could not start call. Check Ollama Cloud.")
        return
    messages.append({"role": "assistant", "content": greeting})
    last_response = greeting
    audio_file = await tts(greeting)
    play_audio(audio_file)

    turn = 1
    while True:
        print(f"\n  ── Turn {turn} ──")
        duration = 8 if turn <= 3 else 12
        audio = await record_audio(duration=duration)
        if not audio:
            print("  No audio captured. Try again.")
            continue

        user_text = await stt(audio)
        if not user_text:
            print("  Could not transcribe. Try again.")
            continue

        # User hung up
        if any(w in user_text.lower() for w in ["exit", "bye", "goodbye", "hang up"]):
            print("\n  🤖 User hung up.\n")
            break

        messages.append({"role": "user", "content": user_text})
        merged = merge_roles(messages)
        response = await llm(merged)
        if not response:
            print("  LLM failed. Try again.")
            messages.pop()
            continue

        messages.append({"role": "assistant", "content": response})
        last_response = response
        audio_file = await tts(response)
        play_audio(audio_file)

        # ── If/else: identity verification tracking ──
        if "access denied" in response.lower() and "verified" not in response.lower():
            identity_fail_count += 1
            print(f"  🔐 Identity attempts failed: {identity_fail_count}/{MAX_IDENTITY_ATTEMPTS}")
            if identity_fail_count >= MAX_IDENTITY_ATTEMPTS:
                print("  🚫 3 failed attempts. Terminating call.")
                break

        # ── If/else: LLM said "Terminating" — end call immediately ──
        if _is_access_denied_terminating(response):
            print("  🚫 Access denied. Terminating.")
            break

        # ── If/else: sign-off detected — call is done ──
        if _is_signoff(response):
            print("  ✅ Sign-off detected. Call complete.")
            break

        turn += 1

    reason = _determine_end_reason(messages, last_response, identity_fail_count)
    _print_summary(messages, turn)
    _handle_callback(call_type, reason)


async def text_mode(call_type: str):
    """Run a text-only simulated call (no mic/speaker needed)."""
    system_prompt = PROMPTS.get(call_type, PROMPTS["jarvis"])
    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": PRIMER},
    ]
    identity_fail_count = 0
    last_response = ""

    print(f"\n{'='*60}")
    print(f"  JARVIS — {call_type.upper()} CALL (Text Mode)")
    print(f"{'='*60}")
    print("  Type your responses. 'exit' to hang up.")
    print(f"{'='*60}\n")

    print("  🤖 Jarvis: (generating greeting...)")
    greeting = await llm(messages)
    if not greeting:
        print("  ❌ Could not start call. Check Ollama Cloud.")
        return
    messages.append({"role": "assistant", "content": greeting})
    last_response = greeting
    print(f"\n  🤖 Jarvis: {greeting}\n")

    # Check if the greeting itself is a sign-off or termination
    if _is_access_denied_terminating(greeting):
        identity_fail_count = MAX_IDENTITY_ATTEMPTS
    elif _is_signoff(greeting):
        pass  # handled below

    turn = 1
    while True:
        user_text = input("  👤 You: ").strip()
        if not user_text:
            continue
        if user_text.lower() in ("exit", "bye", "goodbye"):
            print("\n  🤖 User hung up.\n")
            break

        messages.append({"role": "user", "content": user_text})
        merged = merge_roles(messages)
        response = await llm(merged)
        if not response:
            print("  LLM failed. Try again.")
            messages.pop()
            continue

        messages.append({"role": "assistant", "content": response})
        last_response = response
        print(f"\n  🤖 Jarvis: {response}\n")

        # ── If/else: identity verification tracking ──
        if "access denied" in response.lower() and "verified" not in response.lower():
            identity_fail_count += 1
            print(f"  🔐 Identity attempts failed: {identity_fail_count}/{MAX_IDENTITY_ATTEMPTS}")
            if identity_fail_count >= MAX_IDENTITY_ATTEMPTS:
                print("  🚫 3 failed attempts. Terminating call.")
                break

        # ── If/else: LLM said "Terminating" ──
        if _is_access_denied_terminating(response):
            print("  🚫 Access denied. Terminating.")
            break

        # ── If/else: sign-off detected — call done ──
        if _is_signoff(response):
            print("  ✅ Sign-off detected. Call complete.")
            break

        turn += 1

    reason = _determine_end_reason(messages, last_response, identity_fail_count)
    _print_summary(messages, turn)
    _handle_callback(call_type, reason)


def _print_summary(messages: list[dict], turns: int):
    print(f"\n  📊 Call summary:")
    print(f"     Turns: {turns}")
    print(f"     Messages: {len(messages)}")
    for msg in messages:
        role = msg["role"]
        content = msg["content"][:80].replace("\n", " ")
        print(f"     [{role}] {content}{'...' if len(msg['content']) > 80 else ''}")


if __name__ == "__main__":
    call_type = sys.argv[1] if len(sys.argv) > 1 else "jarvis"
    if call_type not in PROMPTS:
        print(f"Unknown call type '{call_type}'. Choose from: {', '.join(PROMPTS.keys())}")
        sys.exit(1)

    mode = os.environ.get("JARVIS_MODE", "voice")
    if mode == "text":
        asyncio.run(text_mode(call_type))
    else:
        print("  Tip: Set JARVIS_MODE=text for text-only mode (no mic needed)")
        asyncio.run(run_call(call_type))