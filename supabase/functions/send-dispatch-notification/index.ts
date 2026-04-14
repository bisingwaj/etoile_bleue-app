// Supabase Edge Function: send-dispatch-notification
// Triggered via Database Webhook when a dispatch status is updated.
// Sends an FCM notification to the citizen about the status of their rescue team.

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

    const dispatchId = record.id;
    const incidentId = record.incident_id;
    const status = record.status;
    const rescuerName = record.rescuer_name ?? "Équipe Étoile Bleue";

    console.log(
      `[send-dispatch-notification] dispatchId=${dispatchId}, incidentId=${incidentId}, status=${status}`
    );

    if (!incidentId || !status) {
      return new Response(
        JSON.stringify({ ok: false, error: "missing incident_id or status" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // 2. Setup Supabase Client
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // 3. Get Citizen ID from Incident
    const { data: incident, error: incidentError } = await supabase
      .from("incidents")
      .select("citizen_id, reference")
      .eq("id", incidentId)
      .maybeSingle();

    if (incidentError || !incident) {
      console.error("[send-dispatch-notification] Incident fetch error:", incidentError);
      return new Response(
        JSON.stringify({ ok: false, error: "incident_not_found" }),
        { status: 404, headers: { "Content-Type": "application/json" } }
      );
    }

    const citizenId = incident.citizen_id;
    if (!citizenId) {
      return new Response(
        JSON.stringify({ ok: true, skipped: true, reason: "no citizen assigned to incident" }),
        { headers: { "Content-Type": "application/json" } }
      );
    }

    // 4. Get FCM Token
    const { data: user, error: userError } = await supabase
      .from("users_directory")
      .select("fcm_token")
      .eq("auth_user_id", citizenId)
      .maybeSingle();

    if (userError || !user?.fcm_token) {
      console.warn(`[send-dispatch-notification] No FCM token for citizen ${citizenId}`);
      return new Response(
        JSON.stringify({ ok: false, error: "no_fcm_token" }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }

    const fcmToken = user.fcm_token;

    // 5. Title and Message based on status
    let title = "Mise à jour d'intervention";
    let bodyText = "Le statut de votre demande a changé.";

    switch (status) {
      case 'dispatched':
        title = "🚗 Secours assignés";
        bodyText = "Une équipe a été mobilisée pour votre intervention.";
        break;
      case 'en_route':
        title = "🚀 Secours en route";
        bodyText = "L'équipe est en chemin vers votre position.";
        break;
      case 'on_scene':
      case 'arrived':
        title = "📍 Équipe arrivée";
        bodyText = "Les secours sont arrivés sur place.";
        break;
      case 'en_route_hospital':
        title = "🏥 En route vers l'hôpital";
        bodyText = "L'équipe se dirige vers la structure sanitaire.";
        break;
      case 'arrived_hospital':
        title = "🏨 Arrivée à l'hôpital";
        bodyText = "Vous êtes arrivés à l'hôpital.";
        break;
    }

    // 6. Parse Firebase service account
    const serviceAccountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_KEY");
    if (!serviceAccountJson) throw new Error("FIREBASE_SERVICE_ACCOUNT_KEY not set");
    const serviceAccount = JSON.parse(serviceAccountJson);

    // 7. Get Access Token
    const accessToken = await getAccessToken(serviceAccount);

    // 8. Send FCM message
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;
    
    const fcmPayload = {
      message: {
        token: fcmToken,
        notification: {
          title: title,
          body: bodyText,
        },
        data: {
          type: "dispatch_status_update",
          incidentId: incidentId,
          status: status,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          priority: "high",
          notification: {
            channel_id: "sos_calls_channel", // High priority channel
            sound: "default",
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
              "content-available": 1,
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
    console.log("[send-dispatch-notification] FCM response:", JSON.stringify(fcmResult));

    return new Response(
      JSON.stringify({ ok: true, message: fcmResult.name }),
      { headers: { "Content-Type": "application/json" } }
    );

  } catch (err) {
    console.error("[send-dispatch-notification] Error:", err);
    return new Response(
      JSON.stringify({ ok: false, error: String(err) }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
