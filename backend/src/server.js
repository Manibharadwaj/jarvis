import { config } from 'dotenv';
import { resolve } from 'path';
import { fileURLToPath } from 'url';

// Load .env from project root regardless of where the process is started from
const __dirname = fileURLToPath(new URL('.', import.meta.url));
config({ path: resolve(__dirname, '../../.env') });

import express from 'express';
import cors from 'cors';
import admin from 'firebase-admin';
import { readFileSync, writeFileSync } from 'fs';
import { AccessToken, RoomServiceClient } from 'livekit-server-sdk';
import pg from 'pg';
import cron from 'node-cron';

const { Pool } = pg;

const PORT             = process.env.PORT || 3000;
const LIVEKIT_URL      = process.env.LIVEKIT_URL || '';
const LIVEKIT_API_KEY  = process.env.LIVEKIT_API_KEY || '';
const LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET || '';
const AGENT_SECRET     = process.env.AGENT_SECRET || 'jarvis-agent-2024';
const OLLAMA_KEY       = process.env.OLLAMA_API_KEY || '';
const MODEL_NAME       = process.env.OLLAMA_MODEL || 'gpt-oss:120b';

// ── Database ──────────────────────────────────────────────────────────────────

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl:  { rejectUnauthorized: false },
  max:  5,
  idleTimeoutMillis: 30000,
});

pool.on('error', (err) => {
  console.error('PG pool error:', err.message);
});

async function getUserId() {
  try {
    const result = await pool.query('SELECT id FROM public.profiles LIMIT 1');
    return result.rows[0]?.id || null;
  } catch (err) {
    console.error('getUserId failed:', err.message);
    return null;
  }
}

async function wasAnsweredToday(callType) {
  try {
    const result = await pool.query(
      `SELECT 1 FROM public.call_queue
       WHERE call_type = $1 AND status = 'answered'
       AND (created_at AT TIME ZONE 'Asia/Kolkata')::date = (NOW() AT TIME ZONE 'Asia/Kolkata')::date
       LIMIT 1`,
      [callType]
    );
    return result.rowCount > 0;
  } catch (err) {
    console.error('wasAnsweredToday failed:', err.message);
    return false;
  }
}

// ── Firebase ──────────────────────────────────────────────────────────────────

const serviceAccount = JSON.parse(
  readFileSync(new URL('../service-account.json', import.meta.url), 'utf-8')
);
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

// Persist tokens to disk so scheduler works after server restarts
const TOKEN_FILE = new URL('../device_tokens.json', import.meta.url);

function loadTokens() {
  try { return new Set(JSON.parse(readFileSync(TOKEN_FILE, 'utf-8'))); }
  catch { return new Set(); }
}
function saveTokens() {
  try { writeFileSync(TOKEN_FILE, JSON.stringify([...deviceTokens])); }
  catch (e) { console.error('saveTokens failed:', e.message); }
}

const deviceTokens = loadTokens();
if (deviceTokens.size > 0) console.log(`Loaded ${deviceTokens.size} saved device token(s)`);

// ── Express ───────────────────────────────────────────────────────────────────

const app = express();
app.use(cors());
app.use(express.json());

// ── Helpers ───────────────────────────────────────────────────────────────────

async function createScheduledRoom(prefix) {
  const roomName = `${prefix}-${Date.now()}`;
  const roomService = new RoomServiceClient(LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET);
  await roomService.createRoom({ name: roomName, emptyTimeout: 600 });
  return roomName;
}

async function pushCall(roomName, callType) {
  const tokens = Array.from(deviceTokens);
  if (tokens.length === 0) {
    console.warn(`[Scheduler] No devices registered — skipping push for ${callType}`);
    return;
  }
  const result = await admin.messaging().sendEachForMulticast({
    tokens,
    data: { type: 'incoming_call', caller: 'Jarvis', call_type: callType, room_name: roomName },
    android: { priority: 'high', ttl: 60 },
  });
  console.log(`[Scheduler] Push for ${callType}: ${result.successCount} ok, ${result.failureCount} fail`);
}

async function triggerScheduledCall(callType) {
  if (!LIVEKIT_URL) return;
  try {
    const roomName = await createScheduledRoom(callType);
    await pushCall(roomName, callType);
    console.log(`[Scheduler] ${callType} call triggered → room: ${roomName}`);
    // Log to DB — best-effort, don't block push
    pool.query(
      `INSERT INTO public.call_queue (call_type, scheduled_at, status, room_name)
       VALUES ($1, NOW(), 'sent', $2)`,
      [callType, roomName]
    ).catch(e => console.error(`[Scheduler] call_queue insert failed:`, e.message));
  } catch (err) {
    console.error(`[Scheduler] ${callType} trigger failed:`, err.message);
  }
}

// ── Scheduler (IST = UTC+5:30) ────────────────────────────────────────────────

const TZ = 'Asia/Kolkata';

// 5:00 AM — Wakeup call
cron.schedule('0 5 * * *', () => triggerScheduledCall('wakeup'), { timezone: TZ });

// 5:20 AM — Wakeup retry 1
cron.schedule('20 5 * * *', async () => {
  if (!await wasAnsweredToday('wakeup')) triggerScheduledCall('wakeup');
}, { timezone: TZ });

// 5:40 AM — Wakeup retry 2
cron.schedule('40 5 * * *', async () => {
  if (!await wasAnsweredToday('wakeup')) triggerScheduledCall('wakeup');
}, { timezone: TZ });

// Check-ins at 8 AM, 12 PM, 4 PM, 8 PM
cron.schedule('0 8  * * *', () => triggerScheduledCall('checkin'), { timezone: TZ });
cron.schedule('0 12 * * *', () => triggerScheduledCall('checkin'), { timezone: TZ });
cron.schedule('0 16 * * *', () => triggerScheduledCall('checkin'), { timezone: TZ });
cron.schedule('0 20 * * *', () => triggerScheduledCall('checkin'), { timezone: TZ });

// 11:00 PM — Evening review
cron.schedule('0 23 * * *', () => triggerScheduledCall('evening'), { timezone: TZ });

// ── Auth middleware for agent calls ───────────────────────────────────────────

function agentAuth(req, res, next) {
  if (req.headers['x-agent-secret'] !== AGENT_SECRET) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  next();
}

// ── API Routes ────────────────────────────────────────────────────────────────

app.get('/health', (_req, res) => res.json({ ok: true }));

// ── Ollama chat (manual chat fallback) ────────────────────────────────────────

app.post('/api/chat', async (req, res) => {
  try {
    const { messages, mode } = req.body;
    if (!OLLAMA_KEY) return res.status(400).json({ error: 'OLLAMA_API_KEY not set' });

    const VERIFY = `You are Jarvis, Tony Stark's AI. CRITICAL: Start EVERY response with "GRANTED:" or "DENIED:". Secret: "I'm Tony Stark". If correct say GRANTED: and welcome. If wrong say DENIED: and ask again. Under 2 sentences.`;
    const CHAT   = `You are Jarvis, Tony Stark's AI. Loyal, professional, British, witty. Under 3 sentences. No markdown.`;
    const system = mode === 'chat' ? CHAT : VERIFY;

    const resp = await fetch('https://ollama.com/api/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${OLLAMA_KEY}` },
      body: JSON.stringify({ model: MODEL_NAME, messages: [{ role: 'system', content: system }, ...messages], stream: false }),
    });
    if (!resp.ok) return res.status(502).json({ error: 'Ollama error', detail: await resp.text() });
    const data = await resp.json();
    res.json({ response: data.message.content });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Device token registration ─────────────────────────────────────────────────

app.post('/api/register-token', (req, res) => {
  const { token } = req.body;
  if (!token) return res.status(400).json({ error: 'token required' });
  deviceTokens.add(token);
  saveTokens();
  console.log(`Device registered: ${token.slice(0, 20)}… (total: ${deviceTokens.size})`);
  res.json({ ok: true, registered: deviceTokens.size });
});

// ── Manual push (test / manual call trigger) ──────────────────────────────────

app.post('/api/call/push', async (req, res) => {
  try {
    const tokens = Array.from(deviceTokens);
    if (tokens.length === 0) return res.status(400).json({ error: 'No devices registered' });
    const result = await admin.messaging().sendEachForMulticast({
      tokens,
      data: { type: 'incoming_call', caller: 'Jarvis' },
      android: { priority: 'high', ttl: 86400 },
    });
    res.json({ ok: true, sent: result.successCount });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── LiveKit: manual call (creates a new room) ─────────────────────────────────

app.post('/api/voice/start', async (req, res) => {
  if (!LIVEKIT_URL || !LIVEKIT_API_KEY || !LIVEKIT_API_SECRET)
    return res.status(503).json({ error: 'LiveKit not configured' });
  try {
    const roomName = `jarvis-${Date.now()}`;
    const roomService = new RoomServiceClient(LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET);
    await roomService.createRoom({ name: roomName, emptyTimeout: 300 });
    const at = new AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET, { identity: 'stark', ttl: '1h' });
    at.addGrant({ roomJoin: true, room: roomName, canPublish: true, canSubscribe: true });
    const token = await at.toJwt();
    res.json({ url: LIVEKIT_URL, token, roomName });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── LiveKit: join a scheduled room ────────────────────────────────────────────

app.post('/api/voice/join', async (req, res) => {
  if (!LIVEKIT_URL || !LIVEKIT_API_KEY || !LIVEKIT_API_SECRET)
    return res.status(503).json({ error: 'LiveKit not configured' });
  const { roomName } = req.body;
  if (!roomName) return res.status(400).json({ error: 'roomName required' });
  try {
    const at = new AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET, { identity: 'stark', ttl: '1h' });
    at.addGrant({ roomJoin: true, room: roomName, canPublish: true, canSubscribe: true });
    const token = await at.toJwt();

    // Mark as answered so retry scheduler stops — best-effort, don't block the response
    pool.query(
      `UPDATE public.call_queue SET status = 'answered', answered_at = NOW() WHERE room_name = $1`,
      [roomName]
    ).catch(e => console.error('call_queue update failed:', e.message));

    res.json({ url: LIVEKIT_URL, token, roomName });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Agent API — protected by X-Agent-Secret ───────────────────────────────────

// GET today's tasks + daily log for the single user
app.get('/api/agent/today', agentAuth, async (req, res) => {
  try {
    const userId = await getUserId();
    if (!userId) return res.status(404).json({ error: 'No user found' });

    const [tasksResult, logResult] = await Promise.all([
      pool.query(
        `SELECT id, title, time_slot, category, done, skipped, skip_reason, rescheduled_to
         FROM public.master_schedule
         WHERE user_id = $1 AND date = (NOW() AT TIME ZONE 'Asia/Kolkata')::date
         ORDER BY time_slot NULLS LAST, created_at`,
        [userId]
      ),
      pool.query(
        `SELECT food_calories, food_notes, gym_done, gym_protein, gym_creatine,
                code_done, code_start_time, code_end_time, code_notes,
                office_in_time, office_out_time,
                books_title, books_pages, books_insights, day_score, day_notes
         FROM public.daily_log
         WHERE user_id = $1 AND date = (NOW() AT TIME ZONE 'Asia/Kolkata')::date`,
        [userId]
      ),
    ]);

    res.json({
      date: new Date().toISOString().split('T')[0],
      tasks: tasksResult.rows,
      daily_log: logResult.rows[0] || null,
    });
  } catch (err) {
    console.error('/api/agent/today:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// POST create a task
app.post('/api/agent/task', agentAuth, async (req, res) => {
  try {
    const userId = await getUserId();
    if (!userId) return res.status(404).json({ error: 'No user found' });
    const { title, time_slot, category } = req.body;
    if (!title) return res.status(400).json({ error: 'title required' });

    const result = await pool.query(
      `INSERT INTO public.master_schedule (user_id, date, title, time_slot, category)
       VALUES ($1, (NOW() AT TIME ZONE 'Asia/Kolkata')::date, $2, $3, $4)
       RETURNING id`,
      [userId, title, time_slot || null, category || 'other']
    );
    res.json({ ok: true, id: result.rows[0].id });
  } catch (err) {
    console.error('/api/agent/task POST:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// PATCH update a task
app.patch('/api/agent/task/:id', agentAuth, async (req, res) => {
  try {
    const { id } = req.params;
    const { done, skipped, skip_reason, rescheduled_to } = req.body;

    const sets = [];
    const vals = [];
    let i = 1;
    if (done !== undefined)         { sets.push(`done = $${i++}`);           vals.push(done); }
    if (skipped !== undefined)      { sets.push(`skipped = $${i++}`);        vals.push(skipped); }
    if (skip_reason !== undefined)  { sets.push(`skip_reason = $${i++}`);    vals.push(skip_reason); }
    if (rescheduled_to !== undefined) { sets.push(`rescheduled_to = $${i++}`); vals.push(rescheduled_to || null); }
    if (sets.length === 0) return res.status(400).json({ error: 'Nothing to update' });

    vals.push(id);
    await pool.query(
      `UPDATE public.master_schedule SET ${sets.join(', ')} WHERE id = $${i}`,
      vals
    );
    res.json({ ok: true });
  } catch (err) {
    console.error('/api/agent/task PATCH:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// PATCH update a single field in today's daily log (upsert)
app.patch('/api/agent/daily-log', agentAuth, async (req, res) => {
  try {
    const userId = await getUserId();
    if (!userId) return res.status(404).json({ error: 'No user found' });

    const allowed = [
      'food_calories', 'food_notes',
      'gym_done', 'gym_notes', 'gym_protein', 'gym_creatine',
      'code_done', 'code_start_time', 'code_end_time', 'code_notes',
      'office_in_time', 'office_out_time',
      'books_title', 'books_pages', 'books_insights',
      'day_score', 'day_notes',
    ];
    const { field, value } = req.body;
    if (!allowed.includes(field)) return res.status(400).json({ error: `Invalid field: ${field}` });

    // Parse value type
    let parsed = value;
    if (['gym_done', 'gym_protein', 'gym_creatine', 'code_done'].includes(field)) {
      parsed = value === true || value === 'true' || value === '1';
    } else if (['food_calories', 'books_pages', 'day_score'].includes(field)) {
      parsed = parseInt(value) || null;
    }

    await pool.query(
      `INSERT INTO public.daily_log (user_id, date, ${field})
       VALUES ($1, (NOW() AT TIME ZONE 'Asia/Kolkata')::date, $2)
       ON CONFLICT (user_id, date) DO UPDATE SET ${field} = EXCLUDED.${field}, updated_at = NOW()`,
      [userId, parsed]
    );
    res.json({ ok: true });
  } catch (err) {
    console.error('/api/agent/daily-log PATCH:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ── Test: manually trigger any call type ─────────────────────────────────────

app.post('/api/test/call', async (req, res) => {
  const { type } = req.body;
  const valid = ['wakeup', 'checkin', 'evening', 'jarvis'];
  if (!valid.includes(type)) return res.status(400).json({ error: `type must be one of: ${valid.join(', ')}` });
  try {
    const prefix = type === 'jarvis' ? 'jarvis' : type;
    const roomName = await createScheduledRoom(prefix);
    await pushCall(roomName, type);
    res.json({ ok: true, roomName });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Start ─────────────────────────────────────────────────────────────────────

app.listen(PORT, async () => {
  console.log(`Jarvis backend running on port ${PORT}`);

  try {
    await pool.query('SELECT 1');
    console.log('Database connected ✓');
  } catch (err) {
    console.error('Database connection FAILED:', err.message);
    console.error('Check DB_HOST / DB_USER / DB_PASSWORD in .env');
  }

  console.log(`Firebase Admin: project ${serviceAccount.project_id} ✓`);
  if (LIVEKIT_URL) console.log(`LiveKit: ${LIVEKIT_URL} ✓`);
  console.log('Scheduler armed (IST): 5AM wakeup, 8/12/4/8PM checkins, 11PM evening');
});
