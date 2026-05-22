# Jarvis — AI Accountability Companion

An AI that comes to you first — proactive voice calls, accountability follow-ups, persistent memory. Not a chatbot. An AI relationship layer that refuses to let you disappear from your own goals.

## Architecture

```
Flutter App (push notif + voice UI + chat)
    |              |              |
    | FCM          | HTTPS        | WebRTC
    v              v              v
Firebase    Fastify API      LiveKit Cloud
            (Node.js)        (voice transport)
                |                |
                |           LiveKit Agent
                |           (Python voice pipeline)
                |                |
    +-----------+-----------+----+
    |           |           |
PostgreSQL   Groq Whisper  Ollama Cloud
+ pgvector   (STT)        (LLM — gemma3:12b)
    |
Supabase (free tier)
```

## Free Tech Stack

| Layer | Tech | Cost |
|-------|------|------|
| LLM | Ollama Cloud (gemma3:12b) | Free |
| STT | Groq Whisper v3 | Free (2k req/day) |
| TTS | Edge TTS (streaming) | Free |
| Voice | LiveKit Cloud | Free (10k min/mo) |
| Backend | Fastify (Node.js) | Free |
| Database | Supabase PostgreSQL | Free |
| Push | Firebase FCM | Free |
| Mobile | Flutter | Open source |

**Total cost: $0.**

## Quick Start

### 1. Prerequisites

- Node.js 18+
- Python 3.12+
- Flutter (for mobile app)
- Docker (only if using local STT instead of Groq)
- Accounts: [Ollama](https://ollama.com), [Groq](https://console.groq.com), [LiveKit Cloud](https://cloud.livekit.io), [Supabase](https://supabase.com), [Firebase](https://firebase.google.com)

### 2. Configuration

```bash
cp .env.example .env
# Edit .env with your API keys and service URLs
```

### 3. Database Setup

Run the SQL migrations in `db/` against your Supabase PostgreSQL instance.

### 4. Start the Server

```bash
./start.sh start
```

### 5. Mobile App

```bash
cd app
flutter run
```

## Project Structure

```
jarvis/
  agent/          # LiveKit Voice Agent (Python)
    agent.py        # Main agent — STT/LLM/TTS pipeline + protocols
    requirements.txt
    venv/
  backend/        # Fastify API server (Node.js)
    src/server.js   # API routes, scheduler, push notifications
    service-account.json  # Firebase credentials (gitignored)
  app/            # Flutter mobile app
    lib/
      screens/       # Home, Call, History, Tasks, Calendar
      database/     # Local SQLite
    android/        # Native FCM + call notification handling
  db/             # PostgreSQL migration files
  .env.example    # Template for environment variables
  start.sh        # Service startup script
```

## Voice Call Types

| Call | Time | Protocol |
|------|------|----------|
| Wakeup | 5 AM (with retries) | Identity verify, morning briefing, 5-question quiz, schedule review |
| Checkin | 8 AM, 12 PM, 4 PM | Identity verify, task review, next task briefing |
| Evening | 11 PM | Identity verify, task review, 5 pillars (food/gym/code/office/books), day score |
| Manual | On demand | Identity verify, general assistance |

## License

MIT