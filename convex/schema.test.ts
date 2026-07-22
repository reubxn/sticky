/// <reference types="vite/client" />

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";

import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");

async function insertProfile() {
  const testBackend = convexTest(schema, modules);
  const profileId = await testBackend.run(async (ctx) => {
    return await ctx.db.insert("profiles", {
      tokenIdentifier: "https://issuer.example|schema-test",
      displayName: "Schema test",
      accountSettings: {},
      lifecycleStatus: "active",
      createdAt: 1_700_000_000_000,
      updatedAt: 1_700_000_000_000,
    });
  });
  return { profileId, testBackend };
}

describe("workspace schema", () => {
  test("personal workspaces may omit businessType", async () => {
    const { profileId, testBackend } = await insertProfile();

    const workspaceId = await testBackend.run(async (ctx) => {
      return await ctx.db.insert("workspaces", {
        kind: "personal",
        name: "Personal workspace",
        createdByProfileId: profileId,
        lifecycleStatus: "active",
        createdAt: 1_700_000_000_000,
        updatedAt: 1_700_000_000_000,
      });
    });

    const workspace = await testBackend.run(
      async (ctx) => await ctx.db.get("workspaces", workspaceId),
    );
    expect(workspace).toMatchObject({
      kind: "personal",
      name: "Personal workspace",
    });
  });

  test("team workspaces require businessType", async () => {
    const { profileId, testBackend } = await insertProfile();
    const teamWithoutBusinessType = {
      kind: "team" as const,
      name: "Team workspace",
      createdByProfileId: profileId,
      lifecycleStatus: "active" as const,
      createdAt: 1_700_000_000_000,
      updatedAt: 1_700_000_000_000,
    };

    await expect(
      testBackend.run(async (ctx) => {
        // @ts-expect-error Team workspaces require businessType.
        return await ctx.db.insert("workspaces", teamWithoutBusinessType);
      }),
    ).rejects.toThrow("Validator error");
  });
});
