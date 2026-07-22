# Convex backend

The root npm project owns Sticky's Convex schema, functions, generated types,
and backend tests. The macOS app is not connected to Convex in this bootstrap
slice.

## Local setup

Requirements: Node.js 20 or newer and access to the Sticky Convex project.

```bash
npm ci
npx convex login
npm run convex:dev:once
npm test
```

`convex:dev:once` pushes the schema and functions to the deployment selected by
`CONVEX_DEPLOYMENT`, validates the schema, typechecks functions, and refreshes
`convex/_generated`. Use `npm run convex:dev` for the long-running development
watcher. Verify a deployment with:

```bash
npx convex run health:check
```

Commit generated files after schema or function changes. Commit neither
`.env.local` nor deployment credentials.

## Deployments and secrets

Convex development and production deployments are separate. Confirm the
selected deployment before pushing code. Deploy production only from an
authenticated release environment:

```bash
npm run convex:deploy
```

Set backend secrets with `npx convex env set NAME value` against the intended
deployment. Store values in the team's secret manager and CI environment; do
not place them in source files, npm scripts, or committed env files.

Authentication provider configuration is deliberately deferred. Until
`convex/auth.config.ts` is introduced with the selected provider, deployed
protected operations will deny callers because Convex has no verified identity.
