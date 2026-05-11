import { env } from "../config/env.js";

interface LiveKitToken {
  room: string;
  token: string;
  url: string;
}

export async function createRoomAndToken(userId: string, roomName?: string): Promise<LiveKitToken> {
  const room = roomName || `call-${userId}-${Date.now()}`;

  const { AccessToken } = await import("livekit-server-sdk");

  const at = new AccessToken(env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET, {
    identity: userId,
    ttl: "10m",
  });
  at.addGrant({ roomJoin: true, room, canPublish: true, canSubscribe: true });

  const agent = new AccessToken(env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET, {
    identity: "jarvis-agent",
    ttl: "10m",
  });
  agent.addGrant({ roomJoin: true, room, canPublish: true, canSubscribe: true });

  return {
    room,
    token: await at.toJwt(),
    url: env.LIVEKIT_URL,
  };
}
