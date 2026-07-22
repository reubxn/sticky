import type { UserIdentity } from "convex/server";
import { ConvexError } from "convex/values";

import type { Doc, Id } from "./_generated/dataModel";
import type { MutationCtx, QueryCtx } from "./_generated/server";

type AuthorizationCtx = Pick<QueryCtx | MutationCtx, "auth" | "db">;
type WorkspaceRole = Doc<"workspaceMembers">["role"];

function deny(
  code: "UNAUTHENTICATED" | "UNAUTHORIZED",
  message: string,
): never {
  throw new ConvexError({ code, message });
}

function denyResourceUnavailable(): never {
  return deny("UNAUTHORIZED", "Resource unavailable");
}

export async function requireIdentity(
  ctx: Pick<AuthorizationCtx, "auth">,
): Promise<UserIdentity> {
  const identity = await ctx.auth.getUserIdentity();
  if (identity === null) {
    return deny("UNAUTHENTICATED", "Authentication required");
  }
  return identity;
}

export async function requireCanonicalUser(
  ctx: Pick<AuthorizationCtx, "db">,
  identity: UserIdentity,
): Promise<Doc<"profiles">> {
  const profile = await ctx.db
    .query("profiles")
    .withIndex("by_tokenIdentifier", (indexQuery) =>
      indexQuery.eq("tokenIdentifier", identity.tokenIdentifier),
    )
    .unique();

  if (profile === null || profile.lifecycleStatus !== "active") {
    return deny("UNAUTHORIZED", "Active profile required");
  }
  return profile;
}

export async function requireWorkspace(
  ctx: Pick<AuthorizationCtx, "db">,
  workspaceId: Id<"workspaces">,
): Promise<Doc<"workspaces">> {
  const workspace = await ctx.db.get("workspaces", workspaceId);
  if (workspace === null || workspace.lifecycleStatus !== "active") {
    return denyResourceUnavailable();
  }
  return workspace;
}

async function requireActiveMembershipForProfile(
  ctx: Pick<AuthorizationCtx, "db">,
  workspaceId: Id<"workspaces">,
  profileId: Id<"profiles">,
): Promise<Doc<"workspaceMembers">> {
  const membership = await ctx.db
    .query("workspaceMembers")
    .withIndex("by_workspaceId_and_userId_and_status", (indexQuery) =>
      indexQuery
        .eq("workspaceId", workspaceId)
        .eq("userId", profileId)
        .eq("status", "active"),
    )
    .unique();

  if (membership === null) {
    return denyResourceUnavailable();
  }
  return membership;
}

export async function requireActiveMembership(
  ctx: AuthorizationCtx,
  workspaceId: Id<"workspaces">,
): Promise<Doc<"workspaceMembers">> {
  const identity = await requireIdentity(ctx);
  const profile = await requireCanonicalUser(ctx, identity);
  const membership = await requireActiveMembershipForProfile(
    ctx,
    workspaceId,
    profile._id,
  );
  await requireWorkspace(ctx, workspaceId);
  return membership;
}

export async function requireWorkspaceRole(
  ctx: AuthorizationCtx,
  workspaceId: Id<"workspaces">,
  allowedRoles: readonly WorkspaceRole[],
): Promise<Doc<"workspaceMembers">> {
  const membership = await requireActiveMembership(ctx, workspaceId);
  if (!allowedRoles.includes(membership.role)) {
    return deny("UNAUTHORIZED", "Insufficient workspace role");
  }
  return membership;
}

export async function requireWorkspaceOwner(
  ctx: AuthorizationCtx,
  workspaceId: Id<"workspaces">,
): Promise<Doc<"workspaceMembers">> {
  return await requireWorkspaceRole(ctx, workspaceId, ["owner"]);
}

export async function requirePersonalWorkspaceOwner(
  ctx: AuthorizationCtx,
  workspaceId: Id<"workspaces">,
): Promise<{
  workspace: Doc<"workspaces">;
  membership: Doc<"workspaceMembers">;
}> {
  const membership = await requireWorkspaceOwner(ctx, workspaceId);
  const workspace = await requireWorkspace(ctx, workspaceId);
  if (workspace.kind !== "personal") {
    return deny("UNAUTHORIZED", "Personal workspace ownership required");
  }
  return { workspace, membership };
}

export async function requirePersonaOwner(
  ctx: AuthorizationCtx,
  personaId: Id<"personas">,
): Promise<{
  profile: Doc<"profiles">;
  membership: Doc<"workspaceMembers">;
  persona: Doc<"personas">;
}> {
  const identity = await requireIdentity(ctx);
  const profile = await requireCanonicalUser(ctx, identity);
  const persona = await ctx.db.get("personas", personaId);

  if (
    persona === null ||
    persona.status !== "active" ||
    persona.ownerUserId !== profile._id
  ) {
    return denyResourceUnavailable();
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
    return denyResourceUnavailable();
  }

  await requireWorkspace(ctx, persona.workspaceId);
  return { profile, membership, persona };
}

export async function requireUsablePersona(
  ctx: AuthorizationCtx,
  personaId: Id<"personas">,
): Promise<{
  askingMembership: Doc<"workspaceMembers">;
  ownerMembership: Doc<"workspaceMembers">;
  persona: Doc<"personas">;
}> {
  const identity = await requireIdentity(ctx);
  const profile = await requireCanonicalUser(ctx, identity);
  const persona = await ctx.db.get("personas", personaId);
  if (persona === null || persona.status !== "active") {
    return denyResourceUnavailable();
  }

  const askingMembership = await requireActiveMembershipForProfile(
    ctx,
    persona.workspaceId,
    profile._id,
  );
  await requireWorkspace(ctx, persona.workspaceId);
  const ownerMembership = await ctx.db.get(
    "workspaceMembers",
    persona.membershipId,
  );

  if (
    ownerMembership === null ||
    ownerMembership.status !== "active" ||
    ownerMembership.workspaceId !== persona.workspaceId ||
    ownerMembership.userId !== persona.ownerUserId
  ) {
    return denyResourceUnavailable();
  }

  return { askingMembership, ownerMembership, persona };
}
