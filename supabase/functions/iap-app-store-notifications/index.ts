// Verifies App Store Server Notifications V2 and their nested transaction JWS
// before updating the entitlement used by database-backed extraction creation.
//
// Required Edge Function secrets:
//   SUPABASE_SERVICE_ROLE_KEY
//   SUPABASE_URL
//   APPLE_APP_ID (numeric App Store app ID; required for Production payloads)

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  VerificationException,
  VerificationStatus,
} from "npm:@apple/app-store-server-library@3.1.0";
import {
  ApplePayloadValidationError,
  AppleVerificationConfigurationError,
  type VerifiedSubscriptionTransaction,
  verifySubscriptionNotification,
} from "../_shared/apple_store_verification.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);

interface NotificationRequest {
  signedPayload?: string;
}

function json(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function recordVerifiedEntitlement(
  transaction: VerifiedSubscriptionTransaction,
): Promise<void> {
  const { error } = await supabase.rpc("record_verified_iap_entitlement", {
    p_user_id: transaction.userID,
    p_product_id: transaction.productID,
    p_bundle_id: transaction.bundleID,
    p_original_transaction_id: transaction.originalTransactionID,
    p_transaction_id: transaction.transactionID,
    p_status: transaction.status,
    p_expires_at: transaction.expiresAt,
    p_revoked_at: transaction.revokedAt,
    p_environment: transaction.environment,
    p_signed_at: transaction.signedAt,
    p_verification_source: "notification",
  });
  if (error) throw error;
}

serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  try {
    const body = await req.json() as NotificationRequest;
    if (typeof body.signedPayload !== "string") {
      return json({ error: "signed_payload_required" }, 400);
    }

    const { transaction } = await verifySubscriptionNotification(
      body.signedPayload,
    );
    await recordVerifiedEntitlement(transaction);
    return json({ accepted: true }, 200);
  } catch (error) {
    if (error instanceof SyntaxError) {
      return json({ error: "invalid_request" }, 400);
    }
    if (error instanceof AppleVerificationConfigurationError) {
      console.error("Apple verification configuration error", error);
      return json({ error: "verification_unavailable" }, 503);
    }
    if (error instanceof ApplePayloadValidationError) {
      return json({ error: "invalid_notification" }, 422);
    }
    if (error instanceof VerificationException) {
      if (error.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE) {
        console.error(
          "Retryable Apple notification verification failure",
          error,
        );
        return json({ error: "verification_unavailable" }, 503);
      }
      return json({ error: "invalid_notification" }, 422);
    }

    console.error("Unable to record verified App Store notification", error);
    return json({ error: "internal_error" }, 500);
  }
});
