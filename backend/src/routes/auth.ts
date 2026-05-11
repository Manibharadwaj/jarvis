import { FastifyInstance } from "fastify";
import z from "zod";
import { pool } from "../config/database.js";
import { registerUser, loginUser } from "../services/auth.js";

const registerSchema = z.object({
  email: z.string().email(),
  display_name: z.string().min(1).max(100),
  password: z.string().min(6).max(128),
});

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

export async function authRoutes(app: FastifyInstance) {
  app.post("/api/v1/auth/register", async (req, reply) => {
    const body = registerSchema.parse(req.body);

    try {
      const user = await registerUser(body.email, body.display_name, body.password);
      const token = app.jwt.sign({ sub: user.id });
      reply.code(201).send({ user, token });
    } catch (err: any) {
      if (err.message === "Email already registered") {
        reply.code(409).send({ error: err.message });
      } else {
        reply.code(500).send({ error: "Internal server error" });
      }
    }
  });

  app.post("/api/v1/auth/login", async (req, reply) => {
    const body = loginSchema.parse(req.body);

    try {
      const user = await loginUser(body.email, body.password);
      const token = app.jwt.sign({ sub: user.id });
      reply.send({ user, token });
    } catch (err: any) {
      reply.code(401).send({ error: err.message || "Authentication failed" });
    }
  });

  app.get("/api/v1/auth/me", async (req, reply) => {
    await req.jwtVerify();
    const result = await pool.query(
      "SELECT id, email, display_name, timezone, wake_time, sleep_time, created_at FROM users WHERE id = $1",
      [req.user.sub]
    );
    if (result.rows.length === 0) {
      reply.code(404).send({ error: "User not found" });
      return;
    }
    reply.send({ user: result.rows[0] });
  });
}
