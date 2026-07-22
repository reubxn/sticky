import { v } from "convex/values";

import { internal } from "./_generated/api";
import { internalMutation } from "./_generated/server";
import { workerRequestDailyQuotaWindowMs } from "./workerRequestPolicy";

export const workerRequestCleanupBatchSize = 50;

const cleanupResultValidator = v.object({
  deletedCount: v.number(),
  scheduledContinuation: v.boolean(),
});

type CleanupResult = {
  deletedCount: number;
  scheduledContinuation: boolean;
};

export const cleanupIssuedTickets = internalMutation({
  args: {
    cutoff: v.optional(v.number()),
  },
  returns: cleanupResultValidator,
  handler: async (ctx, args): Promise<CleanupResult> => {
    const cutoff = args.cutoff ?? Date.now();
    const issuedRetentionCutoff =
      cutoff - workerRequestDailyQuotaWindowMs;
    const tickets = await ctx.db
      .query("workerRequestTickets")
      .withIndex("by_status_and_expiresAt", (indexQuery) =>
        indexQuery
          .eq("status", "issued")
          .lte("expiresAt", issuedRetentionCutoff),
      )
      .take(workerRequestCleanupBatchSize);

    for (const ticket of tickets) {
      await ctx.db.delete("workerRequestTickets", ticket._id);
    }

    const scheduledContinuation =
      tickets.length === workerRequestCleanupBatchSize;
    if (scheduledContinuation) {
      await ctx.scheduler.runAfter(
        0,
        internal.workerRequestTicketCleanup.cleanupIssuedTickets,
        { cutoff },
      );
    }
    return { deletedCount: tickets.length, scheduledContinuation };
  },
});

export const cleanupConsumedTickets = internalMutation({
  args: {
    cutoff: v.optional(v.number()),
  },
  returns: cleanupResultValidator,
  handler: async (ctx, args): Promise<CleanupResult> => {
    const cutoff = args.cutoff ?? Date.now();
    const tickets = await ctx.db
      .query("workerRequestTickets")
      .withIndex("by_status_and_purgeEligibleAt", (indexQuery) =>
        indexQuery
          .eq("status", "consumed")
          .gte("purgeEligibleAt", 0)
          .lte("purgeEligibleAt", cutoff),
      )
      .take(workerRequestCleanupBatchSize);

    for (const ticket of tickets) {
      await ctx.db.delete("workerRequestTickets", ticket._id);
    }

    const scheduledContinuation =
      tickets.length === workerRequestCleanupBatchSize;
    if (scheduledContinuation) {
      await ctx.scheduler.runAfter(
        0,
        internal.workerRequestTicketCleanup.cleanupConsumedTickets,
        { cutoff },
      );
    }
    return { deletedCount: tickets.length, scheduledContinuation };
  },
});

export const cleanupAudits = internalMutation({
  args: {
    cutoff: v.optional(v.number()),
  },
  returns: cleanupResultValidator,
  handler: async (ctx, args): Promise<CleanupResult> => {
    const cutoff = args.cutoff ?? Date.now();
    const audits = await ctx.db
      .query("workerRequestAudits")
      .withIndex("by_retentionExpiresAt", (indexQuery) =>
        indexQuery.lte("retentionExpiresAt", cutoff),
      )
      .take(workerRequestCleanupBatchSize);

    for (const audit of audits) {
      await ctx.db.delete("workerRequestAudits", audit._id);
    }

    const scheduledContinuation =
      audits.length === workerRequestCleanupBatchSize;
    if (scheduledContinuation) {
      await ctx.scheduler.runAfter(
        0,
        internal.workerRequestTicketCleanup.cleanupAudits,
        { cutoff },
      );
    }
    return { deletedCount: audits.length, scheduledContinuation };
  },
});
