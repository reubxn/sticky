import { v } from "convex/values";

import type { Doc } from "./_generated/dataModel";
import { internalMutation } from "./_generated/server";
import type { MutationCtx } from "./_generated/server";
import {
  workerRequestCompletionValidator,
  workerRequestScopeValidator,
  workerRequestTicketCompletionResultValidator,
  workerRequestTicketConsumeResultValidator,
} from "./validators";
import { buildOnboardingSystemPrompt } from "./personaOnboardingContext";
import { validatePersonaSetupGraph } from "./personaFoundation";
import {
  assertBodyPolicy,
  assertDigest,
  consumedTicketMinimumRetentionMs,
  failWorkerRequest,
  onboardingChatStaticSystemPolicy,
  sanitizedAuditRetentionMs,
  scopePolicies,
  trustedPolicyEnvelope,
  workerRequestDailyQuotaWindowMs,
  workerRequestPolicyVersion,
} from "./workerRequestPolicy";
import type { WorkerRequestScope } from "./workerRequestPolicy";

async function requireIssuingGraph(
  ctx: MutationCtx,
  tokenIdentifier: string,
  personaId: Doc<"personas">["_id"],
) {
  if (tokenIdentifier.length < 1 || tokenIdentifier.length > 512) {
    return failWorkerRequest("RESOURCE_UNAVAILABLE", "Resource unavailable");
  }
  const profiles = await ctx.db
    .query("profiles")
    .withIndex("by_tokenIdentifier", (indexQuery) =>
      indexQuery.eq("tokenIdentifier", tokenIdentifier),
    )
    .take(2);
  if (profiles.length !== 1 || profiles[0].lifecycleStatus !== "active") {
    return failWorkerRequest("RESOURCE_UNAVAILABLE", "Resource unavailable");
  }
  const profile = profiles[0];
  const persona = await ctx.db.get("personas", personaId);
  if (
    persona === null ||
    persona.status !== "active" ||
    persona.ownerUserId !== profile._id
  ) {
    return failWorkerRequest("RESOURCE_UNAVAILABLE", "Resource unavailable");
  }
  const membership = await ctx.db.get(
    "workspaceMembers",
    persona.membershipId,
  );
  if (
    membership === null ||
    membership.status !== "active" ||
    membership.workspaceId !== persona.workspaceId ||
    membership.userId !== profile._id
  ) {
    return failWorkerRequest("RESOURCE_UNAVAILABLE", "Resource unavailable");
  }
  const workspace = await ctx.db.get("workspaces", persona.workspaceId);
  if (
    workspace === null ||
    workspace.lifecycleStatus !== "active"
  ) {
    return failWorkerRequest("RESOURCE_UNAVAILABLE", "Resource unavailable");
  }
  try {
    await validatePersonaSetupGraph(ctx, persona);
  } catch {
    return failWorkerRequest("RESOURCE_UNAVAILABLE", "Resource unavailable");
  }
  if (persona.setupState === "complete") {
    return failWorkerRequest(
      "SETUP_COMPLETE",
      "Onboarding request scopes require incomplete setup",
    );
  }

  return { profile, workspace, membership, persona };
}

async function requireCurrentTicketGraph(
  ctx: MutationCtx,
  ticket: Doc<"workerRequestTickets">,
) {
  const profile = await ctx.db.get("profiles", ticket.actorProfileId);
  const workspace = await ctx.db.get("workspaces", ticket.workspaceId);
  const membership = await ctx.db.get(
    "workspaceMembers",
    ticket.membershipId,
  );
  const persona = await ctx.db.get("personas", ticket.personaId);

  if (
    profile === null ||
    profile.lifecycleStatus !== "active" ||
    workspace === null ||
    workspace.lifecycleStatus !== "active" ||
    membership === null ||
    membership.status !== "active" ||
    membership.workspaceId !== workspace._id ||
    membership.userId !== profile._id ||
    persona === null ||
    persona.status !== "active" ||
    persona.workspaceId !== workspace._id ||
    persona.membershipId !== membership._id ||
    persona.ownerUserId !== profile._id
  ) {
    return failWorkerRequest("TICKET_INVALID", "Ticket is invalid");
  }
  if (persona.setupState === "complete") {
    return failWorkerRequest("TICKET_INVALID", "Ticket is invalid");
  }
  try {
    await validatePersonaSetupGraph(ctx, persona);
  } catch {
    return failWorkerRequest("TICKET_INVALID", "Ticket is invalid");
  }
  return { persona };
}

function auditMatchesTicket(
  audit: Doc<"workerRequestAudits">,
  ticket: Doc<"workerRequestTickets">,
): boolean {
  return (
    audit.ticketId === ticket._id &&
    audit.actorProfileId === ticket.actorProfileId &&
    audit.workspaceId === ticket.workspaceId &&
    audit.membershipId === ticket.membershipId &&
    audit.personaId === ticket.personaId &&
    audit.scope === ticket.scope &&
    audit.policyVersion === ticket.policyVersion &&
    audit.issuedAt === ticket.issuedAt
  );
}

async function enforceIssueLimits(
  ctx: MutationCtx,
  actorProfileId: Doc<"profiles">["_id"],
  scope: WorkerRequestScope,
  requestBodyByteCount: number,
  issuedAt: number,
) {
  const policy = scopePolicies[scope];
  const outstanding = await ctx.db
    .query("workerRequestTickets")
    .withIndex(
      "by_actorProfileId_and_scope_and_status_and_expiresAt",
      (indexQuery) =>
        indexQuery
          .eq("actorProfileId", actorProfileId)
          .eq("scope", scope)
          .eq("status", "issued")
          .gt("expiresAt", issuedAt),
    )
    .take(policy.outstandingLimit);
  if (outstanding.length >= policy.outstandingLimit) {
    return failWorkerRequest(
      "OUTSTANDING_LIMIT",
      "Too many outstanding request tickets",
    );
  }

  const shortWindowTickets = await ctx.db
    .query("workerRequestTickets")
    .withIndex(
      "by_actorProfileId_and_scope_and_issuedAt",
      (indexQuery) =>
        indexQuery
          .eq("actorProfileId", actorProfileId)
          .eq("scope", scope)
          .gte("issuedAt", issuedAt - policy.shortWindowMs),
    )
    .take(policy.shortWindowLimit);
  if (shortWindowTickets.length >= policy.shortWindowLimit) {
    return failWorkerRequest("RATE_LIMITED", "Request ticket rate exceeded");
  }

  const dailyTickets = await ctx.db
    .query("workerRequestTickets")
    .withIndex(
      "by_actorProfileId_and_scope_and_issuedAt",
      (indexQuery) =>
        indexQuery
          .eq("actorProfileId", actorProfileId)
          .eq("scope", scope)
          .gte("issuedAt", issuedAt - workerRequestDailyQuotaWindowMs),
    )
    .take(policy.dailyRequestLimit);
  const dailyBodyByteCount = dailyTickets.reduce(
    (total, ticket) => total + ticket.requestBodyByteCount,
    0,
  );
  if (
    dailyTickets.length >= policy.dailyRequestLimit ||
    dailyBodyByteCount + requestBodyByteCount > policy.dailyBodyByteLimit
  ) {
    return failWorkerRequest("RATE_LIMITED", "Daily ticket quota exceeded");
  }
}

export const issue = internalMutation({
  args: {
    tokenIdentifier: v.string(),
    personaId: v.id("personas"),
    scope: workerRequestScopeValidator,
    requestBodyDigest: v.string(),
    requestBodyByteCount: v.number(),
    ticketDigest: v.string(),
  },
  returns: v.object({
    scope: workerRequestScopeValidator,
    expiresAt: v.number(),
    policyVersion: v.number(),
  }),
  handler: async (ctx, args) => {
    assertBodyPolicy(
      args.scope,
      args.requestBodyDigest,
      args.requestBodyByteCount,
    );
    assertDigest(args.ticketDigest);
    const existingTicket = await ctx.db
      .query("workerRequestTickets")
      .withIndex("by_ticketDigest", (indexQuery) =>
        indexQuery.eq("ticketDigest", args.ticketDigest),
      )
      .unique();
    if (existingTicket !== null) {
      return failWorkerRequest("DATA_INTEGRITY", "Ticket digest collision");
    }

    const graph = await requireIssuingGraph(
      ctx,
      args.tokenIdentifier,
      args.personaId,
    );
    const issuedAt = Date.now();
    await enforceIssueLimits(
      ctx,
      graph.profile._id,
      args.scope,
      args.requestBodyByteCount,
      issuedAt,
    );
    const expiresAt = issuedAt + scopePolicies[args.scope].ticketTtlMs;
    const ticketId = await ctx.db.insert("workerRequestTickets", {
      ticketDigest: args.ticketDigest,
      scope: args.scope,
      requestBodyDigest: args.requestBodyDigest,
      requestBodyByteCount: args.requestBodyByteCount,
      actorProfileId: graph.profile._id,
      workspaceId: graph.workspace._id,
      membershipId: graph.membership._id,
      personaId: graph.persona._id,
      policyVersion: workerRequestPolicyVersion,
      issuedAt,
      expiresAt,
      status: "issued",
    });
    await ctx.db.insert("workerRequestAudits", {
      ticketId,
      scope: args.scope,
      actorProfileId: graph.profile._id,
      workspaceId: graph.workspace._id,
      membershipId: graph.membership._id,
      personaId: graph.persona._id,
      policyVersion: workerRequestPolicyVersion,
      status: "issued",
      issuedAt,
      retentionExpiresAt: issuedAt + sanitizedAuditRetentionMs,
    });

    return {
      scope: args.scope,
      expiresAt,
      policyVersion: workerRequestPolicyVersion,
    };
  },
});

export const consume = internalMutation({
  args: {
    ticketDigest: v.string(),
    expectedScope: workerRequestScopeValidator,
    expectedRequestBodyDigest: v.string(),
    expectedRequestBodyByteCount: v.number(),
    workerRequestId: v.string(),
  },
  returns: workerRequestTicketConsumeResultValidator,
  handler: async (ctx, args) => {
    assertDigest(args.ticketDigest);
    assertBodyPolicy(
      args.expectedScope,
      args.expectedRequestBodyDigest,
      args.expectedRequestBodyByteCount,
    );
    if (!/^[A-Za-z0-9_-]{16,128}$/.test(args.workerRequestId)) {
      return failWorkerRequest(
        "INVALID_REQUEST",
        "Worker request ID is invalid",
      );
    }
    const ticket = await ctx.db
      .query("workerRequestTickets")
      .withIndex("by_ticketDigest", (indexQuery) =>
        indexQuery.eq("ticketDigest", args.ticketDigest),
      )
      .unique();
    const now = Date.now();
    if (
      ticket === null ||
      ticket.status !== "issued" ||
      ticket.expiresAt <= now ||
      ticket.scope !== args.expectedScope ||
      ticket.requestBodyDigest !== args.expectedRequestBodyDigest ||
      ticket.requestBodyByteCount !== args.expectedRequestBodyByteCount ||
      ticket.policyVersion !== workerRequestPolicyVersion
    ) {
      return failWorkerRequest("TICKET_INVALID", "Ticket is invalid");
    }

    const graph = await requireCurrentTicketGraph(ctx, ticket);
    const onboardingChatSystemPrompt =
      ticket.scope === "onboarding_chat"
        ? await buildOnboardingSystemPrompt(
            ctx,
            graph.persona,
            onboardingChatStaticSystemPolicy,
          )
        : undefined;
    const audits = await ctx.db
      .query("workerRequestAudits")
      .withIndex("by_ticketId", (indexQuery) =>
        indexQuery.eq("ticketId", ticket._id),
      )
      .take(2);
    if (
      audits.length !== 1 ||
      audits[0].status !== "issued" ||
      !auditMatchesTicket(audits[0], ticket)
    ) {
      return failWorkerRequest(
        "DATA_INTEGRITY",
        "Ticket audit relationship is invalid",
      );
    }

    const consumptionId = ticket._id;
    await ctx.db.patch("workerRequestTickets", ticket._id, {
      status: "consumed",
      consumedAt: now,
      consumptionId,
      workerRequestId: args.workerRequestId,
      purgeEligibleAt: now + consumedTicketMinimumRetentionMs,
    });
    await ctx.db.patch("workerRequestAudits", audits[0]._id, {
      status: "consumed",
      consumedAt: now,
      workerRequestId: args.workerRequestId,
    });

    return {
      consumptionId,
      policyVersion: workerRequestPolicyVersion,
      policy: trustedPolicyEnvelope(
        ticket,
        graph.persona,
        onboardingChatSystemPrompt,
      ),
    };
  },
});

function assertCompletion(
  completion: {
    outcome: "succeeded" | "provider_error" | "client_disconnected";
    providerRequestId?: string;
    httpStatusClass?: number;
    latencyMs: number;
    usage: {
      inputUnits?: number;
      outputUnits?: number;
    };
    errorCode?: string;
  },
): void {
  if (
    !Number.isSafeInteger(completion.latencyMs) ||
    completion.latencyMs < 0 ||
    completion.latencyMs > 3_600_000
  ) {
    return failWorkerRequest("INVALID_REQUEST", "Latency is invalid");
  }
  if (
    completion.providerRequestId !== undefined &&
    !/^[A-Za-z0-9._:-]{1,128}$/.test(completion.providerRequestId)
  ) {
    return failWorkerRequest(
      "INVALID_REQUEST",
      "Provider request ID is invalid",
    );
  }
  if (
    completion.httpStatusClass !== undefined &&
    ![2, 4, 5].includes(completion.httpStatusClass)
  ) {
    return failWorkerRequest("INVALID_REQUEST", "HTTP status class is invalid");
  }
  if (
    completion.errorCode !== undefined &&
    !/^[A-Z0-9_]{1,64}$/.test(completion.errorCode)
  ) {
    return failWorkerRequest("INVALID_REQUEST", "Error code is invalid");
  }
  for (const unitCount of [
    completion.usage.inputUnits,
    completion.usage.outputUnits,
  ]) {
    if (
      unitCount !== undefined &&
      (!Number.isSafeInteger(unitCount) ||
        unitCount < 0 ||
        unitCount > 10_000_000)
    ) {
      return failWorkerRequest("INVALID_REQUEST", "Usage is invalid");
    }
  }
}

function completionsEqual(
  existing: Doc<"workerRequestAudits">["completion"],
  requested: NonNullable<Doc<"workerRequestAudits">["completion"]>,
): boolean {
  return (
    existing?.outcome === requested.outcome &&
    existing.providerRequestId === requested.providerRequestId &&
    existing.httpStatusClass === requested.httpStatusClass &&
    existing.latencyMs === requested.latencyMs &&
    existing.usage.inputUnits === requested.usage.inputUnits &&
    existing.usage.outputUnits === requested.usage.outputUnits &&
    existing.errorCode === requested.errorCode
  );
}

export const complete = internalMutation({
  args: {
    consumptionId: v.string(),
    workerRequestId: v.string(),
    completion: workerRequestCompletionValidator,
  },
  returns: workerRequestTicketCompletionResultValidator,
  handler: async (ctx, args) => {
    if (!/^[A-Za-z0-9_-]{16,128}$/.test(args.workerRequestId)) {
      return failWorkerRequest(
        "INVALID_REQUEST",
        "Worker request ID is invalid",
      );
    }
    assertCompletion(args.completion);
    const ticketId = ctx.db.normalizeId(
      "workerRequestTickets",
      args.consumptionId,
    );
    const ticket =
      ticketId === null
        ? null
        : await ctx.db.get("workerRequestTickets", ticketId);
    if (
      ticket === null ||
      ticket.status !== "consumed" ||
      ticket.consumptionId !== args.consumptionId ||
      ticket.workerRequestId !== args.workerRequestId
    ) {
      return failWorkerRequest("TICKET_INVALID", "Ticket is invalid");
    }
    const audits = await ctx.db
      .query("workerRequestAudits")
      .withIndex("by_ticketId", (indexQuery) =>
        indexQuery.eq("ticketId", ticket._id),
      )
      .take(2);
    if (audits.length !== 1) {
      return failWorkerRequest(
        "DATA_INTEGRITY",
        "Ticket audit relationship is invalid",
      );
    }
    const audit = audits[0];
    if (!auditMatchesTicket(audit, ticket)) {
      return failWorkerRequest(
        "DATA_INTEGRITY",
        "Ticket audit relationship is invalid",
      );
    }
    if (audit.status === "completed") {
      if (!completionsEqual(audit.completion, args.completion)) {
        return failWorkerRequest(
          "COMPLETION_CONFLICT",
          "Completion conflicts with the recorded outcome",
        );
      }
      return { didComplete: false };
    }
    if (
      audit.status !== "consumed" ||
      audit.workerRequestId !== args.workerRequestId
    ) {
      return failWorkerRequest(
        "DATA_INTEGRITY",
        "Ticket audit relationship is invalid",
      );
    }

    await ctx.db.patch("workerRequestAudits", audit._id, {
      status: "completed",
      completedAt: Date.now(),
      completion: args.completion,
    });
    return { didComplete: true };
  },
});
