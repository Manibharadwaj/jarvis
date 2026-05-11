# Jarvis - AI Accountability Companion

## Context

Building an AI that **comes to you first** - proactive voice calls, accountability follow-ups, persistent memory, emotional continuity. NOT a passive chatbot. The product is an "AI relationship layer" that refuses to let you disappear from your own goals.

**Constraints**: Only costs = VPS (4GB+ RAM) + LLM API key. Everything else must be free/open-source. Flutter mobile app. Push notification + in-app voice call for MVP.

## Architecture Overview

```
FLUTTER APP (push notif + voice UI + chat)
    |              |              |
    | FCM          | HTTPS        | WebRTC
    v              v              v
Firebase    Fastify API      LiveKit Server
            (Node.js)        (self-hosted)
                |                |
                |           LiveKit Agent
                |           (Python voice pipeline)
                |                |
    +-----------+-----------+----+
    |           |           |
PostgreSQL   Redis      LLM API
+ pgvector  (BullMQ)   (Groq/etc)
```

## Free Tech Stack

| Layer | Tech | Cost |
|-------|------|------|
| **LLM** | OpenAI-compatible API (Groq free / Together / OpenRouter) | Free tier or your API key |
| **STT** | Groq Whisper v3 (primary), faster-whisper local (fallback) | Free tier / self-hosted |
| **TTS** | Edge TTS (primary, free neural voices), Piper TTS (offline fallback) | Free |
| **Voice transport** | LiveKit self-hosted (open-source, Flutter SDK) | Free |
| **Voice pipeline** | LiveKit Agents (Python, built-in VAD + STT/LLM/TTS orchestration) | Free |
| **Backend** | Fastify (TypeScript) | Free |
| **Database** | PostgreSQL 16 + pgvector | Free |
| **Queue/Scheduling** | Redis + BullMQ | Free |
| **Push notifications** | Firebase Cloud Messaging | Free |
| **State management** | Riverpod (Flutter) | Free |
| **SSL** | Let's Encrypt + certbot | Free |

**Total cost: VPS + LLM API key only.**

## Database Schema (Key Tables)

- **users** - profile, preferences, wake/sleep times, mood, streak
- **goals** - title, category, frequency, check-in times, progress, streak
- **scheduled_calls** - call_type, scheduled_for, retry_count, retry_interval, status escalation
- **conversations** + **messages** - full conversation history
- **memories** - type (fact/preference/goal_detail/emotional_event/inside_joke), content, embedding (pgvector), importance, confidence
- **emotional_states** - mood, energy, stress over time (time series)
- **daily_plans** - morning intent, priorities, commitments, evening review, accountability score
- **relationship_state** - inside jokes, nicknames, rapport level, humor style

## Voice Call Flow

1. **BullMQ scheduler** picks up pending calls every minute
2. **Push notification** sent via FCM to Flutter app
3. User taps "Answer" -> **POST /voice/start** -> backend creates LiveKit room + dispatches Agent
4. Flutter connects to LiveKit room -> **voice conversation begins**
5. Agent pipeline: Silero VAD -> Groq Whisper STT -> LLM (with memory injection) -> Edge TTS
6. Agent function tools: search_memory, save_memory, detect_mood, update_goals
7. On conversation end: save to DB, update mood, schedule next check-in
8. If missed: **retry with escalation** (exponential backoff + chat fallback)

## Wake-Up Retry Algorithm

- 5 retries with exponential backoff (2min, 4min, 8min, 15min, 15min)
- Escalating notification tone: gentle -> firm -> concerned -> direct
- After retry 3: also send chat message fallback
- After 5 retries: mark missed, reset streak, log accountability event

## Project Structure

```
jarvis/
  backend/          # Fastify TypeScript API server
    src/
      config/       # env, database, redis, livekit, fcm
      routes/       # auth, users, goals, calls, voice, conversations, memory, plans
      services/     # auth, goal, call, memory, embedding, push, livekit, plan, emotion
      jobs/         # BullMQ workers (call-scheduler, retry-handler, daily-plan, evening-review)
      migrations/   # PostgreSQL schema migrations
  agent/            # LiveKit Voice Agent (Python)
    agents/         # jarvis_agent, wake_up_agent, check_in_agent, evening_review_agent
    tools/          # memory_tools, goal_tools, schedule_tools, emotion_tools
    providers/      # edge_tts, piper_tts, faster_whisper_stt
    prompts/        # system_prompt templates
  app/              # Flutter mobile app
    lib/
      core/         # theme, network, auth
      features/     # voice, chat, goals, dashboard, planning, notifications
      models/       # user, goal, call, conversation, memory
      shared/       # widgets, utils
  infra/            # docker-compose, livekit config, nginx, scripts
```

## VPS RAM Budget (4GB)

| Service | Limit |
|---------|-------|
| PostgreSQL | 1GB |
| Redis | 300MB |
| LiveKit Server | 1GB |
| Fastify Backend | 200MB |
| LiveKit Agent | 500MB |
| Nginx | 50MB |
| OS + overhead | ~500MB |
| **Total** | **~3.55GB** |

Leaves ~500MB headroom. Designed for single-user (1-2 concurrent calls).

## Build Phases

### Phase 0: Foundation (Week 1-2)
- Provision VPS, Docker setup
- Deploy PostgreSQL + pgvector, Redis
- Scaffold Fastify backend (health endpoint)
- Scaffold Flutter app (riverpod, API client)
- Nginx + Let's Encrypt SSL

### Phase 1: Auth + Goals + Push (Week 3-4)
- Auth (register, login, JWT)
- Goal CRUD endpoints
- FCM integration in Flutter
- Goals screen in Flutter
- Basic BullMQ push notification job

### Phase 2: Voice Pipeline (Week 5-7) - THE CORE
- Deploy LiveKit server
- Build LiveKit Agent: STT -> LLM -> TTS pipeline
- Voice call screen in Flutter (livekit_client)
- End-to-end: Push -> Tap -> Voice call -> Conversation

### Phase 3: Memory + Personality (Week 8-9)
- Embedding generation + pgvector search
- Memory tools in Agent (search, save)
- System prompt template with user context
- Emotional state detection
- Inside joke / relationship tracking

### Phase 4: Scheduling + Accountability (Week 10-11)
- Call scheduler + retry handler workers
- Wake-up retry algorithm with escalation
- Daily plan + evening review workers
- Streak tracking, accountability scoring
- Chat fallback for missed calls

### Phase 5: Polish (Week 12-13)
- Tune TTS voices, add Piper fallback
- Add faster-whisper offline STT fallback
- Memory consolidation worker
- Dashboard screens (streaks, mood trends)
- Security audit

### Phase 6: Future (Coding copilot, VS Code extension, avatars)

## Verification

1. **Phase 0**: `curl https://yourdomain/api/v1/health` returns 200
2. **Phase 1**: Register user, create goal, receive push notification
3. **Phase 2**: Push notification -> tap -> voice conversation with Jarvis
4. **Phase 3**: Tell Jarvis something in call 1, ask about it in call 2
5. **Phase 4**: Set wake-up time, verify calls arrive on schedule with retries
6. **Phase 5**: Miss 3 days, verify streak resets and Jarvis escalates

## Key Decisions

- **Fastify over NestJS**: ~50% less RAM, faster on constrained VPS
- **Python Agent + TypeScript API**: LiveKit Agents is Python-native; services communicate via LiveKit room + DB
- **Edge TTS over Groq PlayAI TTS**: Groq TTS free tier = 2 req/min, 500/day. Edge TTS = unlimited, no API key
- **PostgreSQL + pgvector over Pinecone/Qdrant**: Free, single-user scale is well within pgvector's capability
- **FCM over OneSignal**: Free, no branding requirements, mature Flutter SDK