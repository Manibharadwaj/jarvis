import { pool } from "../config/database.js";
import crypto from "node:crypto";

function hashPassword(password: string): string {
  const salt = crypto.randomBytes(16).toString("hex");
  const hash = crypto.scryptSync(password, salt, 64).toString("hex");
  return `${salt}:${hash}`;
}

function verifyPassword(password: string, stored: string): boolean {
  const [salt, hash] = stored.split(":");
  const derived = crypto.scryptSync(password, salt, 64).toString("hex");
  return hash === derived;
}

export async function registerUser(email: string, displayName: string, password: string) {
  const existing = await pool.query("SELECT id FROM users WHERE email = $1", [email]);
  if (existing.rows.length > 0) {
    throw new Error("Email already registered");
  }

  const passwordHash = hashPassword(password);
  const result = await pool.query(
    `INSERT INTO users (email, display_name, password_hash)
     VALUES ($1, $2, $3)
     RETURNING id, email, display_name, created_at`,
    [email, displayName, passwordHash]
  );

  await pool.query(
    `INSERT INTO relationship_state (user_id) VALUES ($1)`,
    [result.rows[0].id]
  );

  return result.rows[0];
}

export async function loginUser(email: string, password: string) {
  const result = await pool.query(
    "SELECT id, email, display_name, password_hash FROM users WHERE email = $1",
    [email]
  );

  if (result.rows.length === 0) {
    throw new Error("Invalid email or password");
  }

  const user = result.rows[0];
  if (!verifyPassword(password, user.password_hash)) {
    throw new Error("Invalid email or password");
  }

  return { id: user.id, email: user.email, display_name: user.display_name };
}
