// Supabase Edge Function: send-call-notification
// Triggered via Database Webhook when a new call_history row is inserted with status='ringing'
// Sends an FCM data-only push notification to wake the patient's phone and show CallKit UI.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ─── JWT signing for Google OAuth2 (FCM v1 API) ────────────────────────────────

async function importPrivateKey(pemKey: string): Promise<CryptoKey> {
  const pemBody = pemKey
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\n/g, "");
  const binaryDer = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    binaryDer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );
}

function base64url(data: Uint8Array | string): string {
  const str =
    typeof data === "string"
      ? btoa(data)
      : btoa(String.fromCharCode(...data));
  return str.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function createSignedJwt(
  serviceAccount: {
    client_email: string;
    private_key: string;
    token_uri: string;
  }
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: serviceAccount.client_email,
    sub: serviceAccount.client_email,
    aud: serviceAccount.token_uri,
    iat: now,
    exp: now + 3600,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  };

  const encodedHeader = base64url(JSON.stringify(header));
  const encodedPayload = base64url(JSON.stringify(payload));
  const signingInput = `${encodedHeader}.${encodedPayload}`;

  const key = await importPrivateKey(serviceAccount.private_key);
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signingInput)
  );

  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

async function getAccessToken(serviceAccount: {
  client_email: string;
  private_key: string;
  token_uri: string;
}): Promise<string> {
  const jwt = await createSignedJwt(serviceAccount);
  const res = await fetch(serviceAccount.token_uri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const data = await res.json();
  if (!data.access_token) {
    throw new Error(`OAuth2 token exchange failed: ${JSON.stringify(data)}`);
  }
  return data.access_token;
}

// ─── Main handler ───────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  try {
    // 1. Parse the webhook payload
    const body = await req.json();
    const record = body.record ?? body;

    const callId = record.id;
    const citizenId = record.citizen_id;
    const channelName = record.channel_name;
    const callerName = record.caller_name ?? "Centre d'appels Étoile Bleue";
    const status = record.status;
    const hasVideo = record.has_video === true;

    console.log(
      `[send-call-notification] callId=${callId}, citizen=${citizenId}, status=${status}, channel=${channelName}`
    );

    // Only process ringing calls
    if (status !== "ringing") {
      return new Response(
        JSON.stringify({ ok: true, skipped: true, reason: "status != ringing" }),
        { headers: { "Content-Type": "application/json" } }
      );
    }

    // Ignore patient-initiated calls (SOS, CALLBACK) — they don't need push
    if (
      channelName &&
      (channelName.startsWith("SOS-") || channelName.startsWith("CALLBACK-"))
    ) {
      return new Response(
        JSON.stringify({ ok: true, skipped: true, reason: "outgoing call" }),
        { headers: { "Content-Type": "application/json" } }
      );
    }

    if (!citizenId) {
      return new Response(
        JSON.stringify({ ok: false, error: "missing citizen_id" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // 2. Look up the citizen's FCM token from Supabase
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const { data: user, error: userError } = await supabase
      .from("users_directory")
      .select("fcm_token, first_name, last_name")
      .eq("auth_user_id", citizenId)
      .maybeSingle();

    if (userError) {
      console.error("[send-call-notification] DB error:", userError);
      return new Response(
        JSON.stringify({ ok: false, error: userError.message }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    const fcmToken = user?.fcm_token;
    if (!fcmToken) {
      console.warn(
        `[send-call-notification] No FCM token for citizen ${citizenId}`
      );
      return new Response(
        JSON.stringify({ ok: false, error: "no_fcm_token" }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }

    // 3. Parse the Firebase service account from environment
    const serviceAccountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_KEY");
    if (!serviceAccountJson) {
      throw new Error("FIREBASE_SERVICE_ACCOUNT_KEY secret not set");
    }
    const serviceAccount = JSON.parse(serviceAccountJson);

    // 4. Get OAuth2 access token for FCM v1 API
    const accessToken = await getAccessToken(serviceAccount);

    // 5. Send FCM data-only message (data messages wake the app even when killed)
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;

    const fcmPayload = {
      message: {
        token: fcmToken,
        // DATA-ONLY message: no "notification" key so Android delivers to
        // _handleBackgroundMessage even when the app is killed.
        data: {
          type: "incoming_call",
          callId: callId,
          channelName: channelName ?? "",
          callerName: callerName,
          hasVideo: hasVideo ? "true" : "false",
        },
        android: {
          priority: "high",
          ttl: "60s",
        },
        apns: {
          headers: {
            "apns-priority": "10",
            "apns-push-type": "voip",
          },
          payload: {
            aps: {
              "content-available": 1,
              sound: "default",
            },
          },
        },
      },
    };

    const fcmRes = await fetch(fcmUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(fcmPayload),
    });

    const fcmResult = await fcmRes.json();
    console.log("[send-call-notification] FCM response:", JSON.stringify(fcmResult));

    if (!fcmRes.ok) {
      return new Response(
        JSON.stringify({ ok: false, fcm_error: fcmResult }),
        { status: 502, headers: { "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ ok: true, message_name: fcmResult.name }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("[send-call-notification] Error:", err);
    return new Response(
      JSON.stringify({ ok: false, error: String(err) }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
