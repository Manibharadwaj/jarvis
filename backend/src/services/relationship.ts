import { pool } from "../config/database.js";

export async function getRelationshipState(userId: string) {
  const result = await pool.query(
    "SELECT * FROM relationship_state WHERE user_id = $1",
    [userId]
  );
  return result.rows[0] || null;
}

export async function updateRapport(userId: string, delta: number) {
  const result = await pool.query(
    `UPDATE relationship_state
     SET rapport_level = GREATEST(0, LEAST(1, rapport_level + $1)), updated_at = now()
     WHERE user_id = $2
     RETURNING rapport_level`,
    [delta, userId]
  );
  return result.rows[0]?.rapport_level;
}

export async function addInsideJoke(userId: string, joke: string) {
  const result = await pool.query(
    `UPDATE relationship_state
     SET inside_jokes = inside_jokes || $1::jsonb, updated_at = now()
     WHERE user_id = $2
     RETURNING inside_jokes`,
    [JSON.stringify([joke]), userId]
  );
  return result.rows[0]?.inside_jokes;
}

export async function addNickname(userId: string, nickname: string) {
  const result = await pool.query(
    `UPDATE relationship_state
     SET nicknames = nicknames || $1::jsonb, updated_at = now()
     WHERE user_id = $2
     RETURNING nicknames`,
    [JSON.stringify([nickname]), userId]
  );
  return result.rows[0]?.nicknames;
}
