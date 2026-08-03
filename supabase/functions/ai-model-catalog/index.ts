// Returns a cached, provider-authoritative model catalog without exposing a
// user's bring-your-own API key. The catalog refreshes at most every six hours
// on ordinary reads; ?refresh=true lets the picker ask for a manual refresh.
// Set OPENAI_API_KEY and/or ANTHROPIC_API_KEY as Edge Function secrets.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Provider = "openAI" | "anthropic";

type CatalogModel = {
  id: string;
  provider: Provider;
  displayName: string;
  description: string;
};

const supabaseURL = Deno.env.get("SUPABASE_URL");
const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const catalogRefreshIntervalMs = 6 * 60 * 60 * 1000;
const manualRefreshCooldownMs = 60 * 1000;

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "private, max-age=3600",
    },
  });
}

function displayName(id: string): string {
  return id
    .replace(/^gpt-/i, "GPT-")
    .replace(/^claude-/i, "Claude ")
    .replace(/-/g, " ");
}

type StoredCatalog = {
  id: "default";
  models: CatalogModel[];
  updated_at: string;
};

function ageInMilliseconds(catalog: StoredCatalog): number {
  return Date.now() - new Date(catalog.updated_at).getTime();
}

async function openAIModels(key: string): Promise<CatalogModel[]> {
  const response = await fetch("https://api.openai.com/v1/models", {
    headers: { Authorization: `Bearer ${key}` },
  });
  if (!response.ok) throw new Error(`OpenAI models request failed: ${response.status}`);

  const body = await response.json() as { data?: Array<{ id?: string }> };
  return (body.data ?? [])
    .flatMap(({ id }) => id && /^gpt-/i.test(id) ? [id] : [])
    .map((id) => ({
      id,
      provider: "openAI" as const,
      displayName: displayName(id),
      description: "OpenAI",
    }));
}

async function anthropicModels(key: string): Promise<CatalogModel[]> {
  const response = await fetch("https://api.anthropic.com/v1/models?limit=100", {
    headers: {
      "x-api-key": key,
      "anthropic-version": "2023-06-01",
    },
  });
  if (!response.ok) throw new Error(`Anthropic models request failed: ${response.status}`);

  const body = await response.json() as {
    data?: Array<{ id?: string; display_name?: string }>;
  };
  return (body.data ?? [])
    .flatMap(({ id, display_name }) => id ? [{ id, display_name }] : [])
    .map(({ id, display_name }) => ({
      id,
      provider: "anthropic" as const,
      displayName: display_name ?? displayName(id),
      description: "Anthropic",
    }));
}

Deno.serve(async (req) => {
  if (req.method !== "GET") return json({ error: "method_not_allowed" }, 405);
  if (!supabaseURL || !serviceRole) return json({ error: "server_misconfigured" }, 500);

  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "authentication_required" }, 401);

  const supabase = createClient(supabaseURL, serviceRole);
  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data.user) return json({ error: "authentication_required" }, 401);

  const { data: cachedData, error: cacheReadError } = await supabase
    .from("ai_model_catalog")
    .select("id,models,updated_at")
    .eq("id", "default")
    .maybeSingle();
  if (cacheReadError) {
    console.error("Unable to read model catalog cache", cacheReadError);
    return json({ error: "catalog_unavailable" }, 503);
  }
  const cached = cachedData as StoredCatalog | null;
  const manualRefresh = new URL(req.url).searchParams.get("refresh") === "true";
  const age = cached ? ageInMilliseconds(cached) : Number.POSITIVE_INFINITY;
  const withinAutomaticCacheWindow = age < catalogRefreshIntervalMs;
  const withinManualCooldown = age < manualRefreshCooldownMs;
  if (cached && (!manualRefresh ? withinAutomaticCacheWindow : withinManualCooldown)) {
    return json({ models: cached.models, updated_at: cached.updated_at, source: "cache" });
  }

  const requests: Promise<CatalogModel[]>[] = [];
  const openAIKey = Deno.env.get("OPENAI_API_KEY");
  const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (openAIKey) requests.push(openAIModels(openAIKey));
  if (anthropicKey) requests.push(anthropicModels(anthropicKey));
  if (requests.length === 0) {
    return cached
      ? json({ models: cached.models, updated_at: cached.updated_at, source: "stale_cache" })
      : json({ error: "catalog_not_configured" }, 503);
  }

  const settled = await Promise.allSettled(requests);
  const models = settled.flatMap((result) => {
    if (result.status === "fulfilled") return result.value;
    console.error("Model catalog provider refresh failed", result.reason);
    return [];
  });
  if (models.length === 0) {
    return cached
      ? json({ models: cached.models, updated_at: cached.updated_at, source: "stale_cache" })
      : json({ error: "catalog_unavailable" }, 503);
  }

  const updatedAt = new Date().toISOString();
  const { error: cacheWriteError } = await supabase
    .from("ai_model_catalog")
    .upsert({ id: "default", models, updated_at: updatedAt });
  if (cacheWriteError) {
    console.error("Unable to write model catalog cache", cacheWriteError);
  }

  return json({ models, updated_at: updatedAt, source: "provider" });
});
