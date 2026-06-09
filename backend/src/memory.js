// ── Memory API routes ──────────────────────────────────────────────────────────
// Provides endpoints for saving, searching, and retrieving persistent memories.
// Used by the Python agent (via X-Agent-Secret) and the text chat system.
//
// Two memory stores:
//   1. `user_context` — key-value facts (e.g. "diet_preference" → "vegetarian, 3000 cal")
//   2. `memories`     — vector-searchable episodic memories with embeddings
//
// Both are scoped per user. In single-user mode (no X-User-Id), falls back to the
// first profile.

import { generateEmbedding } from './embeddings.js';

// ── Helper: resolve userId from request ────────────────────────────────────────
// Priority: X-User-Id header (from agent) > fallback to first profile
async function resolveUserId(req, pool) {
  const headerUserId = req.headers['x-user-id'];
  if (headerUserId) return headerUserId;

  // Fallback: single-user mode
  try {
    const result = await pool.query('SELECT id FROM public.profiles LIMIT 1');
    return result.rows[0]?.id || null;
  } catch (err) {
    console.error('[Memory] getUserId failed:', err.message);
    return null;
  }
}

// ── Mount memory routes on the Express app ─────────────────────────────────────
export function mountMemoryRoutes(app, pool, agentAuth, appAuth) {
  // Auth: accept either agent secret OR app key
  function memoryAuth(req, res, next) {
    const agentOk = req.headers['x-agent-secret'] &&
      timingSafeEqualStr(req.headers['x-agent-secret'], process.env.AGENT_SECRET || '');
    if (agentOk) return next();

    const APP_API_KEY = process.env.APP_API_KEY || '';
    if (!APP_API_KEY) return res.status(503).json({ error: 'App API key not configured' });
    if (!timingSafeEqualStr(req.headers['x-app-key'], APP_API_KEY)) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    next();
  }

  // ── POST /api/memory/save — Save a key-value fact ──────────────────────────
  // Body: { key: string, value: string, source_call_id?: string }
  // Upserts into user_context (unique on user_id, key)
  app.post('/api/memory/save', memoryAuth, async (req, res) => {
    try {
      const userId = await resolveUserId(req, pool);
      if (!userId) return res.status(404).json({ error: 'No user found' });

      const { key, value, source_call_id } = req.body;
      if (!key || !value) return res.status(400).json({ error: 'key and value required' });

      await pool.query(
        `INSERT INTO public.user_context (user_id, key, value, source_call_id)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (user_id, key) DO UPDATE
           SET value = EXCLUDED.value, updated_at = NOW()`,
        [userId, key, value, source_call_id || null]
      );

      res.json({ ok: true, key, value });
    } catch (err) {
      console.error('[Memory] /api/memory/save:', err.message);
      res.status(500).json({ error: err.message });
    }
  });

  // ── GET /api/memory/context — Get all key-value context for a user ──────────
  app.get('/api/memory/context', memoryAuth, async (req, res) => {
    try {
      const userId = await resolveUserId(req, pool);
      if (!userId) return res.status(404).json({ error: 'No user found' });

      const { rows } = await pool.query(
        'SELECT key, value, updated_at FROM public.user_context WHERE user_id = $1 ORDER BY updated_at DESC',
        [userId]
      );

      res.json({ context: rows });
    } catch (err) {
      console.error('[Memory] /api/memory/context:', err.message);
      res.status(500).json({ error: err.message });
    }
  });

  // ── GET /api/memory/search — Semantic search across memories ────────────────
  // Query params: ?q=<query>&limit=<5>
  // Generates an embedding for the query, does cosine similarity search
  app.get('/api/memory/search', memoryAuth, async (req, res) => {
    try {
      const userId = await resolveUserId(req, pool);
      if (!userId) return res.status(404).json({ error: 'No user found' });

      const query = req.query.q || '';
      const limit = parseInt(req.query.limit) || 5;

      if (!query.trim()) return res.json({ results: [] });

      // Generate embedding for the search query
      const embedding = await generateEmbedding(query);
      if (!embedding) {
        // Fallback: keyword search on content if embedding fails
        const { rows } = await pool.query(
          `SELECT id, content, memory_type, importance, created_at
           FROM public.memories
           WHERE user_id = $1 AND content ILIKE $2
           ORDER BY importance DESC, created_at DESC
           LIMIT $3`,
          [userId, `%${query}%`, limit]
        );
        return res.json({ results: rows.map(r => ({ ...r, score: null })) });
      }

      // Vector similarity search using cosine distance
      const embeddingStr = `[${embedding.join(',')}]`;
      const { rows } = await pool.query(
        `SELECT id, content, memory_type, importance, created_at,
                1 - (embedding <=> $1::vector) AS score
         FROM public.memories
         WHERE user_id = $2 AND embedding IS NOT NULL
         ORDER BY embedding <=> $1::vector
         LIMIT $3`,
        [embeddingStr, userId, limit]
      );

      // Also search user_context for keyword matches (supplement vector results)
      const { rows: contextRows } = await pool.query(
        `SELECT key, value, updated_at
         FROM public.user_context
         WHERE user_id = $1 AND (key ILIKE $2 OR value ILIKE $2)
         ORDER BY updated_at DESC
         LIMIT 5`,
        [userId, `%${query}%`]
      );

      res.json({
        results: rows.filter(r => r.score > 0.5), // Only reasonably relevant results
        context: contextRows,
      });
    } catch (err) {
      console.error('[Memory] /api/memory/search:', err.message);
      res.status(500).json({ error: err.message });
    }
  });

  // ── POST /api/memory/episode — Save an episodic memory with auto-embedding ──
  // Body: { content: string, memory_type?: 'episodic'|'semantic'|'preference',
  //          importance?: 1-5, call_log_id?: string }
  app.post('/api/memory/episode', memoryAuth, async (req, res) => {
    try {
      const userId = await resolveUserId(req, pool);
      if (!userId) return res.status(404).json({ error: 'No user found' });

      const { content, memory_type, importance, call_log_id } = req.body;
      if (!content) return res.status(400).json({ error: 'content required' });

      const memType = ['episodic', 'semantic', 'preference'].includes(memory_type)
        ? memory_type : 'episodic';
      const imp = Math.min(5, Math.max(1, importance || 3));

      // Generate embedding (non-blocking — store without if it fails)
      const embedding = await generateEmbedding(content);
      const embeddingStr = embedding ? `[${embedding.join(',')}]` : null;

      const result = await pool.query(
        `INSERT INTO public.memories (user_id, content, memory_type, importance, embedding, call_log_id)
         VALUES ($1, $2, $3, $4, $5::vector, $6)
         RETURNING id, content, memory_type, importance, created_at`,
        [userId, content, memType, imp, embeddingStr, call_log_id || null]
      );

      res.json({ ok: true, memory: result.rows[0] });
    } catch (err) {
      console.error('[Memory] /api/memory/episode:', err.message);
      res.status(500).json({ error: err.message });
    }
  });

  // ── POST /api/memory/consolidate — Trigger memory consolidation ─────────────
  // Body: { user_id?: string } (defaults to first user)
  // Processes un-summarized calls and extracts key facts into user_context + memories
  app.post('/api/memory/consolidate', agentAuth, async (req, res) => {
    try {
      const userId = req.headers['x-user-id'] || await resolveUserId(req, pool);
      if (!userId) return res.status(404).json({ error: 'No user found' });

      const result = await consolidateMemoriesForUser(userId, pool);
      res.json(result);
    } catch (err) {
      console.error('[Memory] /api/memory/consolidate:', err.message);
      res.status(500).json({ error: err.message });
    }
  });
}

// ── Memory consolidation logic ─────────────────────────────────────────────────
// Called nightly and on-demand. For each user:
//   1. Find un-summarized call logs
//   2. Extract key facts via LLM → save to user_context
//   3. Create episodic memories with embeddings → save to memories
//   4. Mark calls as summarized

export async function consolidateMemoriesForUser(userId, pool) {
  const { OLLAMA_BASE_URL, OLLAMA_API_KEY, OLLAMA_MODEL } = process.env;
  const ollamaUrl = OLLAMA_BASE_URL || 'https://ollama.com/v1';
  const ollamaKey = OLLAMA_API_KEY || '';
  const model = OLLAMA_MODEL || 'gemma3:12b';

  // Find un-summarized calls for this user (last 7 days, limit 20)
  const { rows: unsummarizedCalls } = await pool.query(
    `SELECT id, call_type, summary, started_at
     FROM public.call_logs
     WHERE user_id = $1 AND summarized = false
       AND summary IS NOT NULL AND summary != ''
       AND started_at > NOW() - INTERVAL '7 days'
     ORDER BY started_at ASC
     LIMIT 20`,
    [userId]
  );

  if (unsummarizedCalls.length === 0) {
    return { ok: true, processed: 0, message: 'No un-summarized calls to consolidate' };
  }

  let factsExtracted = 0;
  let memoriesCreated = 0;

  for (const call of unsummarizedCalls) {
    try {
      // Use LLM to extract key facts from the call summary
      const extractionPrompt = `Extract key facts, preferences, and notable events from this call summary.
Return JSON with two arrays:
- "facts": array of {key: string, value: string} — key factual observations (e.g. {"key": "diet_preference", "value": "vegetarian, 3000 cal target"})
- "episodes": array of {content: string, importance: 1-5, memory_type: "episodic"|"semantic"|"preference"} — memorable moments

Call type: ${call.call_type}
Summary: ${call.summary}

Keep facts concise (under 100 chars each). Limit to 5 facts and 3 episodes max.
Respond ONLY with valid JSON, no markdown.`;

      const headers = { 'Content-Type': 'application/json' };
      if (ollamaKey) headers['Authorization'] = `Bearer ${ollamaKey}`;

      const llmResp = await fetch(`${ollamaUrl}/chat/completions`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          model,
          messages: [{ role: 'user', content: extractionPrompt }],
          stream: false,
          temperature: 0.3,
        }),
        signal: AbortSignal.timeout(30_000),
      });

      if (!llmResp.ok) {
        console.error(`[Consolidation] LLM error for call ${call.id}: ${llmResp.status}`);
        continue;
      }

      const llmData = await llmResp.json();
      const rawContent = llmData.choices?.[0]?.message?.content || '';

      // Parse JSON from LLM response (may have markdown fences)
      let extracted;
      try {
        const jsonStr = rawContent.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();
        extracted = JSON.parse(jsonStr);
      } catch {
        console.error(`[Consolidation] Failed to parse LLM output for call ${call.id}`);
        continue;
      }

      // Save key-value facts to user_context
      if (extracted.facts && Array.isArray(extracted.facts)) {
        for (const fact of extracted.facts.slice(0, 5)) {
          if (fact.key && fact.value) {
            await pool.query(
              `INSERT INTO public.user_context (user_id, key, value, source_call_id)
               VALUES ($1, $2, $3, $4)
               ON CONFLICT (user_id, key) DO UPDATE
                 SET value = EXCLUDED.value, updated_at = NOW()`,
              [userId, fact.key.slice(0, 100), fact.value.slice(0, 500), call.id]
            );
            factsExtracted++;
          }
        }
      }

      // Save episodic memories
      if (extracted.episodes && Array.isArray(extracted.episodes)) {
        for (const ep of extracted.episodes.slice(0, 3)) {
          if (ep.content) {
            const embedding = await generateEmbedding(ep.content);
            const embeddingStr = embedding ? `[${embedding.join(',')}]` : null;
            const memType = ['episodic', 'semantic', 'preference'].includes(ep.memory_type)
              ? ep.memory_type : 'episodic';
            const imp = Math.min(5, Math.max(1, ep.importance || 3));

            await pool.query(
              `INSERT INTO public.memories (user_id, content, memory_type, importance, embedding, call_log_id)
               VALUES ($1, $2, $3, $4, $5::vector, $6)`,
              [userId, ep.content, memType, imp, embeddingStr, call.id]
            );
            memoriesCreated++;
          }
        }
      }

      // Mark call as summarized
      await pool.query(
        'UPDATE public.call_logs SET summarized = true WHERE id = $1',
        [call.id]
      );

    } catch (err) {
      console.error(`[Consolidation] Error processing call ${call.id}:`, err.message);
    }
  }

  console.log(`[Consolidation] User ${userId}: processed ${unsummarizedCalls.length} calls, ${factsExtracted} facts, ${memoriesCreated} memories`);
  return {
    ok: true,
    processed: unsummarizedCalls.length,
    facts_extracted: factsExtracted,
    memories_created: memoriesCreated,
  };
}

// ── Post-call memory processing ───────────────────────────────────────────────
// Called after a call ends. Generates embeddings for transcript messages
// and extracts quick facts (no LLM — just saves the summary as an episode).

export async function processCallMemories(callLogId, pool) {
  try {
    // Get call summary
    const { rows: callRows } = await pool.query(
      'SELECT id, user_id, call_type, summary FROM public.call_logs WHERE id = $1',
      [callLogId]
    );
    if (callRows.length === 0 || !callRows[0].summary) return;

    const call = callRows[0];

    // Save the call summary as an episodic memory with embedding
    if (call.summary.length >= 20) {
      const embedding = await generateEmbedding(call.summary);
      const embeddingStr = embedding ? `[${embedding.join(',')}]` : null;

      await pool.query(
        `INSERT INTO public.memories (user_id, content, memory_type, importance, embedding, call_log_id)
         VALUES ($1, $2, 'episodic', 3, $3::vector, $4)`,
        [call.user_id, `(${call.call_type}) ${call.summary}`, embeddingStr, call.id]
      ).catch(err => {
        // If embedding insert fails (e.g. dimension mismatch), try without
        console.error('[Memory] Embedding insert failed, trying without:', err.message);
        pool.query(
          `INSERT INTO public.memories (user_id, content, memory_type, importance, call_log_id)
           VALUES ($1, $2, 'episodic', 3, $3)`,
          [call.user_id, `(${call.call_type}) ${call.summary}`, call.id]
        ).catch(e => console.error('[Memory] Fallback memory insert also failed:', e.message));
      });
    }

    // Generate embeddings for transcript messages (async, non-blocking)
    const { rows: transcripts } = await pool.query(
      `SELECT id, role, content FROM public.call_transcripts
       WHERE call_log_id = $1 AND role IN ('user', 'assistant')
         AND content IS NOT NULL AND length(content) > 20
       ORDER BY created_at`,
      [callLogId]
    );

    // Process embeddings in background — don't block the response
    setImmediate(async () => {
      for (const t of transcripts.slice(0, 20)) { // Limit to 20 messages per call
        try {
          const emb = await generateEmbedding(t.content);
          if (emb) {
            await pool.query(
              'UPDATE public.call_transcripts SET embedding = $1 WHERE id = $2',
              [`[${emb.join(',')}]`, t.id]
            ).catch(() => {}); // Silently ignore embedding update failures
          }
        } catch {
          // Non-fatal — move on
        }
      }

      // Update embedding model tracking
      const embModel = process.env.EMBEDDING_MODEL || 'nomic-embed-text';
      await pool.query(
        'UPDATE public.call_logs SET embedding_model = $1 WHERE id = $2',
        [embModel, callLogId]
      ).catch(() => {});

      console.log(`[Memory] Processed embeddings for call ${callLogId}`);
    });

  } catch (err) {
    console.error('[Memory] processCallMemories error:', err.message);
  }
}

// ── Fetch relevant memories for a call type ────────────────────────────────────
// Called before building a system prompt to inject context.
// Returns { memories: string[], context: string[] }

const MEMORY_QUERIES = {
  wakeup: 'morning routine goals habits preferences schedule',
  'checkin-morning': 'gym workout diet breakfast morning habits',
  'checkin-midday': 'work productivity lunch diet discipline',
  'checkin-afternoon': 'work progress diet afternoon habits coding',
  evening: 'dinner coding projects evening routine',
  night: 'day review sleep habits books reading goals reflection',
  jarvis: 'preferences goals habits projects important facts',
};

export async function fetchRelevantMemories(userId, callType, pool) {
  const results = { memories: [], context: [] };
  const query = MEMORY_QUERIES[callType] || 'preferences goals habits';

  try {
    // 1. Search episodic memories by vector similarity
    const embedding = await generateEmbedding(query);
    if (embedding) {
      const embeddingStr = `[${embedding.join(',')}]`;
      const { rows } = await pool.query(
        `SELECT content, memory_type, importance,
                1 - (embedding <=> $1::vector) AS score
         FROM public.memories
         WHERE user_id = $2 AND embedding IS NOT NULL
         ORDER BY embedding <=> $1::vector
         LIMIT 5`,
        [embeddingStr, userId]
      );

      results.memories = rows
        .filter(r => r.score > 0.5)
        .map(r => `- [${r.memory_type}] ${r.content} (relevance: ${r.score.toFixed(2)})`);
    }

    // 2. Get key-value context (always return all — it's small)
    const { rows: contextRows } = await pool.query(
      'SELECT key, value FROM public.user_context WHERE user_id = $1 ORDER BY updated_at DESC',
      [userId]
    );

    results.context = contextRows.map(r => `- ${r.key}: ${r.value}`);

  } catch (err) {
    console.error('[Memory] fetchRelevantMemories error:', err.message);
    // Return empty rather than break the call
  }

  return results;
}

// ── Timing-safe string compare (needed here for memoryAuth) ──────────────────
import crypto from 'crypto';

function timingSafeEqualStr(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const aH = crypto.createHash('sha256').update(a).digest();
  const bH = crypto.createHash('sha256').update(b).digest();
  return crypto.timingSafeEqual(aH, bH);
}