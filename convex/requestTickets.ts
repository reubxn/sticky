import { v } from "convex/values";

import { internal } from "./_generated/api";
import { action } from "./_generated/server";
import {
  workerRequestScopeValidator,
  workerRequestTicketIssueResultValidator,
} from "./validators";
import {
  assertBodyPolicy,
  failWorkerRequest,
} from "./workerRequestPolicy";

function bytesToBase64Url(bytes: Uint8Array): string {
  const binary = String.fromCharCode(...bytes);
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export const issueOnboarding = action({
  args: {
    personaId: v.id("personas"),
    scope: workerRequestScopeValidator,
    requestBodyDigest: v.string(),
    requestBodyByteCount: v.number(),
  },
  returns: workerRequestTicketIssueResultValidator,
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (identity === null) {
      return failWorkerRequest(
        "UNAUTHENTICATED",
        "Authentication required",
      );
    }
    assertBodyPolicy(
      args.scope,
      args.requestBodyDigest,
      args.requestBodyByteCount,
    );

    const tokenBytes = new Uint8Array(32);
    crypto.getRandomValues(tokenBytes);
    const token = bytesToBase64Url(tokenBytes);
    const ticketDigest = await sha256Hex(token);
    const issued: {
      scope: typeof args.scope;
      expiresAt: number;
      policyVersion: number;
    } = await ctx.runMutation(
      internal.workerRequestTicketMutations.issue,
      {
        tokenIdentifier: identity.tokenIdentifier,
        personaId: args.personaId,
        scope: args.scope,
        requestBodyDigest: args.requestBodyDigest,
        requestBodyByteCount: args.requestBodyByteCount,
        ticketDigest,
      },
    );

    return {
      token,
      scope: issued.scope,
      expiresAt: issued.expiresAt,
      policyVersion: issued.policyVersion,
    };
  },
});
