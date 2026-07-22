/// <reference types="vite/client" />

import { convexTest } from "convex-test";
import type { TestConvexForDataModel } from "convex-test";
import { ConvexError } from "convex/values";
import { describe, expect, test } from "vitest";

import { api } from "./_generated/api";
import type { DataModel, Id } from "./_generated/dataModel";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");
const timestamp = 1_700_000_000_000;
type TestBackend = TestConvexForDataModel<DataModel>;

const primaryIdentity = {
  subject: "primary",
  issuer: "https://issuer.example",
  tokenIdentifier: "https://issuer.example|primary",
  name: "Primary User",
  email: "primary@example.com",
  pictureUrl: "https://example.com/primary.png",
};

const otherIdentity = {
  subject: "other",
  issuer: "https://issuer.example",
  tokenIdentifier: "https://issuer.example|other",
  name: "Other User",
  email: "other@example.com",
};

async function expectConvexError(
  operation: Promise<unknown>,
  code: "UNAUTHENTICATED" | "DATA_INTEGRITY" | "ACCOUNT_DELETION_PENDING",
) {
  try {
    await operation;
    expect.fail("Expected Convex operation to fail");
  } catch (error) {
    expect(error).toBeInstanceOf(ConvexError);
    if (!(error instanceof ConvexError)) {
      throw error;
    }
    expect(error.data).toMatchObject({ code });
  }
}

async function databaseCounts(
  testBackend: TestBackend,
): Promise<Record<string, number>> {
  return await testBackend.run(async (ctx) => ({
    profiles: (await ctx.db.query("profiles").collect()).length,
    workspaces: (await ctx.db.query("workspaces").collect()).length,
    memberships: (await ctx.db.query("workspaceMembers").collect()).length,
    personas: (await ctx.db.query("personas").collect()).length,
  }));
}

async function databaseState(testBackend: TestBackend) {
  return await testBackend.run(async (ctx) => ({
    profiles: await ctx.db.query("profiles").collect(),
    workspaces: await ctx.db.query("workspaces").collect(),
    memberships: await ctx.db.query("workspaceMembers").collect(),
    personas: await ctx.db.query("personas").collect(),
  }));
}

async function insertProfile(
  testBackend: TestBackend,
  overrides: Partial<{
    tokenIdentifier: string;
    displayName: string;
    email: string;
    avatarUrl: string;
    lifecycleStatus: "active" | "deletionPending";
    deletionRequestedAt: number;
    deletionScheduledFor: number;
  }> = {},
) {
  return await testBackend.run(async (ctx) => {
    return await ctx.db.insert("profiles", {
      tokenIdentifier:
        overrides.tokenIdentifier ?? primaryIdentity.tokenIdentifier,
      displayName: overrides.displayName ?? "Stored Name",
      email: overrides.email,
      avatarUrl: overrides.avatarUrl,
      accountSettings: {},
      lifecycleStatus: overrides.lifecycleStatus ?? "active",
      deletionRequestedAt: overrides.deletionRequestedAt,
      deletionScheduledFor: overrides.deletionScheduledFor,
      createdAt: timestamp,
      updatedAt: timestamp,
    });
  });
}

async function insertWorkspace(
  testBackend: TestBackend,
  profileId: Id<"profiles">,
  overrides: Partial<{
    name: string;
    lifecycleStatus: "active" | "deleting";
  }> = {},
) {
  return await testBackend.run(async (ctx) => {
    return await ctx.db.insert("workspaces", {
      kind: "personal",
      name: overrides.name ?? "Stored Workspace",
      createdByProfileId: profileId,
      lifecycleStatus: overrides.lifecycleStatus ?? "active",
      createdAt: timestamp,
      updatedAt: timestamp,
    });
  });
}

async function insertMembership(
  testBackend: TestBackend,
  profileId: Id<"profiles">,
  workspaceId: Id<"workspaces">,
  overrides: Partial<{
    userId: Id<"profiles">;
    workspaceId: Id<"workspaces">;
    role: "owner" | "admin" | "member";
    status: "active" | "removed";
  }> = {},
) {
  return await testBackend.run(async (ctx) => {
    return await ctx.db.insert("workspaceMembers", {
      workspaceId: overrides.workspaceId ?? workspaceId,
      userId: overrides.userId ?? profileId,
      role: overrides.role ?? "owner",
      status: overrides.status ?? "active",
      joinedAt: timestamp,
      removedAt: overrides.status === "removed" ? timestamp + 1 : undefined,
    });
  });
}

async function insertPersona(
  testBackend: TestBackend,
  profileId: Id<"profiles">,
  workspaceId: Id<"workspaces">,
  membershipId: Id<"workspaceMembers">,
  overrides: Partial<{
    ownerUserId: Id<"profiles">;
    workspaceId: Id<"workspaces">;
    membershipId: Id<"workspaceMembers">;
    status: "active" | "removing";
  }> = {},
) {
  return await testBackend.run(async (ctx) => {
    return await ctx.db.insert("personas", {
      membershipId: overrides.membershipId ?? membershipId,
      workspaceId: overrides.workspaceId ?? workspaceId,
      ownerUserId: overrides.ownerUserId ?? profileId,
      status: overrides.status ?? "active",
      displayName: "Stored Persona",
      setupState: "notStarted",
      currentVersion: 0,
      createdAt: timestamp,
      updatedAt: timestamp,
    });
  });
}

describe("personal account provisioning", () => {
  test("rejects unauthenticated mutation and query", async () => {
    const testBackend = convexTest(schema, modules);

    await expectConvexError(
      testBackend.mutation(api.accounts.provisionCurrent),
      "UNAUTHENTICATED",
    );
    await expectConvexError(
      testBackend.query(api.accounts.current),
      "UNAUTHENTICATED",
    );
    await expect(databaseCounts(testBackend)).resolves.toEqual({
      profiles: 0,
      workspaces: 0,
      memberships: 0,
      personas: 0,
    });
  });

  test("creates one complete graph and returns it from current", async () => {
    const testBackend = convexTest(schema, modules).withIdentity(primaryIdentity);

    const provisioned = await testBackend.mutation(
      api.accounts.provisionCurrent,
    );

    expect(provisioned.didCreate).toBe(true);
    expect(provisioned.snapshot).toMatchObject({
      profileDisplayName: "Primary User",
      workspaceName: "Primary User's Workspace",
      businessType: null,
      personaDisplayName: "Primary User",
      personaSetupState: "notStarted",
      personaCurrentVersion: 0,
    });
    await expect(testBackend.query(api.accounts.current)).resolves.toEqual({
      status: "ready",
      snapshot: provisioned.snapshot,
    });
    await expect(databaseCounts(testBackend)).resolves.toEqual({
      profiles: 1,
      workspaces: 1,
      memberships: 1,
      personas: 1,
    });
  });

  test("repeated and concurrent calls return stable IDs", async () => {
    const testBackend = convexTest(schema, modules).withIdentity(primaryIdentity);
    const results = await Promise.all(
      Array.from({ length: 20 }, async () =>
        await testBackend.mutation(api.accounts.provisionCurrent),
      ),
    );

    const snapshots = results.map((result) => result.snapshot);
    expect(snapshots.every((snapshot) => snapshot.profileId === snapshots[0].profileId))
      .toBe(true);
    expect(snapshots.every((snapshot) => snapshot.workspaceId === snapshots[0].workspaceId))
      .toBe(true);
    expect(snapshots.every((snapshot) => snapshot.membershipId === snapshots[0].membershipId))
      .toBe(true);
    expect(snapshots.every((snapshot) => snapshot.personaId === snapshots[0].personaId))
      .toBe(true);
    await expect(databaseCounts(testBackend)).resolves.toEqual({
      profiles: 1,
      workspaces: 1,
      memberships: 1,
      personas: 1,
    });
  });

  test("repairs every valid partial prefix", async () => {
    for (const prefixLength of [1, 2, 3]) {
      const testBackend = convexTest(schema, modules);
      const profileId = await insertProfile(testBackend);
      let workspaceId: Id<"workspaces"> | undefined;
      if (prefixLength >= 2) {
        workspaceId = await insertWorkspace(testBackend, profileId);
      }
      if (prefixLength >= 3 && workspaceId !== undefined) {
        await insertMembership(testBackend, profileId, workspaceId);
      }

      const asPrimary = testBackend.withIdentity(primaryIdentity);
      await expect(asPrimary.query(api.accounts.current)).resolves.toEqual({
        status: "needsProvisioning",
      });
      const provisioned = await asPrimary.mutation(
        api.accounts.provisionCurrent,
      );
      expect(provisioned.didCreate).toBe(true);
      expect(provisioned.snapshot.profileId).toBe(profileId);
      if (workspaceId !== undefined) {
        expect(provisioned.snapshot.workspaceId).toBe(workspaceId);
      }
      await expect(databaseCounts(testBackend)).resolves.toEqual({
        profiles: 1,
        workspaces: 1,
        memberships: 1,
        personas: 1,
      });
    }
  });

  test("persona without membership fails current and provisioning without writes", async () => {
    const testBackend = convexTest(schema, modules);
    const asPrimary = testBackend.withIdentity(primaryIdentity);
    const provisioned = await asPrimary.mutation(
      api.accounts.provisionCurrent,
    );
    await testBackend.run(async (ctx) => {
      await ctx.db.delete(
        "workspaceMembers",
        provisioned.snapshot.membershipId,
      );
    });
    const before = await databaseState(testBackend);

    await expectConvexError(
      asPrimary.query(api.accounts.current),
      "DATA_INTEGRITY",
    );
    await expectConvexError(
      asPrimary.mutation(api.accounts.provisionCurrent),
      "DATA_INTEGRITY",
    );
    await expect(databaseState(testBackend)).resolves.toEqual(before);
  });

  test("refreshes only present verified profile claims and preserves edits", async () => {
    const testBackend = convexTest(schema, modules);
    const asPrimary = testBackend.withIdentity(primaryIdentity);
    const first = await asPrimary.mutation(api.accounts.provisionCurrent);
    await testBackend.run(async (ctx) => {
      await ctx.db.patch("workspaces", first.snapshot.workspaceId, {
        name: "Renamed Workspace",
        businessType: "Design",
        updatedAt: timestamp + 10,
      });
      await ctx.db.patch("personas", first.snapshot.personaId, {
        displayName: "Edited Persona",
        setupState: "interview",
        currentVersion: 4,
        updatedAt: timestamp + 11,
      });
    });

    const withoutClaims = testBackend.withIdentity({
      subject: primaryIdentity.subject,
      issuer: primaryIdentity.issuer,
      tokenIdentifier: primaryIdentity.tokenIdentifier,
    });
    const repeated = await withoutClaims.mutation(api.accounts.provisionCurrent);
    expect(repeated.didCreate).toBe(false);
    expect(repeated.snapshot).toMatchObject({
      profileDisplayName: "Primary User",
      workspaceName: "Renamed Workspace",
      businessType: "Design",
      personaDisplayName: "Edited Persona",
      personaSetupState: "interview",
      personaCurrentVersion: 4,
    });
    const preservedClaims = await testBackend.run(
      async (ctx) => await ctx.db.get("profiles", repeated.snapshot.profileId),
    );
    expect(preservedClaims).toMatchObject({
      email: primaryIdentity.email,
      avatarUrl: primaryIdentity.pictureUrl,
    });
    const preservedEdits = await testBackend.run(async (ctx) => ({
      workspace: await ctx.db.get("workspaces", repeated.snapshot.workspaceId),
      persona: await ctx.db.get("personas", repeated.snapshot.personaId),
    }));
    expect(preservedEdits.workspace?.updatedAt).toBe(timestamp + 10);
    expect(preservedEdits.persona?.updatedAt).toBe(timestamp + 11);

    const changedClaims = testBackend.withIdentity({
      ...primaryIdentity,
      name: "Updated User",
      email: "updated@example.com",
      pictureUrl: "https://example.com/updated.png",
    });
    const refreshed = await changedClaims.mutation(api.accounts.provisionCurrent);
    expect(refreshed.snapshot.profileDisplayName).toBe("Updated User");
    expect(refreshed.snapshot.workspaceName).toBe("Renamed Workspace");
    expect(refreshed.snapshot.personaDisplayName).toBe("Edited Persona");
  });

  test("deletion-pending profiles fail without writes", async () => {
    const testBackend = convexTest(schema, modules);
    await insertProfile(testBackend, {
      lifecycleStatus: "deletionPending",
      deletionRequestedAt: timestamp,
      deletionScheduledFor: timestamp + 1,
    });
    const before = await databaseState(testBackend);
    const asPrimary = testBackend.withIdentity(primaryIdentity);

    await expectConvexError(
      asPrimary.mutation(api.accounts.provisionCurrent),
      "ACCOUNT_DELETION_PENDING",
    );
    await expectConvexError(
      asPrimary.query(api.accounts.current),
      "ACCOUNT_DELETION_PENDING",
    );
    await expect(databaseState(testBackend)).resolves.toEqual(before);
  });

  test("duplicate singleton records fail without writes", async () => {
    const scenarios = ["profile", "workspace", "membership", "persona"] as const;
    for (const scenario of scenarios) {
      const testBackend = convexTest(schema, modules);
      const profileId = await insertProfile(testBackend);
      if (scenario === "profile") {
        await insertProfile(testBackend);
      } else {
        const workspaceId = await insertWorkspace(testBackend, profileId);
        if (scenario === "workspace") {
          await insertWorkspace(testBackend, profileId);
        } else {
          const membershipId = await insertMembership(
            testBackend,
            profileId,
            workspaceId,
          );
          if (scenario === "membership") {
            await insertMembership(testBackend, profileId, workspaceId);
          } else {
            await insertPersona(
              testBackend,
              profileId,
              workspaceId,
              membershipId,
            );
            await insertPersona(
              testBackend,
              profileId,
              workspaceId,
              membershipId,
            );
          }
        }
      }

      const before = await databaseState(testBackend);
      await expectConvexError(
        testBackend
          .withIdentity(primaryIdentity)
          .mutation(api.accounts.provisionCurrent),
        "DATA_INTEGRITY",
      );
      await expect(databaseState(testBackend)).resolves.toEqual(before);
    }
  });

  test("inactive and malformed graphs fail closed without repair", async () => {
    const scenarios = [
      "deletingWorkspace",
      "removedMembership",
      "wrongRole",
      "wrongUser",
      "removingPersona",
      "wrongPersonaOwner",
      "wrongPersonaMembership",
    ] as const;

    for (const scenario of scenarios) {
      const testBackend = convexTest(schema, modules);
      const profileId = await insertProfile(testBackend);
      const otherProfileId = await insertProfile(testBackend, {
        tokenIdentifier: otherIdentity.tokenIdentifier,
        displayName: "Other",
      });
      const workspaceId = await insertWorkspace(testBackend, profileId, {
        lifecycleStatus:
          scenario === "deletingWorkspace" ? "deleting" : "active",
      });
      let membershipId: Id<"workspaceMembers"> | undefined;
      if (scenario !== "deletingWorkspace") {
        membershipId = await insertMembership(testBackend, profileId, workspaceId, {
          status: scenario === "removedMembership" ? "removed" : "active",
          role: scenario === "wrongRole" ? "member" : "owner",
          userId: scenario === "wrongUser" ? otherProfileId : profileId,
        });
      }
      if (
        membershipId !== undefined &&
        !["removedMembership", "wrongRole", "wrongUser"].includes(scenario)
      ) {
        let personaMembershipId = membershipId;
        if (scenario === "wrongPersonaMembership") {
          const otherWorkspaceId = await insertWorkspace(
            testBackend,
            otherProfileId,
          );
          personaMembershipId = await insertMembership(
            testBackend,
            otherProfileId,
            otherWorkspaceId,
          );
        }
        await insertPersona(testBackend, profileId, workspaceId, membershipId, {
          status: scenario === "removingPersona" ? "removing" : "active",
          ownerUserId:
            scenario === "wrongPersonaOwner" ? otherProfileId : profileId,
          membershipId: personaMembershipId,
        });
      }

      const before = await databaseState(testBackend);
      await expectConvexError(
        testBackend
          .withIdentity(primaryIdentity)
          .mutation(api.accounts.provisionCurrent),
        "DATA_INTEGRITY",
      );
      await expect(databaseState(testBackend)).resolves.toEqual(before);
    }
  });

  test("separate identities provision isolated graphs without email merging", async () => {
    const testBackend = convexTest(schema, modules);
    const first = await testBackend
      .withIdentity(primaryIdentity)
      .mutation(api.accounts.provisionCurrent);
    const second = await testBackend
      .withIdentity({ ...otherIdentity, email: primaryIdentity.email })
      .mutation(api.accounts.provisionCurrent);

    expect(second.snapshot.profileId).not.toBe(first.snapshot.profileId);
    expect(second.snapshot.workspaceId).not.toBe(first.snapshot.workspaceId);
    await expect(databaseCounts(testBackend)).resolves.toEqual({
      profiles: 2,
      workspaces: 2,
      memberships: 2,
      personas: 2,
    });
  });
});
