import { env } from "../config/env.js";

export async function generateEmbedding(text: string): Promise<number[]> {
  const response = await fetch(`${env.LLM_BASE_URL}/embeddings`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${env.LLM_API_KEY}`,
    },
    body: JSON.stringify({
      input: text,
      model: env.EMBEDDING_MODEL,
    }),
  });

  if (!response.ok) {
    throw new Error(`Embedding API error: ${response.status} ${await response.text()}`);
  }

  const data = (await response.json()) as any;
  return data.data[0].embedding;
}

export function truncateText(text: string, maxChars: number = 8000): string {
  return text.length > maxChars ? text.slice(0, maxChars) : text;
}
