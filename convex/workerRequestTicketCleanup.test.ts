/// <reference types="vite/client" />

import { convexTest } from "convex-test";
import { describe, expect, test, vi } from "vitest";

import { internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import schema from "./schema";
import {
  consumedTicketMinimumRetentionMs,
  sanitizedAuditRetentionMs,
  workerRequestDailyQuotaWindowMs,
} from "./workerRequestPolicy";
import { workerRequestCleanupBatchSize } from "./workerRequestTicketCleanup";

const modules = import.meta.glob("./**/*.ts");

async function seedCleanupGraph() {
  const testBackend = convexTest(schema, modules);
  const ids = await testBackend.run(async (ctx) => {
    const timestamp = 1_700_000_000_000;
    const profileId = await ctx.db.insert("profiles", {
      tokenIdentifier: "https://issuer.example|cleanup",
      displayName: "Cleanup",
      accountSettings: {},
      lifecycleStatus: "active",
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    const workspaceId = await ctx.db.insert("workspaces", {
      kind: "personal",
      name: "Cleanup",
      createdByProfileId: profileId,
      lifecycleStatus: "active",
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    const membershipId = await ctx.db.insert("workspaceMembers", {
      workspaceId,
      userId: profileId,
      role: "owner",
      status: "active",
      joinedAt: timestamp,
    });
    const personaId = await ctx.db.insert("personas", {
      membershipId,
      workspaceId,
      ownerUserId: profileId,
      status: "active",
      displayName: "Cleanup",
      setupState: "notStarted",
      currentVersion: 0,
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    return { membershipId, personaId, profileId, workspaceId };
  });
  return { ids, testBackend };
}

describe("Worker request ticket cleanup", () => {
  test("preserves early rows and independently removes eligible tickets and audits", async () => {
    const { ids, testBackend } = await seedCleanupGraph();
    const cutoff = 2_000_000_000_000;
    const seeded = await testBackend.run(async (ctx) => {
      let sequence = 0;
      async function insertTicket(
        status: "issued" | "consumed",
        issuedAt: number,
        expiresAt: number,
        purgeEligibleAt?: number,
      ) {
        sequence += 1;
        const ticketFields = {
          ticketDigest: sequence.toString(16).padStart(64, "0"),
          scope: "onboarding_chat",
          requestBodyDigest: "a".repeat(64),
          requestBodyByteCount: 2,
          actorProfileId: ids.profileId,
          workspaceId: ids.workspaceId,
          membershipId: ids.membershipId,
          personaId: ids.personaId,
          policyVersion: 1,
          issuedAt,
          expiresAt,
        } as const;
        if (status === "issued") {
          return await ctx.db.insert("workerRequestTickets", {
            ...ticketFields,
            status: "issued",
          });
        }
        if (purgeEligibleAt === undefined) {
          throw new Error("Consumed cleanup fixture requires retention");
        }
        return await ctx.db.insert("workerRequestTickets", {
          ...ticketFields,
          status: "consumed",
          consumedAt:
            purgeEligibleAt - consumedTicketMinimumRetentionMs,
          consumptionId: "consumed",
          workerRequestId: "worker_request_cleanup",
          purgeEligibleAt,
        });
      }

      const earlyIssuedTicketId = await insertTicket(
        "issued",
        cutoff - workerRequestDailyQuotaWindowMs - 29_999,
        cutoff - workerRequestDailyQuotaWindowMs + 1,
      );
      const eligibleIssuedTicketId = await insertTicket(
        "issued",
        cutoff - workerRequestDailyQuotaWindowMs - 30_000,
        cutoff - workerRequestDailyQuotaWindowMs,
      );
      const earlyConsumedTicketId = await insertTicket(
        "consumed",
        cutoff - consumedTicketMinimumRetentionMs,
        cutoff - consumedTicketMinimumRetentionMs + 30_000,
        cutoff + 1,
      );
      const eligibleConsumedTicketId = await insertTicket(
        "consumed",
        cutoff - consumedTicketMinimumRetentionMs - 1,
        cutoff - consumedTicketMinimumRetentionMs + 29_999,
        cutoff,
      );

      async function insertAudit(
        ticketId: Id<"workerRequestTickets">,
        retentionExpiresAt: number,
      ) {
        return await ctx.db.insert("workerRequestAudits", {
          ticketId,
          scope: "onboarding_chat",
          actorProfileId: ids.profileId,
          workspaceId: ids.workspaceId,
          membershipId: ids.membershipId,
          personaId: ids.personaId,
          policyVersion: 1,
          status: "issued",
          issuedAt: cutoff - sanitizedAuditRetentionMs,
          retentionExpiresAt,
        });
      }
      const retainedAuditForDeletedTicketId = await insertAudit(
        eligibleIssuedTicketId,
        cutoff + 1,
      );
      const eligibleAuditForRetainedTicketId = await insertAudit(
        earlyIssuedTicketId,
        cutoff,
      );

      return {
        earlyConsumedTicketId,
        earlyIssuedTicketId,
        eligibleAuditForRetainedTicketId,
        eligibleConsumedTicketId,
        eligibleIssuedTicketId,
        retainedAuditForDeletedTicketId,
      };
    });

    await expect(
      testBackend.mutation(
        internal.workerRequestTicketCleanup.cleanupIssuedTickets,
        { cutoff },
      ),
    ).resolves.toEqual({ deletedCount: 1, scheduledContinuation: false });
    await expect(
      testBackend.mutation(
        internal.workerRequestTicketCleanup.cleanupConsumedTickets,
        { cutoff },
      ),
    ).resolves.toEqual({ deletedCount: 1, scheduledContinuation: false });
    await expect(
      testBackend.mutation(
        internal.workerRequestTicketCleanup.cleanupAudits,
        { cutoff },
      ),
    ).resolves.toEqual({ deletedCount: 1, scheduledContinuation: false });

    const remaining = await testBackend.run(async (ctx) => ({
      earlyConsumed: await ctx.db.get(
        "workerRequestTickets",
        seeded.earlyConsumedTicketId,
      ),
      earlyIssued: await ctx.db.get(
        "workerRequestTickets",
        seeded.earlyIssuedTicketId,
      ),
      eligibleConsumed: await ctx.db.get(
        "workerRequestTickets",
        seeded.eligibleConsumedTicketId,
      ),
      eligibleIssued: await ctx.db.get(
        "workerRequestTickets",
        seeded.eligibleIssuedTicketId,
      ),
      eligibleAudit: await ctx.db.get(
        "workerRequestAudits",
        seeded.eligibleAuditForRetainedTicketId,
      ),
      retainedAudit: await ctx.db.get(
        "workerRequestAudits",
        seeded.retainedAuditForDeletedTicketId,
      ),
    }));
    expect(remaining.earlyIssued).not.toBeNull();
    expect(remaining.earlyConsumed).not.toBeNull();
    expect(remaining.eligibleIssued).toBeNull();
    expect(remaining.eligibleConsumed).toBeNull();
    expect(remaining.eligibleAudit).toBeNull();
    expect(remaining.retainedAudit).not.toBeNull();
  });

  test("schedules bounded continuation when a full batch remains", async () => {
    const { ids, testBackend } = await seedCleanupGraph();
    const cutoff = 2_000_000_000_000;
    await testBackend.run(async (ctx) => {
      for (
        let index = 0;
        index < workerRequestCleanupBatchSize + 1;
        index += 1
      ) {
        await ctx.db.insert("workerRequestTickets", {
          ticketDigest: (index + 1).toString(16).padStart(64, "0"),
          scope: "onboarding_chat",
          requestBodyDigest: "a".repeat(64),
          requestBodyByteCount: 2,
          actorProfileId: ids.profileId,
          workspaceId: ids.workspaceId,
          membershipId: ids.membershipId,
          personaId: ids.personaId,
          policyVersion: 1,
          issuedAt:
            cutoff - workerRequestDailyQuotaWindowMs - 30_001 - index,
          expiresAt:
            cutoff - workerRequestDailyQuotaWindowMs - 1 - index,
          status: "issued",
        });
      }
    });

    vi.useFakeTimers();
    try {
      await expect(
        testBackend.mutation(
          internal.workerRequestTicketCleanup.cleanupIssuedTickets,
          { cutoff },
        ),
      ).resolves.toEqual({
        deletedCount: workerRequestCleanupBatchSize,
        scheduledContinuation: true,
      });
      await testBackend.finishAllScheduledFunctions(() => vi.runAllTimers());
    } finally {
      vi.useRealTimers();
    }
    const remaining = await testBackend.run(
      async (ctx) =>
        await ctx.db
          .query("workerRequestTickets")
          .withIndex("by_status_and_expiresAt", (query) =>
            query.eq("status", "issued"),
          )
          .take(2),
    );
    expect(remaining).toHaveLength(0);
  });
});
