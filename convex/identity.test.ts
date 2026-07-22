/// <reference types="vite/client" />

import { convexTest } from "convex-test";
import { ConvexError } from "convex/values";
import { expect, test } from "vitest";

import { api } from "./_generated/api";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");

test("current identity rejects unauthenticated callers", async () => {
  const testBackend = convexTest(schema, modules);

  try {
    await testBackend.query(api.identity.current);
    expect.fail("Expected unauthenticated identity query to fail");
  } catch (error) {
    expect(error).toBeInstanceOf(ConvexError);
    if (!(error instanceof ConvexError)) {
      throw error;
    }
    expect(error.data).toEqual({
      code: "UNAUTHENTICATED",
      message: "Authentication required",
    });
  }
});

test("current identity returns verified provider claims", async () => {
  const testBackend = convexTest(schema, modules).withIdentity({
    subject: "clerk-user",
    issuer: "https://ruling-katydid-23.clerk.accounts.dev",
    tokenIdentifier:
      "https://ruling-katydid-23.clerk.accounts.dev|clerk-user",
    name: "Sticky User",
    email: "sticky@example.com",
  });

  await expect(testBackend.query(api.identity.current)).resolves.toEqual({
    tokenIdentifier:
      "https://ruling-katydid-23.clerk.accounts.dev|clerk-user",
    subject: "clerk-user",
    issuer: "https://ruling-katydid-23.clerk.accounts.dev",
    name: "Sticky User",
    email: "sticky@example.com",
  });
});
