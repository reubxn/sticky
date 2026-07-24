import { v } from "convex/values";

import { query } from "./_generated/server";
import { requireIdentity } from "./authorization";

export const current = query({
  args: {},
  returns: v.object({
    tokenIdentifier: v.string(),
    subject: v.string(),
    issuer: v.string(),
    name: v.union(v.string(), v.null()),
    email: v.union(v.string(), v.null()),
  }),
  handler: async (ctx) => {
    const identity = await requireIdentity(ctx);

    return {
      tokenIdentifier: identity.tokenIdentifier,
      subject: identity.subject,
      issuer: identity.issuer,
      name: identity.name ?? null,
      email: identity.email ?? null,
    };
  },
});
