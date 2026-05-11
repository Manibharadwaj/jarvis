import { pool } from "../config/database.js";

export async function recordEmotion(
  userId: string,
  mood: string,
  energy?: number,
  stress?: number
) {
  const result = await pool.query(
    `INSERT INTO emotional_states (user_id, mood, energy, stress)
     VALUES ($1, $2, $3, $4)
     RETURNING *`,
    [userId, mood, energy ?? null, stress ?? null]
  );
  return result.rows[0];
}

export async function getEmotionHistory(userId: string, days: number = 7) {
  const result = await pool.query(
    `SELECT * FROM emotional_states
     WHERE user_id = $1 AND recorded_at >= now() - make_interval(days => $2)
     ORDER BY recorded_at DESC`,
    [userId, days]
  );
  return result.rows;
}

export async function getLatestEmotion(userId: string) {
  const result = await pool.query(
    `SELECT * FROM emotional_states
     WHERE user_id = $1
     ORDER BY recorded_at DESC
     LIMIT 1`,
    [userId]
  );
  return result.rows[0] || null;
}

export async function detectMoodFromText(text: string, apiKey: string, baseUrl: string): Promise<{
  mood: string;
  energy: number;
  stress: number;
}> {
  const response = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: "llama-3.1-8b-instant",
      messages: [
        {
          role: "system",
          content:
            "Analyze the user's message and return JSON with mood (one word), energy (0-1), stress (0-1). Only return JSON, no explanation.",
        },
        { role: "user", content: text },
      ],
      temperature: 0,
    }),
  });

  const data = (await response.json()) as any;
  try {
    return JSON.parse(data.choices[0].message.content);
  } catch {
    return { mood: "neutral", energy: 0.5, stress: 0.5 };
  }
}
