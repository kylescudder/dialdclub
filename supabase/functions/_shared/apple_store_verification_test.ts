import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1";
import {
  ApplePayloadValidationError,
  validateSubscriptionTransaction,
  verifySubscriptionNotification,
  verifySubscriptionTransaction,
} from "./apple_store_verification.ts";

const USER_ID = "11111111-1111-4111-8111-111111111111";

function validTransaction(overrides: Record<string, unknown> = {}) {
  return {
    appAccountToken: USER_ID,
    bundleId: "club.diald",
    environment: "Sandbox",
    expiresDate: Date.now() + 86_400_000,
    originalTransactionId: "original-transaction",
    productId: "club.diald.supporter.monthly",
    signedDate: Date.now(),
    transactionId: "transaction",
    ...overrides,
  };
}

function unsignedJWS(payload: Record<string, unknown>): string {
  const encode = (value: Record<string, unknown>) =>
    btoa(JSON.stringify(value))
      .replace(/=/g, "")
      .replace(/\+/g, "-")
      .replace(/\//g, "_");
  return `${encode({ alg: "none" })}.${encode(payload)}.forged`;
}

Deno.test("validates the expected product, bundle, environment, and account token", () => {
  const transaction = validateSubscriptionTransaction(
    validTransaction(),
    USER_ID,
  );
  assertEquals(transaction.userID, USER_ID);
  assertEquals(transaction.status, "active");
  assertEquals(transaction.environment, "Sandbox");
});

Deno.test("requires an appAccountToken", () => {
  assertThrows(
    () =>
      validateSubscriptionTransaction(
        validTransaction({ appAccountToken: undefined }),
      ),
    ApplePayloadValidationError,
  );
});

Deno.test("rejects product, bundle, environment, and account mismatches", () => {
  for (
    const overrides of [
      { productId: "fabricated.product" },
      { bundleId: "fabricated.bundle" },
      { environment: "Xcode" },
    ]
  ) {
    assertThrows(
      () =>
        validateSubscriptionTransaction(validTransaction(overrides), USER_ID),
      ApplePayloadValidationError,
    );
  }

  assertThrows(
    () =>
      validateSubscriptionTransaction(
        validTransaction(),
        "22222222-2222-4222-8222-222222222222",
      ),
    ApplePayloadValidationError,
  );
});

Deno.test("rejects a forged signed transaction", async () => {
  await assertRejects(
    () =>
      verifySubscriptionTransaction(unsignedJWS(validTransaction()), USER_ID),
  );
});

Deno.test("rejects a forged server notification", async () => {
  const signedTransactionInfo = unsignedJWS(validTransaction());
  await assertRejects(
    () =>
      verifySubscriptionNotification(unsignedJWS({
        notificationType: "DID_RENEW",
        data: {
          bundleId: "club.diald",
          environment: "Sandbox",
          signedTransactionInfo,
        },
      })),
  );
});
