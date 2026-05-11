import { redis } from "../config/redis.js";
import { google } from "googleapis";

const SCOPES = ["https://www.googleapis.com/auth/firebase.messaging"];

let _accessToken: string | null = null;
let _tokenExpiry = 0;

async function getAccessToken(): Promise<string> {
  if (Date.now() < _tokenExpiry && _accessToken) return _accessToken;

  const clientEmail = process.env.FCM_CLIENT_EMAIL;
  const privateKey = process.env.FCM_PRIVATE_KEY?.replace(/\\n/g, "\n");

  if (!clientEmail || !privateKey) {
    throw new Error("FCM service account credentials not configured");
  }

  const auth = new google.auth.JWT({
    email: clientEmail,
    key: privateKey,
    scopes: SCOPES,
  });
  const tokens = await auth.authorize();
  _accessToken = tokens.access_token!;
  _tokenExpiry = Date.now() + 55 * 60 * 1000;
  return _accessToken;
}

export async function sendPushNotification(
  fcmToken: string,
  title: string,
  body: string,
  data?: Record<string, string>
) {
  const projectId = process.env.FCM_PROJECT_ID;
  if (!projectId) {
    console.warn("FCM_PROJECT_ID not set, skipping push notification");
    return;
  }

  try {
    const token = await getAccessToken();
    const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    const message: any = {
      message: {
        token: fcmToken,
        notification: { title, body },
        data: data || {},
        android: { priority: "high", notification: { sound: "default" } },
        apns: {
          payload: {
            aps: {
              sound: "default",
              "content-available": 1,
            },
          },
        },
        webpush: { headers: { Urgency: "high" } },
      },
    };

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(message),
    });

    if (!response.ok) {
      const text = await response.text();
      console.error(`FCM v1 error: ${response.status} ${text}`);
    }
  } catch (err) {
    console.error("FCM send error:", err);
  }
}

export async function storeFcmToken(userId: string, token: string) {
  await redis.set(`fcm:${userId}`, token);
}

export async function getFcmToken(userId: string): Promise<string | null> {
  return redis.get(`fcm:${userId}`);
}
