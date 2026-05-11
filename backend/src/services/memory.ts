import { pool } from "../config/database.js";
import { env } from "../config/env.js";
import { generateEmbedding, truncateText } from "./embedding.js";

const MEMORY_TYPES = ["fact", "preference", "goal_detail", "emotional_event", "inside_joke"] as const;
type MemoryType = (typeof MEMORY_TYPES)[number];

function hasEmbeddingSupport(): boolean {
  return !!env.LLM_API_KEY;
}

export async function saveMemory(
  userId: string,
  type: MemoryType,
  content: string,
  importance: number = 0.5,
  confidence: number = 0.5
) {
  const truncated = truncateText(content);
  let embedding = null;

  if (hasEmbeddingSupport()) {
    try {
      embedding = await generateEmbedding(truncated);
    } catch {
      // proceed without embedding
    }
  }

  const result = await pool.query(
    `INSERT INTO memories (user_id, type, content, embedding, importance, confidence)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING id, user_id, type, content, importance, confidence, created_at`,
    [userId, type, content, embedding ? JSON.stringify(embedding) : null, importance, confidence]
  );

  return result.rows[0];
}

export async function searchMemories(
  userId: string,
  query: string,
  limit: number = 5,
  minImportance: number = 0
) {
  if (!hasEmbeddingSupport()) {
    const result = await pool.query(
      `SELECT id, type, content, importance, confidence, created_at
       FROM memories
       WHERE user_id = $1 AND importance >= $2
       ORDER BY created_at DESC
       LIMIT $3`,
      [userId, minImportance, limit]
    );
    return result.rows;
  }

  try {
    const embedding = await generateEmbedding(truncateText(query));
    const result = await pool.query(
      `SELECT id, type, content, importance, confidence, created_at,
              1 - (embedding <=> $1::vector) AS similarity
       FROM memories
       WHERE user_id = $2 AND importance >= $3 AND embedding IS NOT NULL
       ORDER BY embedding <=> $1::vector
       LIMIT $4`,
      [JSON.stringify(embedding), userId, minImportance, limit]
    );
    return result.rows;
  } catch {
    const result = await pool.query(
      `SELECT id, type, content, importance, confidence, created_at
       FROM memories
       WHERE user_id = $1 AND importance >= $2
       ORDER BY created_at DESC
       LIMIT $3`,
      [userId, minImportance, limit]
    );
    return result.rows;
  }
}

export async function getMemoriesByType(userId: string, type: MemoryType) {
  const result = await pool.query(
    "SELECT * FROM memories WHERE user_id = $1 AND type = $2 ORDER BY created_at DESC",
    [userId, type]
  );
  return result.rows;
}

export async function deleteMemory(userId: string, memoryId: string) {
  const result = await pool.query(
    "DELETE FROM memories WHERE id = $1 AND user_id = $2 RETURNING id",
    [memoryId, userId]
  );
  return result.rows.length > 0;
}
