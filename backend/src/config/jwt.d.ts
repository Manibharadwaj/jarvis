import "fastify";
import "@fastify/jwt";

declare module "fastify" {
  interface FastifyRequest {
    user: { sub: string };
  }
}

declare module "@fastify/jwt" {
  interface FastifyJWT {
    payload: { sub: string };
    user: { sub: string };
  }
}
