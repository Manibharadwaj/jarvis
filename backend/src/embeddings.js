// ── Embedding generation service ──────────────────────────────────────────────
// Uses the same Ollama instance that powers the chat LLM.
// Generates 768-dim vectors via nomic-embed-text (or whatever EMBEDDING_MODEL is set to).
// Failures are logged but never throw — embedding is non-blocking.

const OLLAMA_BASE_URL = process.env.OLLAMA_BASE_URL || 'https://ollama.com/v1';
const OLLAMA_KEY = process.env.OLLAMA_API_KEY || '';
const EMBEDDING_MODEL = process.env.EMBEDDING_MODEL || 'nomic-embed-text';

/**
 * Generate an embedding vector for the given text.
 * Returns a number[] (768-dim for nomic-embed-text) or null on failure.
 */
export async function generateEmbedding(text) {
  if (!text || text.trim().length < 5) return null;

  // Truncate to ~8000 chars — embedding models have context limits
  const truncated = text.slice(0, 8000);

  try {
    const headers = { 'Content-Type': 'application/json' };
    if (OLLAMA_KEY) headers['Authorization'] = `Bearer ${OLLAMA_KEY}`;

    const resp = await fetch(`${OLLAMA_BASE_URL}/embeddings`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ model: EMBEDDING_MODEL, prompt: truncated }),
      signal: AbortSignal.timeout(30_000), // 30s timeout for embedding
    });

    if (!resp.ok) {
      const body = await resp.text().catch(() => '');
      console.error(`[Embedding] ${resp.status} from Ollama: ${body.slice(0, 200)}`);
      return null;
    }

    const data = await resp.json();
    if (!data.embedding || !Array.isArray(data.embedding)) {
      console.error('[Embedding] No embedding in response:', JSON.stringify(data).slice(0, 200));
      return null;
    }

    return data.embedding;
  } catch (err) {
    console.error(`[Embedding] Error generating embedding: ${err.message}`);
    return null;
  }
}

/**
 * Generate embeddings for multiple texts in batch.
 * Returns an array of number[] | null, same order as input.
 */
export async function generateEmbeddings(texts) {
  return Promise.all(texts.map(t => generateEmbedding(t)));
}