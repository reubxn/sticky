/// <reference types="vite/client" />

import { convexTest } from "convex-test";
import type { TestConvexForDataModelAndIdentity } from "convex-test";
import { ConvexError } from "convex/values";
import { describe, expect, test } from "vitest";

import { api, internal } from "./_generated/api";
import type { DataModel, Id } from "./_generated/dataModel";
import schema from "./schema";
import { emptyRequestBodyDigest } from "./workerRequestPolicy";

const modules = import.meta.glob("./**/*.ts");
type TestBackend = TestConvexForDataModelAndIdentity<DataModel>;

const personaOwnerIdentity = {
  subject: "persona-owner",
  issuer: "https://issuer.example",
  tokenIdentifier: "https://issuer.example|persona-owner",
};
const workspaceOwnerIdentity = {
  subject: "workspace-owner",
  issuer: "https://issuer.example",
  tokenIdentifier: "https://issuer.example|workspace-owner",
};
const adminIdentity = {
  subject: "admin",
  issuer: "https://issuer.example",
  tokenIdentifier: "https://issuer.example|admin",
};
const memberIdentity = {
  subject: "member",
  issuer: "https://issuer.example",
  tokenIdentifier: "https://issuer.example|member",
};
const unrelatedIdentity = {
  subject: "unrelated",
  issuer: "https://issuer.example",
  tokenIdentifier: "https://issuer.example|unrelated",
};
const workerRequestId = "worker_request_0001";

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function bodyBinding(body: string) {
  return {
    requestBodyDigest: await sha256Hex(body),
    requestBodyByteCount: new TextEncoder().encode(body).byteLength,
  };
}

async function expectTicketError(
  operation: Promise<unknown>,
  code:
    | "UNAUTHENTICATED"
    | "INVALID_REQUEST"
    | "RESOURCE_UNAVAILABLE"
    | "SETUP_COMPLETE"
    | "OUTSTANDING_LIMIT"
    | "RATE_LIMITED"
    | "TICKET_INVALID"
    | "COMPLETION_CONFLICT"
    | "DATA_INTEGRITY",
) {
  try {
    await operation;
    expect.fail("Expected ticket operation to fail");
  } catch (error) {
    expect(error).toBeInstanceOf(ConvexError);
    if (!(error instanceof ConvexError)) {
      throw error;
    }
    expect(error.data).toMatchObject({ code });
  }
}

async function seedTicketWorkspace(
  personaSetupState:
    | "notStarted"
    | "essentials"
    | "interview"
    | "complete" = "notStarted",
) {
  const testBackend = convexTest(schema, modules);
  const ids = await testBackend.run(async (ctx) => {
    const timestamp = 1_700_000_000_000;
    async function insertProfile(
      tokenIdentifier: string,
      displayName: string,
    ) {
      return await ctx.db.insert("profiles", {
        tokenIdentifier,
        displayName,
        accountSettings: {},
        lifecycleStatus: "active",
        createdAt: timestamp,
        updatedAt: timestamp,
      });
    }
    const personaOwnerProfileId = await insertProfile(
      personaOwnerIdentity.tokenIdentifier,
      "Persona Owner",
    );
    const workspaceOwnerProfileId = await insertProfile(
      workspaceOwnerIdentity.tokenIdentifier,
      "Workspace Owner",
    );
    const adminProfileId = await insertProfile(
      adminIdentity.tokenIdentifier,
      "Admin",
    );
    const memberProfileId = await insertProfile(
      memberIdentity.tokenIdentifier,
      "Member",
    );
    const unrelatedProfileId = await insertProfile(
      unrelatedIdentity.tokenIdentifier,
      "Unrelated",
    );
    const workspaceId = await ctx.db.insert("workspaces", {
      kind: "team",
      name: "Ticket workspace",
      businessType: "Software",
      createdByProfileId: workspaceOwnerProfileId,
      lifecycleStatus: "active",
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    async function insertMembership(
      userId: Id<"profiles">,
      role: "owner" | "admin" | "member",
    ) {
      return await ctx.db.insert("workspaceMembers", {
        workspaceId,
        userId,
        role,
        status: "active",
        joinedAt: timestamp,
      });
    }
    const personaOwnerMembershipId = await insertMembership(
      personaOwnerProfileId,
      "member",
    );
    const workspaceOwnerMembershipId = await insertMembership(
      workspaceOwnerProfileId,
      "owner",
    );
    const adminMembershipId = await insertMembership(
      adminProfileId,
      "admin",
    );
    const memberMembershipId = await insertMembership(
      memberProfileId,
      "member",
    );
    const personaId = await ctx.db.insert("personas", {
      membershipId: personaOwnerMembershipId,
      workspaceId,
      ownerUserId: personaOwnerProfileId,
      status: "active",
      displayName: "Persona Owner",
      setupState: personaSetupState,
      currentVersion: 0,
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    const secondaryPersonaId = await ctx.db.insert("personas", {
      membershipId: memberMembershipId,
      workspaceId,
      ownerUserId: memberProfileId,
      status: "active",
      displayName: "Member",
      setupState: "notStarted",
      currentVersion: 0,
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    const unrelatedWorkspaceId = await ctx.db.insert("workspaces", {
      kind: "personal",
      name: "Unrelated",
      createdByProfileId: unrelatedProfileId,
      lifecycleStatus: "active",
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    return {
      adminMembershipId,
      adminProfileId,
      memberMembershipId,
      memberProfileId,
      personaId,
      personaOwnerMembershipId,
      personaOwnerProfileId,
      secondaryPersonaId,
      unrelatedProfileId,
      unrelatedWorkspaceId,
      workspaceId,
      workspaceOwnerMembershipId,
      workspaceOwnerProfileId,
    };
  });
  return { ids, testBackend };
}

async function issueChatTicket(
  testBackend: TestBackend,
  personaId: Id<"personas">,
  body = '{"text":"hello","clientTurnId":"turn-1"}',
) {
  const binding = await bodyBinding(body);
  const result = await testBackend
    .withIdentity(personaOwnerIdentity)
    .action(api.requestTickets.issueOnboarding, {
      personaId,
      scope: "onboarding_chat",
      ...binding,
    });
  return { ...result, ...binding };
}

async function consumeTicket(
  testBackend: TestBackend,
  issued: Awaited<ReturnType<typeof issueChatTicket>>,
  overrides: Partial<{
    expectedScope:
      | "onboarding_chat"
      | "onboarding_tts"
      | "onboarding_transcribe";
    expectedRequestBodyDigest: string;
    expectedRequestBodyByteCount: number;
    workerRequestId: string;
  }> = {},
) {
  return await testBackend.mutation(
    internal.workerRequestTicketMutations.consume,
    {
      ticketDigest: await sha256Hex(issued.token),
      expectedScope: overrides.expectedScope ?? issued.scope,
      expectedRequestBodyDigest:
        overrides.expectedRequestBodyDigest ?? issued.requestBodyDigest,
      expectedRequestBodyByteCount:
        overrides.expectedRequestBodyByteCount ??
        issued.requestBodyByteCount,
      workerRequestId: overrides.workerRequestId ?? workerRequestId,
    },
  );
}

type AuditMismatchField =
  | "actorProfileId"
  | "workspaceId"
  | "membershipId"
  | "personaId"
  | "scope"
  | "policyVersion"
  | "issuedAt";

async function corruptTicketAudit(
  testBackend: TestBackend,
  ticketDigest: string,
  field: AuditMismatchField,
  alternateIds: {
    memberProfileId: Id<"profiles">;
    unrelatedWorkspaceId: Id<"workspaces">;
    memberMembershipId: Id<"workspaceMembers">;
    secondaryPersonaId: Id<"personas">;
  },
) {
  await testBackend.run(async (ctx) => {
    const ticket = await ctx.db
      .query("workerRequestTickets")
      .withIndex("by_ticketDigest", (query) =>
        query.eq("ticketDigest", ticketDigest),
      )
      .unique();
    if (ticket === null) {
      throw new Error("Missing ticket");
    }
    const audit = await ctx.db
      .query("workerRequestAudits")
      .withIndex("by_ticketId", (query) => query.eq("ticketId", ticket._id))
      .unique();
    if (audit === null) {
      throw new Error("Missing audit");
    }
    switch (field) {
      case "actorProfileId":
        await ctx.db.patch("workerRequestAudits", audit._id, {
          actorProfileId: alternateIds.memberProfileId,
        });
        break;
      case "workspaceId":
        await ctx.db.patch("workerRequestAudits", audit._id, {
          workspaceId: alternateIds.unrelatedWorkspaceId,
        });
        break;
      case "membershipId":
        await ctx.db.patch("workerRequestAudits", audit._id, {
          membershipId: alternateIds.memberMembershipId,
        });
        break;
      case "personaId":
        await ctx.db.patch("workerRequestAudits", audit._id, {
          personaId: alternateIds.secondaryPersonaId,
        });
        break;
      case "scope":
        await ctx.db.patch("workerRequestAudits", audit._id, {
          scope: "onboarding_tts",
        });
        break;
      case "policyVersion":
        await ctx.db.patch("workerRequestAudits", audit._id, {
          policyVersion: ticket.policyVersion + 1,
        });
        break;
      case "issuedAt":
        await ctx.db.patch("workerRequestAudits", audit._id, {
          issuedAt: ticket.issuedAt + 1,
        });
        break;
    }
  });
}

describe("onboarding Worker request tickets", () => {
  test("requires authentication and persona ownership regardless of workspace role", async () => {
    const { ids, testBackend } = await seedTicketWorkspace();
    const binding = await bodyBinding('{"text":"hello"}');
    const args = {
      personaId: ids.personaId,
      scope: "onboarding_chat" as const,
      ...binding,
    };

    await expectTicketError(
      testBackend.action(api.requestTickets.issueOnboarding, args),
      "UNAUTHENTICATED",
    );
    for (const identity of [
      unrelatedIdentity,
      memberIdentity,
      adminIdentity,
      workspaceOwnerIdentity,
    ]) {
      await expectTicketError(
        testBackend
          .withIdentity(identity)
          .action(api.requestTickets.issueOnboarding, args),
        "RESOURCE_UNAVAILABLE",
      );
    }
    await expect(
      testBackend
        .withIdentity(personaOwnerIdentity)
        .action(api.requestTickets.issueOnboarding, args),
    ).resolves.toMatchObject({
      scope: "onboarding_chat",
      policyVersion: 1,
    });
  });

  test("returns a fresh 256-bit bearer once and persists only digests", async () => {
    const { ids, testBackend } = await seedTicketWorkspace();
    const first = await issueChatTicket(testBackend, ids.personaId);
    const second = await issueChatTicket(testBackend, ids.personaId);

    expect(first.token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(second.token).not.toBe(first.token);
    expect(first.expiresAt).toBeGreaterThan(Date.now());
    const state = await testBackend.run(async (ctx) => ({
      tickets: await ctx.db.query("workerRequestTickets").take(10),
      audits: await ctx.db.query("workerRequestAudits").take(10),
    }));
    expect(state.tickets).toHaveLength(2);
    expect(state.audits).toHaveLength(2);
    expect(state.tickets[0].ticketDigest).toMatch(/^[0-9a-f]{64}$/);
    expect(JSON.stringify(state)).not.toContain(first.token);
    expect(JSON.stringify(state)).not.toContain("hello");
    expect(Object.keys(state.audits[0])).not.toContain("ticketDigest");
  });

  test("enforces digest, integer count, scope body, and empty transcription policy", async () => {
    const { ids, testBackend } = await seedTicketWorkspace();
    const asOwner = testBackend.withIdentity(personaOwnerIdentity);
    const validDigest = await sha256Hex("body");
    const base = {
      personaId: ids.personaId,
      scope: "onboarding_chat" as const,
      requestBodyDigest: validDigest,
      requestBodyByteCount: 4,
    };
    for (const overrides of [
      { requestBodyDigest: validDigest.toUpperCase() },
      { requestBodyDigest: "a".repeat(63) },
      { requestBodyByteCount: -1 },
      { requestBodyByteCount: 1.5 },
      { requestBodyByteCount: 0 },
      { requestBodyByteCount: 2_305 },
    ]) {
      await expectTicketError(
        asOwner.action(api.requestTickets.issueOnboarding, {
          ...base,
          ...overrides,
        }),
        "INVALID_REQUEST",
      );
    }
    await expectTicketError(
      asOwner.action(api.requestTickets.issueOnboarding, {
        personaId: ids.personaId,
        scope: "onboarding_transcribe",
        requestBodyDigest: validDigest,
        requestBodyByteCount: 0,
      }),
      "INVALID_REQUEST",
    );
    await expect(
      asOwner.action(api.requestTickets.issueOnboarding, {
        personaId: ids.personaId,
        scope: "onboarding_transcribe",
        requestBodyDigest: emptyRequestBodyDigest,
        requestBodyByteCount: 0,
      }),
    ).resolves.toMatchObject({ scope: "onboarding_transcribe" });
  });

  test("rejects client policy fields and returns scope-specific server policy", async () => {
    const { ids, testBackend } = await seedTicketWorkspace();
    const asOwner = testBackend.withIdentity(personaOwnerIdentity);
    const chatBinding = await bodyBinding('{"text":"hello"}');
    await expect(
      asOwner.action(api.requestTickets.issueOnboarding, {
        personaId: ids.personaId,
        scope: "onboarding_chat",
        ...chatBinding,
        // @ts-expect-error Clients cannot select provider policy.
        model: "client-selected-model",
      }),
    ).rejects.toThrow("Validator error");

    const ttsBody = "{}";
    const ttsBinding = await bodyBinding(ttsBody);
    const ttsTicket = await asOwner.action(
      api.requestTickets.issueOnboarding,
      {
        personaId: ids.personaId,
        scope: "onboarding_tts",
        ...ttsBinding,
      },
    );
    const ttsConsumed = await testBackend.mutation(
      internal.workerRequestTicketMutations.consume,
      {
        ticketDigest: await sha256Hex(ttsTicket.token),
        expectedScope: "onboarding_tts",
        expectedRequestBodyDigest: ttsBinding.requestBodyDigest,
        expectedRequestBodyByteCount: ttsBinding.requestBodyByteCount,
        workerRequestId: "worker_request_tts_policy",
      },
    );
    expect(ttsConsumed.policy).toMatchObject({
      kind: "onboarding_tts",
      voiceId: "EXAVITQu4vr4xnSDxMaL",
      model: "eleven_flash_v2_5",
    });

    const transcriptionTicket = await asOwner.action(
      api.requestTickets.issueOnboarding,
      {
        personaId: ids.personaId,
        scope: "onboarding_transcribe",
        requestBodyDigest: emptyRequestBodyDigest,
        requestBodyByteCount: 0,
      },
    );
    const transcriptionConsumed = await testBackend.mutation(
      internal.workerRequestTicketMutations.consume,
      {
        ticketDigest: await sha256Hex(transcriptionTicket.token),
        expectedScope: "onboarding_transcribe",
        expectedRequestBodyDigest: emptyRequestBodyDigest,
        expectedRequestBodyByteCount: 0,
        workerRequestId: "worker_request_transcribe_policy",
      },
    );
    expect(transcriptionConsumed.policy).toEqual({
      kind: "onboarding_transcribe",
      redemptionWindowSeconds: 30,
      maximumSessionSeconds: 900,
    });
  });

  test("fails closed for complete, removing, deleted, and inactive lifecycle records", async () => {
    const completeFixture = await seedTicketWorkspace("complete");
    const binding = await bodyBinding('{"text":"hello"}');
    await expectTicketError(
      completeFixture.testBackend
        .withIdentity(personaOwnerIdentity)
        .action(api.requestTickets.issueOnboarding, {
          personaId: completeFixture.ids.personaId,
          scope: "onboarding_chat",
          ...binding,
        }),
      "SETUP_COMPLETE",
    );

    for (const scenario of [
      "removingPersona",
      "deletedPersona",
      "removedMembership",
      "deletingWorkspace",
      "deletionPendingProfile",
    ] as const) {
      const { ids, testBackend } = await seedTicketWorkspace();
      await testBackend.run(async (ctx) => {
        if (scenario === "removingPersona") {
          await ctx.db.patch("personas", ids.personaId, {
            status: "removing",
          });
        } else if (scenario === "deletedPersona") {
          await ctx.db.delete("personas", ids.personaId);
        } else if (scenario === "removedMembership") {
          await ctx.db.patch(
            "workspaceMembers",
            ids.personaOwnerMembershipId,
            { status: "removed", removedAt: Date.now() },
          );
        } else if (scenario === "deletingWorkspace") {
          await ctx.db.patch("workspaces", ids.workspaceId, {
            lifecycleStatus: "deleting",
          });
        } else {
          await ctx.db.patch("profiles", ids.personaOwnerProfileId, {
            lifecycleStatus: "deletionPending",
            deletionRequestedAt: Date.now(),
            deletionScheduledFor: Date.now() + 1,
          });
        }
      });
      await expectTicketError(
        testBackend
          .withIdentity(personaOwnerIdentity)
          .action(api.requestTickets.issueOnboarding, {
            personaId: ids.personaId,
            scope: "onboarding_chat",
            ...binding,
          }),
        "RESOURCE_UNAVAILABLE",
      );
    }
  });

  test("allows issuance and consumption during essentials and interview only", async () => {
    for (const setupState of ["essentials", "interview"] as const) {
      const { ids, testBackend } = await seedTicketWorkspace(setupState);
      const issued = await issueChatTicket(testBackend, ids.personaId);
      await expect(consumeTicket(testBackend, issued)).resolves.toMatchObject({
        policy: { kind: "onboarding_chat" },
      });
    }

    const { ids, testBackend } = await seedTicketWorkspace("complete");
    const binding = await bodyBinding('{"text":"hello"}');
    await expectTicketError(
      testBackend
        .withIdentity(personaOwnerIdentity)
        .action(api.requestTickets.issueOnboarding, {
          personaId: ids.personaId,
          scope: "onboarding_chat",
          ...binding,
        }),
      "SETUP_COMPLETE",
    );
  });

  test("rejects malformed persona ownership and relationship graphs", async () => {
    for (const scenario of [
      "wrongOwner",
      "wrongMembershipUser",
      "wrongMembershipWorkspace",
    ] as const) {
      const { ids, testBackend } = await seedTicketWorkspace();
      await testBackend.run(async (ctx) => {
        if (scenario === "wrongOwner") {
          await ctx.db.patch("personas", ids.personaId, {
            ownerUserId: ids.memberProfileId,
          });
        } else if (scenario === "wrongMembershipUser") {
          await ctx.db.patch(
            "workspaceMembers",
            ids.personaOwnerMembershipId,
            { userId: ids.memberProfileId },
          );
        } else {
          const otherWorkspaceId = await ctx.db.insert("workspaces", {
            kind: "personal",
            name: "Other",
            createdByProfileId: ids.unrelatedProfileId,
            lifecycleStatus: "active",
            createdAt: Date.now(),
            updatedAt: Date.now(),
          });
          await ctx.db.patch(
            "workspaceMembers",
            ids.personaOwnerMembershipId,
            { workspaceId: otherWorkspaceId },
          );
        }
      });
      const binding = await bodyBinding('{"text":"hello"}');
      await expectTicketError(
        testBackend
          .withIdentity(personaOwnerIdentity)
          .action(api.requestTickets.issueOnboarding, {
            personaId: ids.personaId,
            scope: "onboarding_chat",
            ...binding,
          }),
        "RESOURCE_UNAVAILABLE",
      );
    }
  });

  test("enforces outstanding and concurrent short-window limits", async () => {
    const { ids, testBackend } = await seedTicketWorkspace();
    const issued = await Promise.all(
      Array.from({ length: 3 }, async (_, index) =>
        await issueChatTicket(
          testBackend,
          ids.personaId,
          `{"text":"hello","clientTurnId":"outstanding-${index}"}`,
        ),
      ),
    );
    await expectTicketError(
      issueChatTicket(
        testBackend,
        ids.personaId,
        '{"text":"hello","clientTurnId":"outstanding-4"}',
      ),
      "OUTSTANDING_LIMIT",
    );
    for (let index = 0; index < issued.length; index += 1) {
      await consumeTicket(testBackend, issued[index], {
        workerRequestId: `worker_request_out_${index}`,
      });
    }
    for (let index = 0; index < 6; index += 1) {
      const ticket = await issueChatTicket(
        testBackend,
        ids.personaId,
        `{"text":"hello","clientTurnId":"rate-seed-${index}"}`,
      );
      await consumeTicket(testBackend, ticket, {
        workerRequestId: `worker_request_seed_${index}`,
      });
    }
    const attempts = await Promise.allSettled(
      Array.from({ length: 3 }, async (_, index) => {
        const ticket = await issueChatTicket(
          testBackend,
          ids.personaId,
          `{"text":"hello","clientTurnId":"rate-${index}"}`,
        );
        return ticket;
      }),
    );
    expect(attempts.filter((result) => result.status === "fulfilled")).toHaveLength(1);
    expect(attempts.filter((result) => result.status === "rejected")).toHaveLength(
      2,
    );
  });

  test("enforces the TTS daily payload quota with bounded issuance reads", async () => {
    const { ids, testBackend } = await seedTicketWorkspace();
    const asOwner = testBackend.withIdentity(personaOwnerIdentity);
    const digest = await sha256Hex("x".repeat(4_000));
    for (let index = 0; index < 25; index += 1) {
      const issued = await asOwner.action(api.requestTickets.issueOnboarding, {
        personaId: ids.personaId,
        scope: "onboarding_tts",
        requestBodyDigest: digest,
        requestBodyByteCount: 4_000,
      });
      await testBackend.mutation(
        internal.workerRequestTicketMutations.consume,
        {
          ticketDigest: await sha256Hex(issued.token),
          expectedScope: "onboarding_tts",
          expectedRequestBodyDigest: digest,
          expectedRequestBodyByteCount: 4_000,
          workerRequestId: `worker_request_tts_${index}`,
        },
      );
    }
    await expectTicketError(
      asOwner.action(api.requestTickets.issueOnboarding, {
        personaId: ids.personaId,
        scope: "onboarding_tts",
        requestBodyDigest: await sha256Hex("xx"),
        requestBodyByteCount: 2,
      }),
      "RATE_LIMITED",
    );
  });

  test("consumes exactly once under concurrency and returns only server policy", async () => {
    const { ids, testBackend } = await seedTicketWorkspace();
    const issued = await issueChatTicket(testBackend, ids.personaId);
    const results = await Promise.allSettled(
      Array.from({ length: 12 }, async () =>
        await consumeTicket(testBackend, issued),
      ),
    );
    const successes = results.filter(
      (result) => result.status === "fulfilled",
    );
    const failures = results.filter((result) => result.status === "rejected");
    expect(successes).toHaveLength(1);
    expect(failures).toHaveLength(11);
    if (successes[0].status !== "fulfilled") {
      throw new Error("Expected one successful consumption");
    }
    expect(successes[0].value).toMatchObject({
      policyVersion: 1,
      policy: {
        kind: "onboarding_chat",
        model: "claude-haiku-4-5-20251001",
        maximumOutputTokens: 512,
      },
    });
    expect(successes[0].value.policy).not.toHaveProperty("voiceId");
  });

  test("rejects replay, wrong route, altered body, wrong count, and cross-scope use", async () => {
    const scenarios = [
      { expectedScope: "onboarding_tts" as const },
      { expectedRequestBodyDigest: await sha256Hex("altered") },
      { expectedRequestBodyByteCount: 3 },
    ];
    for (const overrides of scenarios) {
      const { ids, testBackend } = await seedTicketWorkspace();
      const issued = await issueChatTicket(testBackend, ids.personaId);
      await expectTicketError(
        consumeTicket(testBackend, issued, overrides),
        "TICKET_INVALID",
      );
      await expect(consumeTicket(testBackend, issued)).resolves.toBeDefined();
      await expectTicketError(
        consumeTicket(testBackend, issued),
        "TICKET_INVALID",
      );
    }
  });

  test("rejects expiry and issue-then-remove TOCTOU without consuming", async () => {
    for (const scenario of ["expired", "removed"] as const) {
      const { ids, testBackend } = await seedTicketWorkspace();
      const issued = await issueChatTicket(testBackend, ids.personaId);
      const ticketDigest = await sha256Hex(issued.token);
      await testBackend.run(async (ctx) => {
        const ticket = await ctx.db
          .query("workerRequestTickets")
          .withIndex("by_ticketDigest", (query) =>
            query.eq("ticketDigest", ticketDigest),
          )
          .unique();
        if (ticket === null) {
          throw new Error("Missing issued ticket");
        }
        if (scenario === "expired") {
          await ctx.db.patch("workerRequestTickets", ticket._id, {
            expiresAt: Date.now() - 1,
          });
        } else {
          await ctx.db.patch(
            "workspaceMembers",
            ids.personaOwnerMembershipId,
            { status: "removed", removedAt: Date.now() },
          );
        }
      });
      await expectTicketError(
        consumeTicket(testBackend, issued),
        "TICKET_INVALID",
      );
      const ticket = await testBackend.run(
        async (ctx) =>
          await ctx.db
            .query("workerRequestTickets")
            .withIndex("by_ticketDigest", (query) =>
              query.eq("ticketDigest", ticketDigest),
            )
            .unique(),
      );
      expect(ticket?.status).toBe("issued");
    }
  });

  test("rolls back consume when its audit relationship is malformed", async () => {
    const { ids, testBackend } = await seedTicketWorkspace();
    const issued = await issueChatTicket(testBackend, ids.personaId);
    const ticketDigest = await sha256Hex(issued.token);
    await testBackend.run(async (ctx) => {
      const ticket = await ctx.db
        .query("workerRequestTickets")
        .withIndex("by_ticketDigest", (query) =>
          query.eq("ticketDigest", ticketDigest),
        )
        .unique();
      if (ticket === null) {
        throw new Error("Missing ticket");
      }
      const audit = await ctx.db
        .query("workerRequestAudits")
        .withIndex("by_ticketId", (query) => query.eq("ticketId", ticket._id))
        .unique();
      if (audit === null) {
        throw new Error("Missing audit");
      }
      await ctx.db.delete("workerRequestAudits", audit._id);
    });
    await expectTicketError(
      consumeTicket(testBackend, issued),
      "DATA_INTEGRITY",
    );
    const ticket = await testBackend.run(
      async (ctx) =>
        await ctx.db
          .query("workerRequestTickets")
          .withIndex("by_ticketDigest", (query) =>
            query.eq("ticketDigest", ticketDigest),
          )
          .unique(),
    );
    expect(ticket?.status).toBe("issued");
    expect(ticket !== null && "consumptionId" in ticket).toBe(false);
  });

  test("consume rejects every denormalized audit mismatch and rolls back", async () => {
    const mismatchFields: AuditMismatchField[] = [
      "actorProfileId",
      "workspaceId",
      "membershipId",
      "personaId",
      "scope",
      "policyVersion",
      "issuedAt",
    ];
    for (const mismatchField of mismatchFields) {
      const { ids, testBackend } = await seedTicketWorkspace();
      const issued = await issueChatTicket(testBackend, ids.personaId);
      const ticketDigest = await sha256Hex(issued.token);
      await corruptTicketAudit(
        testBackend,
        ticketDigest,
        mismatchField,
        ids,
      );
      await expectTicketError(
        consumeTicket(testBackend, issued),
        "DATA_INTEGRITY",
      );
      const ticket = await testBackend.run(
        async (ctx) =>
          await ctx.db
            .query("workerRequestTickets")
            .withIndex("by_ticketDigest", (query) =>
              query.eq("ticketDigest", ticketDigest),
            )
            .unique(),
      );
      expect(ticket?.status).toBe("issued");
      expect(ticket !== null && "consumptionId" in ticket).toBe(false);
    }
  });

  test("completion rejects every denormalized audit mismatch and rolls back", async () => {
    const mismatchFields: AuditMismatchField[] = [
      "actorProfileId",
      "workspaceId",
      "membershipId",
      "personaId",
      "scope",
      "policyVersion",
      "issuedAt",
    ];
    for (const mismatchField of mismatchFields) {
      const { ids, testBackend } = await seedTicketWorkspace();
      const issued = await issueChatTicket(testBackend, ids.personaId);
      const ticketDigest = await sha256Hex(issued.token);
      const consumed = await consumeTicket(testBackend, issued);
      await corruptTicketAudit(
        testBackend,
        ticketDigest,
        mismatchField,
        ids,
      );
      await expectTicketError(
        testBackend.mutation(
          internal.workerRequestTicketMutations.complete,
          {
            consumptionId: consumed.consumptionId,
            workerRequestId,
            completion: {
              outcome: "succeeded",
              latencyMs: 10,
              usage: {},
            },
          },
        ),
        "DATA_INTEGRITY",
      );
      const audit = await testBackend.run(async (ctx) => {
        const ticketId = ctx.db.normalizeId(
          "workerRequestTickets",
          consumed.consumptionId,
        );
        if (ticketId === null) {
          throw new Error("Missing consumed ticket ID");
        }
        return await ctx.db
          .query("workerRequestAudits")
          .withIndex("by_ticketId", (query) =>
            query.eq("ticketId", ticketId),
          )
          .unique();
      });
      expect(audit?.status).toBe("consumed");
      expect(audit?.completion).toBeUndefined();
    }
  });

  test("records sanitized completion idempotently and rejects conflicts", async () => {
    const { ids, testBackend } = await seedTicketWorkspace();
    const issued = await issueChatTicket(testBackend, ids.personaId);
    const consumed = await consumeTicket(testBackend, issued);
    const completion = {
      outcome: "succeeded" as const,
      providerRequestId: "provider-request-1",
      httpStatusClass: 2,
      latencyMs: 325,
      usage: { inputUnits: 10, outputUnits: 20 },
    };
    const args = {
      consumptionId: consumed.consumptionId,
      workerRequestId,
      completion,
    };
    await expect(
      testBackend.mutation(
        internal.workerRequestTicketMutations.complete,
        args,
      ),
    ).resolves.toEqual({ didComplete: true });
    await expect(
      testBackend.mutation(
        internal.workerRequestTicketMutations.complete,
        args,
      ),
    ).resolves.toEqual({ didComplete: false });
    await expectTicketError(
      testBackend.mutation(
        internal.workerRequestTicketMutations.complete,
        {
          ...args,
          completion: { ...completion, latencyMs: 326 },
        },
      ),
      "COMPLETION_CONFLICT",
    );
    const state = await testBackend.run(async (ctx) => ({
      ticket: await ctx.db.get(
        "workerRequestTickets",
        ctx.db.normalizeId(
          "workerRequestTickets",
          consumed.consumptionId,
        )!,
      ),
      audits: await ctx.db.query("workerRequestAudits").take(5),
    }));
    expect(state.ticket?.status).toBe("consumed");
    if (state.ticket?.status !== "consumed") {
      throw new Error("Expected consumed ticket");
    }
    expect(state.ticket.purgeEligibleAt).toBeGreaterThan(
      state.ticket.consumedAt,
    );
    expect(state.audits[0]).toMatchObject({
      status: "completed",
      completion,
    });
    expect(state.audits[0].retentionExpiresAt).toBeGreaterThan(
      state.audits[0].issuedAt,
    );
    expect(JSON.stringify(state)).not.toContain(issued.token);
    expect(JSON.stringify(state)).not.toContain("hello");
  });
});
