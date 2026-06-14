<div align="center">

# 🤖 J.A.R.V.I.S.

**AI Accountability Companion**

*An AI that comes to you first — proactive voice calls, accountability follow-ups, persistent memory. Not a chatbot. An AI relationship layer that refuses to let you disappear from your own goals.*

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](https://opensource.org/licenses/MIT)
[![Python](https://img.shields.io/badge/Python-3.12-3776AB?style=flat-square&logo=python&logoColor=white)](https://python.org)
[![Node.js](https://img.shields.io/badge/Node.js-22-339933?style=flat-square&logo=node.js&logoColor=white)](https://nodejs.org)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter&logoColor=white)](https://flutter.dev)
[![LiveKit](https://img.shields.io/badge/LiveKit-Voice-FF6600?style=flat-square&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJ3aGl0ZSI+PHBhdGggZD0iTTIxIDNIM0MxLjkgMyAxIDMuOSAxIDV2MTRjMCAxLjEuOSAyIDIgMmgxOGMxLjEgMCAyLS45IDItMlY1YzAtMS4xLS45LTItMi0yeiIvPjwvc3ZnPg==)](https://livekit.io)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](CONTRIBUTING.md)

</div>

---

## 🎯 What It Does

Jarvis **calls you** — not the other way around. It's a voice-based accountability system that:

- ☎️ **Wakes you up at 5 AM** with a structured morning protocol (identity verification, tech quiz, schedule review)
- 📋 **Checks in throughout the day** — tracks tasks, gym, food, coding, reading
- 🌙 **Reviews your night** — scores your day across 5 pillars, holds you accountable
- 🔁 **Retries with escalation** — if you miss a call, it calls again every 20 minutes up to 6 times
- 🧠 **Remembers who you are** — identity verification ("I'm Tony Stark") before every call

### The Wakeup Call

```
🤖 "Identity verification required. State your code."
👤 "I'm Tony Stark"
🤖 "Verified. Good morning, Mr. Stark."
🤖 "It is Friday, 23 May 2025, 05:00 AM IST. Day 143 of the year. 222 days remaining."
🤖 "Let's begin. Question 1 — Technology: What is the primary cryptographic algorithm used in Bitcoin?"
👤 "SHA-256"
🤖 "Correct. Moving to cybersecurity..."
```

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🔊 **Voice-First** | Real-time voice calls via LiveKit, not text |
| 🗣️ **Streaming TTS** | Sentence-by-sentence audio — no waiting for full response |
| ⚡ **Sub-second STT** | Groq Whisper v3 for instant speech recognition |
| 🔄 **Auto-Retry** | Missed wakeup? Calls again every 20 min, up to 6 times |
| 📱 **Push Notifications** | FCM rings your phone like a real call |
| 📊 **5-Pillar Tracking** | Food, Gym, Code, Office, Books — scored nightly |
| 🔐 **Identity Verification** | "State your code" — no unauthorized access |
| 💾 **Task Persistence** | PostgreSQL stores your schedule, logs, scores |
| 🆓 **100% Free** | No paid services. Groq + Ollama + Edge TTS + LiveKit free tiers |

---

## 🏗️ Architecture

```mermaid
graph LR
    subgraph "Your Phone"
        A[Flutter App]
    end

    subgraph "Cloud (Free Tier)"
        B[LiveKit Cloud<br/>Voice Transport]
        C[Supabase<br/>PostgreSQL]
        D[Firebase FCM<br/>Push Notifications]
        E[Groq<br/>Whisper v3 STT]
        F[Ollama Cloud<br/>gemma3:12b LLM]
    end

    subgraph "VPS (Your Server)"
        G[Node.js Backend<br/>Scheduler + API]
        H[Python Agent<br/>Voice Pipeline]
    end

    subgraph "Microsoft"
        I[Edge TTS<br/>Neural Voices]
    end

    A -->|Push| D
    A -->|WebRTC| B
    D -->|Notification| A
    G -->|Schedule Calls| D
    G -->|Create Room| B
    H -->|STT| E
    H -->|LLM| F
    H -->|TTS| I
    H -->|Voice| B
    G <-->|Tasks + Logs| C
    H <-->|Data API| G
```

### Voice Pipeline

```mermaid
flowchart LR
    MIC["🎤 Microphone"] --> VAD["Silero VAD<br/>(300ms)"]
    VAD --> STT["Groq Whisper v3<br/>(~0.3s)"]
    STT --> LLM["gemma3:12b<br/>Ollama Cloud<br/>(~1s)"]
    LLM --> TTS["Edge TTS<br/>(Streaming)"]
    TTS --> SPK["🔊 Speaker"]
```

**Total time-to-first-audio: ~2 seconds**

---

## 💰 Cost

| Service | Tier | Monthly Cost |
|---------|------|:------------:|
| Groq Whisper | Free | **$0** |
| Ollama Cloud | Free | **$0** |
| Edge TTS | Free | **$0** |
| LiveKit Cloud | Free (10k min/mo) | **$0** |
| Supabase | Free | **$0** |
| Firebase FCM | Free | **$0** |
| VPS | Any 2+ core | ~$5-10 |

**Total: $0 + VPS.**

---

## 🚀 Quick Start

### Prerequisites

- Node.js 18+, Python 3.12+, Flutter 3.x
- A VPS (2+ cores, 4GB+ RAM)
- Free accounts: [Groq](https://console.groq.com), [Ollama](https://ollama.com), [LiveKit Cloud](https://cloud.livekit.io), [Supabase](https://supabase.com), [Firebase](https://firebase.google.com)

### 1. Clone & Configure

```bash
git clone https://github.com/Manibharadwaj/jarvis.git
cd jarvis
cp .env.example .env
# Edit .env with your API keys
```

### 2. Set Up Database

Create a Supabase project and run the SQL migrations in `db/` against it.

### 3. Start the Server

```bash
# Install Python dependencies
cd agent && python -m venv venv && source venv/bin/activate
pip install -r requirements.txt

# Install Node.js dependencies
cd ../backend && npm install

# Start everything
cd .. && ./start.sh start
```

### 4. Set Up the App

```bash
cd app
flutter pub get
# Add your google-services.json (see google-services.json.example)
flutter run
```

### 5. Test a Call

```bash
curl -X POST http://localhost:3000/api/test/call \
  -H "Content-Type: application/json" \
  -d '{"type":"wakeup"}'
```

Your phone rings. You answer. Jarvis starts the protocol.

---

## ⚙️ Configuration

All configuration is in `.env`. Copy `.env.example` to get started:

| Variable | Description | Default |
|----------|-------------|---------|
| `OLLAMA_API_KEY` | Ollama Cloud API key | — |
| `OLLAMA_BASE_URL` | Ollama Cloud endpoint | `https://ollama.com/v1` |
| `OLLAMA_MODEL` | LLM model | `gemma3:12b` |
| `GROQ_API_KEY` | Groq API key (for STT) | — |
| `GROQ_BASE_URL` | Groq endpoint | `https://api.groq.com/openai/v1` |
| `STT_MODEL` | Whisper model | `whisper-large-v3` |
| `LIVEKIT_URL` | LiveKit Cloud WebSocket URL | — |
| `LIVEKIT_API_KEY` | LiveKit API key | — |
| `LIVEKIT_API_SECRET` | LiveKit API secret | — |
| `EDGE_TTS_VOICE` | Microsoft neural voice | `en-GB-RyanNeural` |
| `DATABASE_URL` | PostgreSQL connection string | — |
| `AGENT_SECRET` | Shared secret for agent↔backend auth | — |

---

## 🗓️ Call Schedule

| Time (IST) | Call Type | Protocol |
|:----------:|:---------:|----------|
| 05:00 AM | 🔆 Wakeup | Identity verify → Quiz → Schedule review → Focus plan |
| 05:20-06:40 | 🔁 Wakeup retries | Every 20 min if missed (up to 6 times) |
| 08:00 AM | ✅ Check-in | Identity verify → Task review → Next task |
| 12:00 PM | ✅ Check-in | Same protocol |
| 04:00 PM | ✅ Check-in | Same protocol |
| 08:00 PM | 🌙 Evening | Identity verify → Task review → 5 pillars → Day score |
| 11:00 PM | 🌙 Night review | Final accountability check |

---

## 📁 Project Structure

```
jarvis/
├── agent/             # LiveKit Voice Agent (Python)
│   ├── agent.py         # Main pipeline — STT/LLM/TTS + protocols
│   └── requirements.txt
├── backend/           # Fastify API server (Node.js)
│   ├── src/server.js    # Routes, scheduler, push notifications
│   └── service-account.json  # Firebase (gitignored)
├── app/               # Flutter mobile app
│   └── lib/
│       ├── screens/      # Home, Call, History, Tasks, Calendar
│       ├── database/      # Local SQLite
│       └── config.dart   # Server URL config
├── db/                # PostgreSQL migrations
│   └── 001-007_*.sql   # Schema + seed data
├── .env.example       # Template for all environment variables
├── start.sh           # One-command service startup
├── PLAN.md            # Architecture planning doc
└── README.md          # This file
```

---

## 🛡️ Security

Phase 2 (Jun 7 2026) brought the system to a **B+** grade for a personal
single-VPS deployment. Highlights:

- **Passphrase safety** — `I'm Tony Stark` lives only in the DB. No LLM
  prompt anywhere in the codebase contains it. Server-side timing-safe
  compare via `crypto.timingSafeEqual`.
- **Auth surface** — two distinct secrets: `AGENT_SECRET` (Python agent ↔
  Node backend, header `X-Agent-Secret`) and `APP_API_KEY` (Flutter app,
  header `X-App-Key`). Both checked with constant-time equality. If
  `APP_API_KEY` is unset, app routes return 503 rather than accidentally
  opening up.
- **Rate limiting** — `/api/verify-identity` caps at 5 attempts per 5 min
  per IP so the passphrase can't be brute-forced.
- **Input validation** — all `time` fields in daily log are regex-validated
  before reaching Postgres (no more `invalid input syntax for type time`).
- **DoS hardening** — JSON body limit 100KB, startup preflight refuses
  to boot without secrets, db CHECK constraints.

Known gaps (kept as-is for a personal single-user project):
- No HTTPS — fine for a single-VPS deployment you control; the app hits
  `http://93.127.206.82:3000` directly. Add Caddy + a domain when you ever
  expose this to a network you don't control.
- CORS is wide open by default — fine for single-user; `CORS_ORIGIN` env
  exists for when it isn't.

## 🗺️ Roadmap

### Phase 1 — Foundation & Calls ✅ DONE
- [x] Voice pipeline (LiveKit Agent → STT → LLM → TTS)
- [x] Identity verification protocol
- [x] Morning wakeup with quiz + schedule review
- [x] Check-in and evening review calls (6 personas)
- [x] Push notification call triggering (FCM)
- [x] Streaming TTS for faster responses
- [x] Groq Whisper v3 for sub-second STT
- [x] Daemonized services (setsid + supervisor restart loop)
- [x] Text chat fallback (same prompts, same tools)
- [x] 5-pillar daily log + auto-seeded master schedule

### Phase 2 — Security Hardening ✅ DONE (commit `3d062c4`, Jun 7 2026)
- [x] DB CHECK constraint widened (`call_queue.status` was rejecting call-end writes)
- [x] Passphrase removed from every LLM system prompt — server-side verify only
- [x] `APP_API_KEY` middleware on all app + chat + verify-identity endpoints
- [x] `AGENT_SECRET` timing-safe comparison (SHA-256 + `crypto.timingSafeEqual`)
- [x] Per-IP rate limit on `/api/verify-identity` (5/5min)
- [x] Time-field validation in `/api/agent/daily-log` (regex `^([01]\d|2[0-3]):[0-5]\d`)
- [x] Body size cap (`express.json({ limit: '100kb' })`)
- [x] CORS configurable via `CORS_ORIGIN` env
- [x] Startup preflight — refuses to start without `DATABASE_URL` + `AGENT_SECRET`
- [x] `start.sh` port-based kill + agent supervisor loop (no more orphan processes)
- [x] Status command reports pids + port + health all together

### Phase 3 — Memory & Continuity 🚧 IN PROGRESS
- [ ] Missed-call retry with escalation (wakeup +20/+40/+60/+80/+100 min)
- [ ] Persistent memory across calls (pgvector + embeddings)
- [ ] Top-K memory retrieval injected into system prompt
- [ ] Daily summary writer + streak tracking
- [ ] Settings screen (passphrase, timezone, voice persona, wake hour)
- [ ] Device token store → Postgres (auto-prune stale FCM tokens)

### Phase 4 — Tests & Polish 📋 PLANNED
- [ ] Jest unit tests for backend (auth, tools, prompts)
- [ ] pytest for agent (prompt builders, call-end detector)
- [ ] Code session tracker (6:30-10:30 PM focus block)
- [ ] Reminder system (drink water, "10 min to code")
- [ ] Agent healthcheck endpoint
- [ ] Multi-user support (drop the `LIMIT 1` everywhere)
- [ ] iOS app

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

<div align="center">

**Built with ❤️ and accountability**

</div>