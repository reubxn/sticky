/// <reference types="vite/client" />

import { convexTest } from "convex-test";
import type { TestConvexForDataModelAndIdentity } from "convex-test";
import { ConvexError } from "convex/values";
import { describe, expect, test } from "vitest";

import { api } from "./_generated/api";
import type { DataModel, Id } from "./_generated/dataModel";
import {
  maximumNonterminalSessionOperationReceipts,
  maximumSessionOperationReceipts,
} from "./personaFoundation";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");
type TestBackend = TestConvexForDataModelAndIdentity<DataModel>;
type AuthenticatedTestBackend = ReturnType<TestBackend["withIdentity"]>;

const ownerIdentity = {
  subject: "persona-owner",
  issuer: "https://issuer.example",
  tokenIdentifier: "https://issuer.example|persona-owner",
  name: "Persona Owner",
};
const teammateIdentity = {
  subject: "teammate",
  issuer: "https://issuer.example",
  tokenIdentifier: "https://issuer.example|teammate",
  name: "Teammate",
};

async function expectPersonaError(
  operation: Promise<unknown>,
  code: string,
) {
  try {
    await operation;
    expect.fail("Expected persona operation to fail");
  } catch (error) {
    expect(error).toBeInstanceOf(ConvexError);
    if (!(error instanceof ConvexError)) {
      throw error;
    }
    expect(error.data).toMatchObject({ code });
  }
}

async function provisionOwner() {
  const testBackend = convexTest(schema, modules);
  const ownerBackend = testBackend.withIdentity(ownerIdentity);
  const provisioned = await ownerBackend.mutation(api.accounts.provisionCurrent);
  return {
    ownerBackend,
    personaId: provisioned.snapshot.personaId,
    testBackend,
    workspaceId: provisioned.snapshot.workspaceId,
  };
}

async function appendAndInterpret(
  ownerBackend: AuthenticatedTestBackend,
  args: {
    sessionId: Id<"personaOnboardingSessions">;
    revision: number;
    personaVersion: number;
    suffix: string;
    text: string;
    changes: Array<
      | {
          operation: "create";
          content:
            | { kind: "work_context"; statement: string }
            | { kind: "communication_preference"; statement: string };
          evidenceExcerpt: string;
          confidence: number;
        }
      | {
          operation: "delete";
          recordKey: string;
          evidenceExcerpt: string;
          confidence: number;
        }
    >;
  },
) {
  const turn = await ownerBackend.mutation(
    api.personaOnboarding.appendOwnerTurn,
    {
      sessionId: args.sessionId,
      expectedSessionRevision: args.revision,
      turnId: `turn-${args.suffix}`,
      clientMutationId: `append-${args.suffix}`,
      inputMode: "voice",
      text: args.text,
    },
  );
  return await ownerBackend.mutation(
    api.personaOnboarding.applyOwnerTurnInterpretation,
    {
      sessionId: args.sessionId,
      sourceTurnId: turn._id,
      expectedSessionRevision: args.revision + 1,
      expectedPersonaVersion: args.personaVersion,
      clientMutationId: `interpret-${args.suffix}`,
      changes: args.changes,
    },
  );
}

async function activatePersona() {
  const fixture = await provisionOwner();
  const started = await fixture.ownerBackend.mutation(
    api.personaOnboarding.startOrResume,
    {
      personaId: fixture.personaId,
      clientMutationId: "start-session",
      expectedSessionRevision: 0,
    },
  );
  const work = await appendAndInterpret(fixture.ownerBackend, {
    sessionId: started.sessionId,
    revision: 0,
    personaVersion: 0,
    suffix: "work",
    text: "I build developer tools for design teams.",
    changes: [
      {
        operation: "create",
        content: {
          kind: "work_context",
          statement: "Builds developer tools for design teams",
        },
        evidenceExcerpt: "build developer tools",
        confidence: 1,
      },
    ],
  });
  const communication = await appendAndInterpret(fixture.ownerBackend, {
    sessionId: started.sessionId,
    revision: work.sessionRevision,
    personaVersion: work.versionNumber,
    suffix: "communication",
    text: "Please give me concise, direct answers.",
    changes: [
      {
        operation: "create",
        content: {
          kind: "communication_preference",
          statement: "Prefers concise, direct answers",
        },
        evidenceExcerpt: "concise, direct answers",
        confidence: 1,
      },
    ],
  });
  return { ...fixture, sessionId: started.sessionId, state: communication };
}

async function fillSessionReceipts(
  testBackend: TestBackend,
  personaId: Id<"personas">,
  sessionId: Id<"personaOnboardingSessions">,
  status: "active" | "paused",
) {
  await testBackend.run(async (ctx) => {
    const persona = await ctx.db.get("personas", personaId);
    const session = await ctx.db.get("personaOnboardingSessions", sessionId);
    if (persona === null || session === null) {
      throw new Error("Missing receipt fixture graph");
    }
    const existing = await ctx.db
      .query("personaSessionOperationReceipts")
      .withIndex("by_sessionId_and_clientMutationId", (query) =>
        query.eq("sessionId", sessionId),
      )
      .take(maximumSessionOperationReceipts);
    for (
      let index = existing.length;
      index < maximumNonterminalSessionOperationReceipts;
      index += 1
    ) {
      await ctx.db.insert("personaSessionOperationReceipts", {
        personaId,
        sessionId,
        membershipId: persona.membershipId,
        workspaceId: persona.workspaceId,
        ownerUserId: persona.ownerUserId,
        clientMutationId: `capacity-${status}-${index}`,
        operation: status === "active" ? "resume" : "pause",
        requestFingerprint: index
          .toString(16)
          .padStart(2, "0")
          .repeat(32),
        resultStatus: status,
        resultRevision: session.revision,
        resultSetupState: persona.setupState,
        createdAt: Date.now() + index,
      });
    }
  });
}

describe("persona onboarding foundation", () => {
  test("moves through essentials and atomically activates at the minimum", async () => {
    const fixture = await provisionOwner();
    const before = await fixture.ownerBackend.query(
      api.personaOnboarding.getOwnedState,
      { personaId: fixture.personaId },
    );
    expect(before).toMatchObject({
      setupState: "notStarted",
      currentVersion: 0,
      activatedAt: null,
      session: null,
      minimumReadiness: { isMet: false },
    });

    const started = await fixture.ownerBackend.mutation(
      api.personaOnboarding.startOrResume,
      {
        personaId: fixture.personaId,
        clientMutationId: "start",
        expectedSessionRevision: 0,
      },
    );
    expect(started).toMatchObject({ setupState: "essentials", revision: 0 });
    const work = await appendAndInterpret(fixture.ownerBackend, {
      sessionId: started.sessionId,
      revision: 0,
      personaVersion: 0,
      suffix: "work-only",
      text: "I work on accessibility software.",
      changes: [
        {
          operation: "create",
          content: {
            kind: "work_context",
            statement: "Works on accessibility software",
          },
          evidenceExcerpt: "accessibility software",
          confidence: 1,
        },
      ],
    });
    expect(work).toMatchObject({
      setupState: "essentials",
      activatedAt: null,
      versionNumber: 1,
    });
    const communication = await appendAndInterpret(fixture.ownerBackend, {
      sessionId: started.sessionId,
      revision: work.sessionRevision,
      personaVersion: 1,
      suffix: "minimum",
      text: "I prefer direct recommendations.",
      changes: [
        {
          operation: "create",
          content: {
            kind: "communication_preference",
            statement: "Prefers direct recommendations",
          },
          evidenceExcerpt: "direct recommendations",
          confidence: 1,
        },
      ],
    });
    expect(communication.setupState).toBe("interview");
    expect(communication.activatedAt).toEqual(expect.any(Number));

    const state = await fixture.ownerBackend.query(
      api.personaOnboarding.getOwnedState,
      { personaId: fixture.personaId },
    );
    expect(state.minimumReadiness).toEqual({
      hasWorkContext: true,
      hasCommunicationPreference: true,
      isMet: true,
    });
    expect(state.currentRecords).toHaveLength(2);
  });

  test("checks turn idempotency before stale revisions and protects evidence", async () => {
    const fixture = await provisionOwner();
    const session = await fixture.ownerBackend.mutation(
      api.personaOnboarding.startOrResume,
      {
        personaId: fixture.personaId,
        clientMutationId: "start",
        expectedSessionRevision: 0,
      },
    );
    const args = {
      sessionId: session.sessionId,
      expectedSessionRevision: 0,
      turnId: "answer-1",
      clientMutationId: "append-1",
      inputMode: "text" as const,
      text: "I design financial tools.",
    };
    const first = await fixture.ownerBackend.mutation(
      api.personaOnboarding.appendOwnerTurn,
      args,
    );
    const retry = await fixture.ownerBackend.mutation(
      api.personaOnboarding.appendOwnerTurn,
      { ...args, expectedSessionRevision: 999 },
    );
    expect(retry._id).toBe(first._id);
    await expectPersonaError(
      fixture.ownerBackend.mutation(
        api.personaOnboarding.appendOwnerTurn,
        { ...args, text: "Different answer", expectedSessionRevision: 1 },
      ),
      "IDEMPOTENCY_CONFLICT",
    );
    await expectPersonaError(
      fixture.ownerBackend.mutation(
        api.personaOnboarding.applyOwnerTurnInterpretation,
        {
          sessionId: session.sessionId,
          sourceTurnId: first._id,
          expectedSessionRevision: 1,
          expectedPersonaVersion: 0,
          clientMutationId: "interpret",
          changes: [
            {
              operation: "create",
              content: {
                kind: "work_context",
                statement: "Designs financial tools",
              },
              evidenceExcerpt: "not in answer",
              confidence: 1,
            },
          ],
        },
      ),
      "INVALID_REQUEST",
    );
  });

  test("paginates applied owner interpretation fingerprints privately", async () => {
    const fixture = await activatePersona();
    const turns = await fixture.ownerBackend.query(
      api.personaOnboarding.listOwnedTurns,
      {
        sessionId: fixture.sessionId,
        paginationOpts: { cursor: null, numItems: 10 },
      },
    );
    const interpreted = turns.page.filter(
      (turn) => turn.interpretationStatus === "applied",
    );
    expect(interpreted).toHaveLength(2);
    for (const turn of interpreted) {
      expect(turn.interpretationRequestFingerprint).toMatch(/^[0-9a-f]{64}$/);
      expect(turn.interpretationClientMutationId).toBeDefined();
      expect(turn.interpretedVersionId).toBeDefined();
    }

    const teammateBackend = fixture.testBackend.withIdentity(teammateIdentity);
    await teammateBackend.mutation(api.accounts.provisionCurrent);
    await expectPersonaError(
      teammateBackend.query(api.personaOnboarding.listOwnedTurns, {
        sessionId: fixture.sessionId,
        paginationOpts: { cursor: null, numItems: 10 },
      }),
      "RESOURCE_UNAVAILABLE",
    );
  });

  test("preserves activation and immutable versions when minimum removal fails", async () => {
    const fixture = await activatePersona();
    const state = await fixture.ownerBackend.query(
      api.personaOnboarding.getOwnedState,
      { personaId: fixture.personaId },
    );
    const work = state.currentRecords.find(
      (record) => record.kind === "work_context",
    )!;
    const before = await fixture.testBackend.run(async (ctx) => ({
      records: await ctx.db.query("personaRecords").take(10),
      versions: await ctx.db.query("personaVersions").take(10),
      persona: await ctx.db.get("personas", fixture.personaId),
    }));
    await expectPersonaError(
      fixture.ownerBackend.mutation(api.personaRecords.applyOwnedChanges, {
        personaId: fixture.personaId,
        expectedPersonaVersion: state.currentVersion,
        clientMutationId: "remove-final-work",
        changes: [
          { operation: "delete", recordKey: work.recordKey, confidence: 1 },
        ],
      }),
      "MINIMUM_REQUIRED",
    );
    const after = await fixture.testBackend.run(async (ctx) => ({
      records: await ctx.db.query("personaRecords").take(10),
      versions: await ctx.db.query("personaVersions").take(10),
      persona: await ctx.db.get("personas", fixture.personaId),
    }));
    expect(after).toEqual(before);
  });

  test("supports skipped-for-now resume and terminal completion", async () => {
    const fixture = await activatePersona();
    const paused = await fixture.ownerBackend.mutation(
      api.personaOnboarding.pause,
      {
        sessionId: fixture.sessionId,
        expectedSessionRevision: fixture.state.sessionRevision,
        reason: "skippedForNow",
        clientMutationId: "skip",
      },
    );
    expect(paused).toMatchObject({ status: "paused", setupState: "interview" });
    const resumed = await fixture.ownerBackend.mutation(
      api.personaOnboarding.startOrResume,
      {
        personaId: fixture.personaId,
        expectedSessionRevision: paused.revision,
        clientMutationId: "resume",
      },
    );
    expect(resumed.sessionId).toBe(fixture.sessionId);
    const completed = await fixture.ownerBackend.mutation(
      api.personaOnboarding.complete,
      {
        sessionId: fixture.sessionId,
        expectedSessionRevision: resumed.revision,
        clientMutationId: "complete",
      },
    );
    expect(completed).toMatchObject({ status: "completed", setupState: "complete" });
    await expectPersonaError(
      fixture.ownerBackend.mutation(api.personaOnboarding.startOrResume, {
        personaId: fixture.personaId,
        clientMutationId: "reopen",
        expectedSessionRevision: completed.revision,
      }),
      "SETUP_COMPLETE",
    );
  });

  test("keeps private state owner-only and publishes only approved boundary text", async () => {
    const fixture = await activatePersona();
    const boundaryVersion = await fixture.ownerBackend.mutation(
      api.personaRecords.applyOwnedChanges,
      {
        personaId: fixture.personaId,
        expectedPersonaVersion: fixture.state.versionNumber,
        clientMutationId: "add-boundary",
        changes: [
          {
            operation: "create",
            content: {
              kind: "boundary",
              mode: "ask_first",
              statement: "Ask before sharing estimates",
            },
            confidence: 1,
          },
        ],
      },
    );
    const teammateIds = await fixture.testBackend.run(async (ctx) => {
      const timestamp = Date.now();
      const profileId = await ctx.db.insert("profiles", {
        tokenIdentifier: teammateIdentity.tokenIdentifier,
        displayName: "Teammate",
        accountSettings: {},
        lifecycleStatus: "active",
        createdAt: timestamp,
        updatedAt: timestamp,
      });
      const membershipId = await ctx.db.insert("workspaceMembers", {
        workspaceId: fixture.workspaceId,
        userId: profileId,
        role: "admin",
        status: "active",
        joinedAt: timestamp,
      });
      return { membershipId, profileId };
    });
    const teammate = fixture.testBackend.withIdentity(teammateIdentity);
    await expectPersonaError(
      teammate.query(api.personaOnboarding.getOwnedState, {
        personaId: fixture.personaId,
      }),
      "UNAUTHORIZED",
    );
    const draft = await fixture.ownerBackend.mutation(
      api.personaBoundarySummaries.saveOwnedDraft,
      {
        personaId: fixture.personaId,
        expectedPersonaVersion: boundaryVersion.versionNumber,
        clientMutationId: "draft-boundary",
        summaryText: "Ask before sharing delivery estimates.",
      },
    );
    await expect(
      teammate.query(api.personaBoundarySummaries.getReadable, {
        personaId: fixture.personaId,
      }),
    ).resolves.toBeNull();
    await fixture.ownerBackend.mutation(
      api.personaBoundarySummaries.approveOwnedDraft,
      {
        summaryId: draft.summaryId,
        expectedPersonaVersion: boundaryVersion.versionNumber,
        expectedApprovedSummaryId: null,
        clientMutationId: "approve-boundary",
      },
    );
    await expect(
      teammate.query(api.personaBoundarySummaries.getReadable, {
        personaId: fixture.personaId,
      }),
    ).resolves.toEqual({
      personaId: fixture.personaId,
      summaryText: "Ask before sharing delivery estimates.",
      approvedAt: expect.any(Number),
    });
    await fixture.ownerBackend.mutation(api.personaRecords.applyOwnedChanges, {
      personaId: fixture.personaId,
      expectedPersonaVersion: boundaryVersion.versionNumber,
      clientMutationId: "change-boundary",
      changes: [
        {
          operation: "create",
          content: {
            kind: "boundary",
            mode: "never",
            statement: "Never reveal private customer names",
          },
          confidence: 1,
        },
      ],
    });
    await expect(
      teammate.query(api.personaBoundarySummaries.getReadable, {
        personaId: fixture.personaId,
      }),
    ).resolves.toBeNull();
    expect(teammateIds.membershipId).toBeDefined();
  });

  test("normalizes private authorization denial and paginates immutable versions", async () => {
    const fixture = await activatePersona();
    await expectPersonaError(
      fixture.testBackend.query(api.personaOnboarding.getOwnedState, {
        personaId: fixture.personaId,
      }),
      "UNAUTHENTICATED",
    );
    await expectPersonaError(
      fixture.testBackend
        .withIdentity(teammateIdentity)
        .query(api.personaRecords.listOwnedVersions, {
          personaId: fixture.personaId,
          paginationOpts: { cursor: null, numItems: 10 },
        }),
      "UNAUTHORIZED",
    );
    const versions = await fixture.ownerBackend.query(
      api.personaRecords.listOwnedVersions,
      {
        personaId: fixture.personaId,
        paginationOpts: { cursor: null, numItems: 1 },
      },
    );
    expect(versions.page).toHaveLength(1);
    expect(versions.page[0].versionNumber).toBe(2);
    expect(versions.isDone).toBe(false);
    const stored = await fixture.testBackend.run(
      async (ctx) => await ctx.db.get("personaVersions", versions.page[0]._id),
    );
    expect(stored).toEqual(versions.page[0]);
  });

  test("allows one concurrent interpretation and rolls the loser back", async () => {
    const fixture = await provisionOwner();
    const session = await fixture.ownerBackend.mutation(
      api.personaOnboarding.startOrResume,
      {
        personaId: fixture.personaId,
        clientMutationId: "start",
        expectedSessionRevision: 0,
      },
    );
    const turn = await fixture.ownerBackend.mutation(
      api.personaOnboarding.appendOwnerTurn,
      {
        sessionId: session.sessionId,
        expectedSessionRevision: 0,
        turnId: "concurrent-answer",
        clientMutationId: "append-concurrent",
        inputMode: "text",
        text: "I build secure collaboration software.",
      },
    );
    const attempts = await Promise.allSettled(
      ["interpret-a", "interpret-b"].map(
        async (clientMutationId) =>
          await fixture.ownerBackend.mutation(
            api.personaOnboarding.applyOwnerTurnInterpretation,
            {
              sessionId: session.sessionId,
              sourceTurnId: turn._id,
              expectedSessionRevision: 1,
              expectedPersonaVersion: 0,
              clientMutationId,
              changes: [
                {
                  operation: "create",
                  content: {
                    kind: "work_context",
                    statement: "Builds secure collaboration software",
                  },
                  evidenceExcerpt: "secure collaboration software",
                  confidence: 1,
                },
              ],
            },
          ),
      ),
    );
    expect(
      attempts.filter((attempt) => attempt.status === "fulfilled"),
    ).toHaveLength(1);
    expect(
      attempts.filter((attempt) => attempt.status === "rejected"),
    ).toHaveLength(1);
    const state = await fixture.ownerBackend.query(
      api.personaOnboarding.getOwnedState,
      { personaId: fixture.personaId },
    );
    expect(state.currentVersion).toBe(1);
    expect(state.currentRecords).toHaveLength(1);
  });

  test("rejects controls, oversized answers, and excessive operations without writes", async () => {
    const fixture = await provisionOwner();
    const session = await fixture.ownerBackend.mutation(
      api.personaOnboarding.startOrResume,
      {
        personaId: fixture.personaId,
        clientMutationId: "start",
        expectedSessionRevision: 0,
      },
    );
    for (const text of ["contains\ncontrol", "x".repeat(2_001)]) {
      await expectPersonaError(
        fixture.ownerBackend.mutation(
          api.personaOnboarding.appendOwnerTurn,
          {
            sessionId: session.sessionId,
            expectedSessionRevision: 0,
            turnId: `invalid-${text.length}`,
            clientMutationId: `invalid-mutation-${text.length}`,
            inputMode: "text",
            text,
          },
        ),
        "INVALID_REQUEST",
      );
    }
    const turn = await fixture.ownerBackend.mutation(
      api.personaOnboarding.appendOwnerTurn,
      {
        sessionId: session.sessionId,
        expectedSessionRevision: 0,
        turnId: "bounded-answer",
        clientMutationId: "bounded-append",
        inputMode: "text",
        text: "I build tools.",
      },
    );
    await expectPersonaError(
      fixture.ownerBackend.mutation(
        api.personaOnboarding.applyOwnerTurnInterpretation,
        {
          sessionId: session.sessionId,
          sourceTurnId: turn._id,
          expectedSessionRevision: 1,
          expectedPersonaVersion: 0,
          clientMutationId: "too-many-changes",
          changes: Array.from({ length: 9 }, () => ({
            operation: "create" as const,
            content: { kind: "work_context" as const, statement: "Builds tools" },
            evidenceExcerpt: "build tools",
            confidence: 1,
          })),
        },
      ),
      "INVALID_REQUEST",
    );
    const state = await fixture.ownerBackend.query(
      api.personaOnboarding.getOwnedState,
      { personaId: fixture.personaId },
    );
    expect(state.currentVersion).toBe(0);
    expect(state.currentRecords).toEqual([]);
  });

  test("binds idempotent versions to exact normalized operations and source turns", async () => {
    const fixture = await activatePersona();
    const created = await fixture.ownerBackend.mutation(
      api.personaRecords.applyOwnedChanges,
      {
        personaId: fixture.personaId,
        expectedPersonaVersion: fixture.state.versionNumber,
        clientMutationId: "manual-fingerprint",
        changes: [
          {
            operation: "create",
            content: { kind: "expertise", statement: "Distributed systems" },
            confidence: 0.9,
          },
        ],
      },
    );
    const beforeConflict = await fixture.testBackend.run(async (ctx) => ({
      versions: await ctx.db.query("personaVersions").take(20),
      records: await ctx.db.query("personaRecords").take(20),
    }));
    await expectPersonaError(
      fixture.ownerBackend.mutation(api.personaRecords.applyOwnedChanges, {
        personaId: fixture.personaId,
        expectedPersonaVersion: fixture.state.versionNumber,
        clientMutationId: "manual-fingerprint",
        changes: [
          {
            operation: "create",
            content: { kind: "expertise", statement: "Different expertise" },
            confidence: 0.9,
          },
        ],
      }),
      "IDEMPOTENCY_CONFLICT",
    );
    await expectPersonaError(
      fixture.ownerBackend.mutation(api.personaRecords.applyOwnedChanges, {
        personaId: fixture.personaId,
        expectedPersonaVersion: created.versionNumber,
        clientMutationId: "interpret-work",
        changes: [
          {
            operation: "create",
            content: { kind: "expertise", statement: "Cross operation" },
            confidence: 1,
          },
        ],
      }),
      "IDEMPOTENCY_CONFLICT",
    );

    const turn = await fixture.ownerBackend.mutation(
      api.personaOnboarding.appendOwnerTurn,
      {
        sessionId: fixture.sessionId,
        expectedSessionRevision: fixture.state.sessionRevision,
        turnId: "different-source-turn",
        clientMutationId: "append-different-source",
        inputMode: "text",
        text: "I also review infrastructure.",
      },
    );
    await expectPersonaError(
      fixture.ownerBackend.mutation(
        api.personaOnboarding.applyOwnerTurnInterpretation,
        {
          sessionId: fixture.sessionId,
          sourceTurnId: turn._id,
          expectedSessionRevision: fixture.state.sessionRevision + 1,
          expectedPersonaVersion: created.versionNumber,
          clientMutationId: "interpret-work",
          changes: [
            {
              operation: "create",
              content: { kind: "expertise", statement: "Reviews infrastructure" },
              evidenceExcerpt: "review infrastructure",
              confidence: 1,
            },
          ],
        },
      ),
      "IDEMPOTENCY_CONFLICT",
    );
    const afterConflict = await fixture.testBackend.run(async (ctx) => ({
      versions: await ctx.db.query("personaVersions").take(20),
      records: await ctx.db.query("personaRecords").take(20),
      turn: await ctx.db.get("personaOnboardingTurns", turn._id),
    }));
    expect(afterConflict.versions).toEqual(beforeConflict.versions);
    expect(afterConflict.records).toEqual(beforeConflict.records);
    expect(afterConflict.turn?.interpretationStatus).toBe("pending");
  });

  test("uses immutable session receipts across delayed and cross-operation retries", async () => {
    const fixture = await activatePersona();
    const paused = await fixture.ownerBackend.mutation(
      api.personaOnboarding.pause,
      {
        sessionId: fixture.sessionId,
        expectedSessionRevision: fixture.state.sessionRevision,
        reason: "skippedForNow",
        clientMutationId: "pause-receipt",
      },
    );
    const delayedStart = await fixture.ownerBackend.mutation(
      api.personaOnboarding.startOrResume,
      {
        personaId: fixture.personaId,
        expectedSessionRevision: 0,
        clientMutationId: "start-session",
      },
    );
    expect(delayedStart).toMatchObject({ status: "active", revision: 0 });
    const stillPaused = await fixture.ownerBackend.query(
      api.personaOnboarding.getOwnedState,
      { personaId: fixture.personaId },
    );
    expect(stillPaused.session).toMatchObject({
      status: "paused",
      revision: paused.revision,
    });
    await expectPersonaError(
      fixture.ownerBackend.mutation(api.personaOnboarding.startOrResume, {
        personaId: fixture.personaId,
        expectedSessionRevision: paused.revision,
        clientMutationId: "pause-receipt",
      }),
      "IDEMPOTENCY_CONFLICT",
    );
    await expectPersonaError(
      fixture.ownerBackend.mutation(api.personaOnboarding.startOrResume, {
        personaId: fixture.personaId,
        expectedSessionRevision: 0,
        clientMutationId: "new-delayed-start",
      }),
      "REVISION_CONFLICT",
    );
  });

  test("fingerprints active no-op receipts for exact and cross-operation replay", async () => {
    const fixture = await activatePersona();
    const args = {
      personaId: fixture.personaId,
      expectedSessionRevision: fixture.state.sessionRevision,
      clientMutationId: "active-noop-receipt",
    };
    const first = await fixture.ownerBackend.mutation(
      api.personaOnboarding.startOrResume,
      args,
    );
    const retry = await fixture.ownerBackend.mutation(
      api.personaOnboarding.startOrResume,
      args,
    );
    expect(retry).toEqual(first);
    const receipts = await fixture.testBackend.run(
      async (ctx) =>
        await ctx.db
          .query("personaSessionOperationReceipts")
          .withIndex("by_sessionId_and_clientMutationId", (query) =>
            query
              .eq("sessionId", fixture.sessionId)
              .eq("clientMutationId", args.clientMutationId),
          )
          .take(2),
    );
    expect(receipts).toHaveLength(1);
    expect(receipts[0]).toMatchObject({
      operation: "resume",
      resultStatus: "active",
      resultRevision: fixture.state.sessionRevision,
    });
    expect(receipts[0].requestFingerprint).toMatch(/^[0-9a-f]{64}$/);

    await expectPersonaError(
      fixture.ownerBackend.mutation(api.personaOnboarding.pause, {
        sessionId: fixture.sessionId,
        expectedSessionRevision: fixture.state.sessionRevision,
        reason: "userPaused",
        clientMutationId: args.clientMutationId,
      }),
      "IDEMPOTENCY_CONFLICT",
    );
    const state = await fixture.ownerBackend.query(
      api.personaOnboarding.getOwnedState,
      { personaId: fixture.personaId },
    );
    expect(state.session?.status).toBe("active");
  });

  test("reserves terminal receipt capacity from active sessions", async () => {
    const fixture = await activatePersona();
    await fillSessionReceipts(
      fixture.testBackend,
      fixture.personaId,
      fixture.sessionId,
      "active",
    );

    await expectPersonaError(
      fixture.ownerBackend.mutation(api.personaOnboarding.startOrResume, {
        personaId: fixture.personaId,
        expectedSessionRevision: fixture.state.sessionRevision,
        clientMutationId: "capacity-active-noop",
      }),
      "INVALID_REQUEST",
    );
    const countAfterNoOp = await fixture.testBackend.run(
      async (ctx) =>
        (
          await ctx.db
            .query("personaSessionOperationReceipts")
            .withIndex("by_sessionId_and_clientMutationId", (query) =>
              query.eq("sessionId", fixture.sessionId),
            )
            .take(maximumSessionOperationReceipts)
        ).length,
    );
    expect(countAfterNoOp).toBe(maximumNonterminalSessionOperationReceipts);

    await expectPersonaError(
      fixture.ownerBackend.mutation(api.personaOnboarding.pause, {
        sessionId: fixture.sessionId,
        expectedSessionRevision: fixture.state.sessionRevision,
        reason: "userPaused",
        clientMutationId: "capacity-active-pause",
      }),
      "INVALID_REQUEST",
    );
    const completed = await fixture.ownerBackend.mutation(
      api.personaOnboarding.complete,
      {
        sessionId: fixture.sessionId,
        expectedSessionRevision: fixture.state.sessionRevision,
        clientMutationId: "capacity-active-complete",
      },
    );
    expect(completed.status).toBe("completed");
    await expect(
      fixture.ownerBackend.mutation(api.personaOnboarding.complete, {
        sessionId: fixture.sessionId,
        expectedSessionRevision: fixture.state.sessionRevision,
        clientMutationId: "capacity-active-complete",
      }),
    ).resolves.toEqual(completed);
  });

  test("reserves terminal receipt capacity from paused sessions", async () => {
    const fixture = await activatePersona();
    const paused = await fixture.ownerBackend.mutation(
      api.personaOnboarding.pause,
      {
        sessionId: fixture.sessionId,
        expectedSessionRevision: fixture.state.sessionRevision,
        reason: "skippedForNow",
        clientMutationId: "capacity-paused-initial",
      },
    );
    await fillSessionReceipts(
      fixture.testBackend,
      fixture.personaId,
      fixture.sessionId,
      "paused",
    );

    await expectPersonaError(
      fixture.ownerBackend.mutation(api.personaOnboarding.startOrResume, {
        personaId: fixture.personaId,
        expectedSessionRevision: paused.revision,
        clientMutationId: "capacity-paused-resume",
      }),
      "INVALID_REQUEST",
    );
    const state = await fixture.ownerBackend.query(
      api.personaOnboarding.getOwnedState,
      { personaId: fixture.personaId },
    );
    expect(state.session).toMatchObject({
      status: "paused",
      revision: paused.revision,
    });
    const completed = await fixture.ownerBackend.mutation(
      api.personaOnboarding.complete,
      {
        sessionId: fixture.sessionId,
        expectedSessionRevision: paused.revision,
        clientMutationId: "capacity-paused-complete",
      },
    );
    expect(completed.status).toBe("completed");
    const receiptCount = await fixture.testBackend.run(
      async (ctx) =>
        (
          await ctx.db
            .query("personaSessionOperationReceipts")
            .withIndex("by_sessionId_and_clientMutationId", (query) =>
              query.eq("sessionId", fixture.sessionId),
            )
            .take(maximumSessionOperationReceipts + 1)
        ).length,
    );
    expect(receiptCount).toBe(maximumSessionOperationReceipts);
  });

  test("fails closed and rolls back when current child relationships are corrupted", async () => {
    const fixture = await activatePersona();
    const corruptedRecordId = await fixture.testBackend.run(async (ctx) => {
      const record = await ctx.db
        .query("personaRecords")
        .withIndex(
          "by_personaId_and_isCurrent_and_state_and_kind",
          (query) =>
            query
              .eq("personaId", fixture.personaId)
              .eq("isCurrent", true)
              .eq("state", "active")
              .eq("kind", "work_context"),
        )
        .unique();
      if (record === null) {
        throw new Error("Missing current record");
      }
      const unrelatedProfileId = await ctx.db.insert("profiles", {
        tokenIdentifier: "https://issuer.example|corruption",
        displayName: "Corruption",
        accountSettings: {},
        lifecycleStatus: "active",
        createdAt: Date.now(),
        updatedAt: Date.now(),
      });
      const unrelatedWorkspaceId = await ctx.db.insert("workspaces", {
        kind: "personal",
        name: "Unrelated",
        createdByProfileId: unrelatedProfileId,
        lifecycleStatus: "active",
        createdAt: Date.now(),
        updatedAt: Date.now(),
      });
      await ctx.db.patch("personaRecords", record._id, {
        workspaceId: unrelatedWorkspaceId,
      });
      return record._id;
    });
    await expectPersonaError(
      fixture.ownerBackend.query(api.personaOnboarding.getOwnedState, {
        personaId: fixture.personaId,
      }),
      "DATA_INTEGRITY",
    );
    const before = await fixture.testBackend.run(
      async (ctx) => await ctx.db.query("personaVersions").take(20),
    );
    await expectPersonaError(
      fixture.ownerBackend.mutation(api.personaRecords.applyOwnedChanges, {
        personaId: fixture.personaId,
        expectedPersonaVersion: fixture.state.versionNumber,
        clientMutationId: "write-after-corruption",
        changes: [
          {
            operation: "create",
            content: { kind: "expertise", statement: "Must not commit" },
            confidence: 1,
          },
        ],
      }),
      "DATA_INTEGRITY",
    );
    const after = await fixture.testBackend.run(
      async (ctx) => await ctx.db.query("personaVersions").take(20),
    );
    expect(after).toEqual(before);
    expect(corruptedRecordId).toBeDefined();
  });

  test("direct session IDs do not reveal missing or foreign resources", async () => {
    const ownerFixture = await provisionOwner();
    const ownerSession = await ownerFixture.ownerBackend.mutation(
      api.personaOnboarding.startOrResume,
      {
        personaId: ownerFixture.personaId,
        expectedSessionRevision: 0,
        clientMutationId: "owner-start",
      },
    );
    const foreignBackend = ownerFixture.testBackend.withIdentity(teammateIdentity);
    const foreignProvisioned = await foreignBackend.mutation(
      api.accounts.provisionCurrent,
    );
    const foreignSession = await foreignBackend.mutation(
      api.personaOnboarding.startOrResume,
      {
        personaId: foreignProvisioned.snapshot.personaId,
        expectedSessionRevision: 0,
        clientMutationId: "foreign-start",
      },
    );
    await expectPersonaError(
      ownerFixture.ownerBackend.query(api.personaOnboarding.listOwnedTurns, {
        sessionId: foreignSession.sessionId,
        paginationOpts: { cursor: null, numItems: 10 },
      }),
      "RESOURCE_UNAVAILABLE",
    );
    await ownerFixture.testBackend.run(async (ctx) => {
      await ctx.db.delete(
        "personaOnboardingSessions",
        foreignSession.sessionId,
      );
    });
    await expectPersonaError(
      ownerFixture.ownerBackend.query(api.personaOnboarding.listOwnedTurns, {
        sessionId: foreignSession.sessionId,
        paginationOpts: { cursor: null, numItems: 10 },
      }),
      "RESOURCE_UNAVAILABLE",
    );
    await expectPersonaError(
      ownerFixture.testBackend.query(api.personaOnboarding.listOwnedTurns, {
        sessionId: ownerSession.sessionId,
        paginationOpts: { cursor: null, numItems: 10 },
      }),
      "UNAUTHENTICATED",
    );
  });

  test("direct summary IDs authenticate before normalized resource denial", async () => {
    const fixture = await activatePersona();
    const boundaryVersion = await fixture.ownerBackend.mutation(
      api.personaRecords.applyOwnedChanges,
      {
        personaId: fixture.personaId,
        expectedPersonaVersion: fixture.state.versionNumber,
        clientMutationId: "oracle-boundary",
        changes: [
          {
            operation: "create",
            content: {
              kind: "boundary",
              mode: "ask_first",
              statement: "Ask before external sharing",
            },
            confidence: 1,
          },
        ],
      },
    );
    const draft = await fixture.ownerBackend.mutation(
      api.personaBoundarySummaries.saveOwnedDraft,
      {
        personaId: fixture.personaId,
        expectedPersonaVersion: boundaryVersion.versionNumber,
        clientMutationId: "oracle-draft",
        summaryText: "Ask before sharing externally.",
      },
    );
    await expectPersonaError(
      fixture.testBackend.mutation(
        api.personaBoundarySummaries.discardOwnedDraft,
        { summaryId: draft.summaryId },
      ),
      "UNAUTHENTICATED",
    );
    await fixture.testBackend
      .withIdentity(teammateIdentity)
      .mutation(api.accounts.provisionCurrent);
    await expectPersonaError(
      fixture.testBackend
        .withIdentity(teammateIdentity)
        .mutation(api.personaBoundarySummaries.discardOwnedDraft, {
          summaryId: draft.summaryId,
        }),
      "RESOURCE_UNAVAILABLE",
    );
    await fixture.testBackend.run(async (ctx) => {
      await ctx.db.delete("personaBoundarySummaries", draft.summaryId);
    });
    await expectPersonaError(
      fixture.ownerBackend.mutation(
        api.personaBoundarySummaries.discardOwnedDraft,
        { summaryId: draft.summaryId },
      ),
      "RESOURCE_UNAVAILABLE",
    );
  });
});
