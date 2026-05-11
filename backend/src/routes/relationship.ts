import { FastifyInstance } from "fastify";
import z from "zod";
import { getRelationshipState, updateRapport, addInsideJoke, addNickname } from "../services/relationship.js";

export async function relationshipRoutes(app: FastifyInstance) {
  app.addHook("onRequest", async (req) => {
    await req.jwtVerify();
  });

  app.get("/api/v1/relationship", async (req, reply) => {
    const state = await getRelationshipState(req.user.sub);
    if (!state) {
      reply.code(404).send({ error: "No relationship state found" });
      return;
    }
    reply.send({ state });
  });

  app.post("/api/v1/relationship/rapport", async (req, reply) => {
    const { delta } = req.body as { delta: number };
    const level = await updateRapport(req.user.sub, delta);
    reply.send({ rapport_level: level });
  });

  app.post("/api/v1/relationship/inside-joke", async (req, reply) => {
    const { joke } = req.body as { joke: string };
    const jokes = await addInsideJoke(req.user.sub, joke);
    reply.send({ inside_jokes: jokes });
  });

  app.post("/api/v1/relationship/nickname", async (req, reply) => {
    const { nickname } = req.body as { nickname: string };
    const nicknames = await addNickname(req.user.sub, nickname);
    reply.send({ nicknames });
  });
}
