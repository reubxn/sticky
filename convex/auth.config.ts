declare const process: {
  env: Record<string, string | undefined>;
};

const clerkJwtIssuerDomain = process.env.CLERK_JWT_ISSUER_DOMAIN;

if (!clerkJwtIssuerDomain) {
  throw new Error("CLERK_JWT_ISSUER_DOMAIN is not configured");
}

export default {
  providers: [
    {
      domain: clerkJwtIssuerDomain,
      applicationID: "convex",
    },
  ],
};
