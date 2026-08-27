/// <reference types="vite/client" />

import { convexTest } from "convex-test";
import { ConvexError } from "convex/values";
import { describe, expect, test } from "vitest";

import { api } from "./_generated/api";
import {
  requireActiveMembership,
  requireIdentity,
  requirePersonaOwner,
  requirePersonalWorkspaceOwner,
  requireUsablePersona,
  requireWorkspaceOwner,
} from "./authorization";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");

const ownerIdentity = {
  subject: "owner",
  issuer: "https://issuer.example",
  tokenIdentifier: "https://issuer.example|owner",
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

async function expectAuthorizationError(
  operation: Promise<unknown>,
  code: "UNAUTHENTICATED" | "UNAUTHORIZED",
  message: string,
) {
  try {
    await operation;
    expect.fail("Expected authorization to fail");
  } catch (error) {
    expect(error).toBeInstanceOf(ConvexError);
    if (!(error instanceof ConvexError)) {
      throw error;
    }
    expect(error.data).toEqual({ code, message });
  }
}

async function seedWorkspace() {
  const testBackend = convexTest(schema, modules);
  const ids = await testBackend.run(async (ctx) => {
    const timestamp = 1_700_000_000_000;
    const ownerProfileId = await ctx.db.insert("profiles", {
      tokenIdentifier: ownerIdentity.tokenIdentifier,
      displayName: "Owner",
      accountSettings: {},
      lifecycleStatus: "active",
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    const memberProfileId = await ctx.db.insert("profiles", {
      tokenIdentifier: memberIdentity.tokenIdentifier,
      displayName: "Member",
      accountSettings: {},
      lifecycleStatus: "active",
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    const unrelatedProfileId = await ctx.db.insert("profiles", {
      tokenIdentifier: unrelatedIdentity.tokenIdentifier,
      displayName: "Unrelated",
      accountSettings: {},
      lifecycleStatus: "active",
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    const workspaceId = await ctx.db.insert("workspaces", {
      kind: "team",
      name: "Sticky",
      businessType: "Software",
      createdByProfileId: ownerProfileId,
      lifecycleStatus: "active",
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    const ownerMembershipId = await ctx.db.insert("workspaceMembers", {
      workspaceId,
      userId: ownerProfileId,
      role: "owner",
      status: "active",
      joinedAt: timestamp,
    });
    const memberMembershipId = await ctx.db.insert("workspaceMembers", {
      workspaceId,
      userId: memberProfileId,
      role: "member",
      status: "active",
      joinedAt: timestamp,
    });
    const ownerPersonaId = await ctx.db.insert("personas", {
      membershipId: ownerMembershipId,
      workspaceId,
      ownerUserId: ownerProfileId,
      status: "active",
      displayName: "Owner",
      setupState: "complete",
      currentVersion: 1,
      activatedAt: timestamp,
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    await ctx.db.insert("personaOnboardingSessions", {
      personaId: ownerPersonaId,
      membershipId: ownerMembershipId,
      workspaceId,
      ownerUserId: ownerProfileId,
      status: "completed",
      revision: 1,
      turnCount: 0,
      nextSequence: 0,
      startedAt: timestamp,
      updatedAt: timestamp,
      completedAt: timestamp,
    });
    const ownerVersionId = await ctx.db.insert("personaVersions", {
      personaId: ownerPersonaId,
      membershipId: ownerMembershipId,
      workspaceId,
      ownerUserId: ownerProfileId,
      versionNumber: 1,
      previousVersionNumber: 0,
      clientMutationId: "authorization-seed",
      requestFingerprint: "a".repeat(64),
      source: { kind: "manual_owner_edit" },
      changeCount: 2,
      createdAt: timestamp,
    });
    for (const [recordKey, content] of [
      [
        "work",
        { kind: "work_context" as const, statement: "Builds software" },
      ],
      [
        "communication",
        {
          kind: "communication_preference" as const,
          statement: "Prefers concise answers",
        },
      ],
    ] as const) {
      await ctx.db.insert("personaRecords", {
        personaId: ownerPersonaId,
        membershipId: ownerMembershipId,
        workspaceId,
        ownerUserId: ownerProfileId,
        recordKey,
        versionId: ownerVersionId,
        versionNumber: 1,
        kind: content.kind,
        state: "active",
        isCurrent: true,
        content,
        source: { kind: "manual_owner_edit" },
        confidence: 1,
        createdAt: timestamp,
      });
    }
    const unrelatedWorkspaceId = await ctx.db.insert("workspaces", {
      kind: "team",
      name: "Other workspace",
      businessType: "Software",
      createdByProfileId: unrelatedProfileId,
      lifecycleStatus: "active",
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    const unrelatedMembershipId = await ctx.db.insert("workspaceMembers", {
      workspaceId: unrelatedWorkspaceId,
      userId: unrelatedProfileId,
      role: "owner",
      status: "active",
      joinedAt: timestamp,
    });
    const unrelatedPersonaId = await ctx.db.insert("personas", {
      membershipId: unrelatedMembershipId,
      workspaceId: unrelatedWorkspaceId,
      ownerUserId: unrelatedProfileId,
      status: "active",
      displayName: "Unrelated",
      setupState: "complete",
      currentVersion: 1,
      activatedAt: timestamp,
      createdAt: timestamp,
      updatedAt: timestamp,
    });

    return {
      memberMembershipId,
      memberProfileId,
      ownerMembershipId,
      ownerPersonaId,
      ownerProfileId,
      unrelatedMembershipId,
      unrelatedPersonaId,
      unrelatedProfileId,
      unrelatedWorkspaceId,
      workspaceId,
    };
  });

  return { ids, testBackend };
}

describe("Convex bootstrap", () => {
  test("health query reports a ready backend", async () => {
    const testBackend = convexTest(schema, modules);

    await expect(testBackend.query(api.health.check)).resolves.toEqual({
      service: "sticky-convex",
      status: "ok",
    });
  });

  test("authorization denies an unauthenticated caller", async () => {
    const testBackend = convexTest(schema, modules);

    await expectAuthorizationError(
      testBackend.run(async (ctx) => await requireIdentity(ctx)),
      "UNAUTHENTICATED",
      "Authentication required",
    );
  });

  test("membership and role helpers return validated records", async () => {
    const { ids, testBackend } = await seedWorkspace();
    const asOwner = testBackend.withIdentity(ownerIdentity);

    const membership = await asOwner.run(
      async (ctx) => await requireActiveMembership(ctx, ids.workspaceId),
    );
    const ownerMembership = await asOwner.run(
      async (ctx) => await requireWorkspaceOwner(ctx, ids.workspaceId),
    );

    expect(membership._id).toEqual(ids.ownerMembershipId);
    expect(ownerMembership.role).toEqual("owner");
  });

  test("authenticated members receive a role-specific denial", async () => {
    const { ids, testBackend } = await seedWorkspace();
    const asMember = testBackend.withIdentity(memberIdentity);

    await expectAuthorizationError(
      asMember.run(
        async (ctx) => await requireWorkspaceOwner(ctx, ids.workspaceId),
      ),
      "UNAUTHORIZED",
      "Insufficient workspace role",
    );
  });

  test("personal workspace checks authenticate before inspecting kind", async () => {
    const { ids, testBackend } = await seedWorkspace();

    await expectAuthorizationError(
      testBackend.run(
        async (ctx) =>
          await requirePersonalWorkspaceOwner(ctx, ids.workspaceId),
      ),
      "UNAUTHENTICATED",
      "Authentication required",
    );

    const asOwner = testBackend.withIdentity(ownerIdentity);
    await expectAuthorizationError(
      asOwner.run(
        async (ctx) =>
          await requirePersonalWorkspaceOwner(ctx, ids.workspaceId),
      ),
      "UNAUTHORIZED",
      "Personal workspace ownership required",
    );

    const asUnrelated = testBackend.withIdentity(unrelatedIdentity);
    await expectAuthorizationError(
      asUnrelated.run(
        async (ctx) =>
          await requirePersonalWorkspaceOwner(ctx, ids.workspaceId),
      ),
      "UNAUTHORIZED",
      "Resource unavailable",
    );
  });

  test("persona use is workspace-wide but mutation remains owner-only", async () => {
    const { ids, testBackend } = await seedWorkspace();
    const asMember = testBackend.withIdentity(memberIdentity);
    const asOwner = testBackend.withIdentity(ownerIdentity);

    const usablePersona = await asMember.run(
      async (ctx) => await requireUsablePersona(ctx, ids.ownerPersonaId),
    );
    expect(usablePersona.persona._id).toEqual(ids.ownerPersonaId);
    expect(usablePersona.askingMembership.role).toEqual("member");

    await expectAuthorizationError(
      asMember.run(
        async (ctx) => await requirePersonaOwner(ctx, ids.ownerPersonaId),
      ),
      "UNAUTHORIZED",
      "Resource unavailable",
    );

    const ownerAccess = await asOwner.run(
      async (ctx) => await requirePersonaOwner(ctx, ids.ownerPersonaId),
    );
    expect(ownerAccess.persona._id).toEqual(ids.ownerPersonaId);
  });

  test("unrelated users receive normalized workspace and persona denials", async () => {
    const { ids, testBackend } = await seedWorkspace();
    const asUnrelated = testBackend.withIdentity(unrelatedIdentity);

    await expectAuthorizationError(
      asUnrelated.run(
        async (ctx) =>
          await requireActiveMembership(ctx, ids.workspaceId),
      ),
      "UNAUTHORIZED",
      "Resource unavailable",
    );
    await expectAuthorizationError(
      asUnrelated.run(
        async (ctx) => await requireUsablePersona(ctx, ids.ownerPersonaId),
      ),
      "UNAUTHORIZED",
      "Resource unavailable",
    );
    await expectAuthorizationError(
      asUnrelated.run(
        async (ctx) => await requirePersonaOwner(ctx, ids.ownerPersonaId),
      ),
      "UNAUTHORIZED",
      "Resource unavailable",
    );
  });

  test("active members cannot use personas across workspaces", async () => {
    const { ids, testBackend } = await seedWorkspace();
    const asMember = testBackend.withIdentity(memberIdentity);
    const asUnrelated = testBackend.withIdentity(unrelatedIdentity);

    await expectAuthorizationError(
      asMember.run(
        async (ctx) =>
          await requireUsablePersona(ctx, ids.unrelatedPersonaId),
      ),
      "UNAUTHORIZED",
      "Resource unavailable",
    );
    await expectAuthorizationError(
      asUnrelated.run(
        async (ctx) => await requireUsablePersona(ctx, ids.ownerPersonaId),
      ),
      "UNAUTHORIZED",
      "Resource unavailable",
    );
  });

  test("mismatched persona relationships are unavailable", async () => {
    const { ids, testBackend } = await seedWorkspace();
    const malformedPersonaIds = await testBackend.run(async (ctx) => {
      const timestamp = 1_700_000_000_002;
      const mismatchedWorkspacePersonaId = await ctx.db.insert("personas", {
        membershipId: ids.unrelatedMembershipId,
        workspaceId: ids.workspaceId,
        ownerUserId: ids.ownerProfileId,
        status: "active",
        displayName: "Mismatched workspace",
        setupState: "complete",
        currentVersion: 1,
        activatedAt: timestamp,
        createdAt: timestamp,
        updatedAt: timestamp,
      });
      const mismatchedOwnerPersonaId = await ctx.db.insert("personas", {
        membershipId: ids.ownerMembershipId,
        workspaceId: ids.workspaceId,
        ownerUserId: ids.memberProfileId,
        status: "active",
        displayName: "Mismatched owner",
        setupState: "complete",
        currentVersion: 1,
        activatedAt: timestamp,
        createdAt: timestamp,
        updatedAt: timestamp,
      });
      return { mismatchedOwnerPersonaId, mismatchedWorkspacePersonaId };
    });

    const asOwner = testBackend.withIdentity(ownerIdentity);
    await expectAuthorizationError(
      asOwner.run(
        async (ctx) =>
          await requirePersonaOwner(
            ctx,
            malformedPersonaIds.mismatchedWorkspacePersonaId,
          ),
      ),
      "UNAUTHORIZED",
      "Resource unavailable",
    );
    await expectAuthorizationError(
      asOwner.run(
        async (ctx) =>
          await requireUsablePersona(
            ctx,
            malformedPersonaIds.mismatchedOwnerPersonaId,
          ),
      ),
      "UNAUTHORIZED",
      "Resource unavailable",
    );
  });

  test("inactive profiles and workspaces are denied consistently", async () => {
    const { ids, testBackend } = await seedWorkspace();
    const asOwner = testBackend.withIdentity(ownerIdentity);

    await testBackend.run(async (ctx) => {
      await ctx.db.patch("profiles", ids.ownerProfileId, {
        lifecycleStatus: "deletionPending",
      });
    });
    await expectAuthorizationError(
      asOwner.run(
        async (ctx) =>
          await requireActiveMembership(ctx, ids.workspaceId),
      ),
      "UNAUTHORIZED",
      "Active profile required",
    );

    await testBackend.run(async (ctx) => {
      await ctx.db.patch("profiles", ids.ownerProfileId, {
        lifecycleStatus: "active",
      });
      await ctx.db.patch("workspaces", ids.workspaceId, {
        lifecycleStatus: "deleting",
      });
    });
    await expectAuthorizationError(
      asOwner.run(
        async (ctx) =>
          await requireActiveMembership(ctx, ids.workspaceId),
      ),
      "UNAUTHORIZED",
      "Resource unavailable",
    );
    await expectAuthorizationError(
      asOwner.run(
        async (ctx) => await requireUsablePersona(ctx, ids.ownerPersonaId),
      ),
      "UNAUTHORIZED",
      "Resource unavailable",
    );
  });

  test("a removed owner membership makes its persona unusable", async () => {
    const { ids, testBackend } = await seedWorkspace();
    await testBackend.run(async (ctx) => {
      await ctx.db.patch("workspaceMembers", ids.ownerMembershipId, {
        status: "removed",
        removedAt: 1_700_000_000_001,
      });
    });

    const asMember = testBackend.withIdentity(memberIdentity);
    await expectAuthorizationError(
      asMember.run(
        async (ctx) => await requireUsablePersona(ctx, ids.ownerPersonaId),
      ),
      "UNAUTHORIZED",
      "Resource unavailable",
    );
  });

  test("an inactive persona owner profile makes its persona unusable", async () => {
    const { ids, testBackend } = await seedWorkspace();
    await testBackend.run(async (ctx) => {
      await ctx.db.patch("profiles", ids.ownerProfileId, {
        lifecycleStatus: "deletionPending",
      });
    });

    const asMember = testBackend.withIdentity(memberIdentity);
    await expectAuthorizationError(
      asMember.run(
        async (ctx) => await requireUsablePersona(ctx, ids.ownerPersonaId),
      ),
      "UNAUTHORIZED",
      "Resource unavailable",
    );
  });
});
