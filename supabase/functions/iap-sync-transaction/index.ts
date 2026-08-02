// Verifies a StoreKit 2 signed transaction against Apple's certificate chain,
// binds it to the authenticated Supabase user, and records the server-confirmed
// entitlement used by database-backed extraction creation.
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
  verifySubscriptionTransaction,
} from "../_shared/apple_store_verification.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);

interface SyncRequest {
  signedTransactionInfo?: string;
}

class AuthenticationError extends Error {}

function json(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function authenticatedUserID(req: Request): Promise<string> {
  const authorization = req.headers.get("Authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "");
  if (!token) throw new AuthenticationError("Authentication required");

  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data.user) {
    throw new AuthenticationError("Invalid authenticated user");
  }
  return data.user.id.toLowerCase();
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
    p_verification_source: "device",
  });
  if (error) throw error;
}

serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  try {
    const userID = await authenticatedUserID(req);
    const body = await req.json() as SyncRequest;
    if (typeof body.signedTransactionInfo !== "string") {
      return json({ error: "signed_transaction_required" }, 400);
    }

    const transaction = await verifySubscriptionTransaction(
      body.signedTransactionInfo,
      userID,
    );
    await recordVerifiedEntitlement(transaction);

    const { data: storedEntitlement, error: readError } = await supabase
      .from("iap_entitlements")
      .select(
        "status,expires_at,revoked_at,verified_at,product_id,bundle_id,environment",
      )
      .eq("user_id", userID)
      .single();
    if (readError) throw readError;

    const active = storedEntitlement.status === "active" &&
      storedEntitlement.product_id === transaction.productID &&
      storedEntitlement.bundle_id === transaction.bundleID &&
      (storedEntitlement.environment === "Production" ||
        storedEntitlement.environment === "Sandbox") &&
      storedEntitlement.verified_at != null &&
      storedEntitlement.revoked_at == null &&
      new Date(storedEntitlement.expires_at).getTime() > Date.now();
    return json({
      verified: true,
      active,
      status: storedEntitlement.status,
      environment: storedEntitlement.environment,
    }, 200);
  } catch (error) {
    if (error instanceof AuthenticationError) {
      return json({ error: "authentication_required" }, 401);
    }
    if (error instanceof SyntaxError) {
      return json({ error: "invalid_request" }, 400);
    }
    if (error instanceof AppleVerificationConfigurationError) {
      console.error("Apple verification configuration error", error);
      return json({ error: "verification_unavailable" }, 503);
    }
    if (error instanceof ApplePayloadValidationError) {
      return json({ error: "invalid_transaction" }, 422);
    }
    if (error instanceof VerificationException) {
      if (error.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE) {
        console.error(
          "Retryable Apple transaction verification failure",
          error,
        );
        return json({ error: "verification_unavailable" }, 503);
      }
      return json({ error: "invalid_transaction" }, 422);
    }

    console.error("Unable to record verified transaction", error);
    return json({ error: "internal_error" }, 500);
  }
});
