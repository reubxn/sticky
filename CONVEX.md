# Convex backend

The root npm project owns Sticky's Convex schema, functions, generated types,
and backend tests. The macOS app is not connected to Convex in this bootstrap
slice.

## Deployment safety

Before running any Convex CLI command or `convex:*` npm script, inspect
`CONVEX_DEPLOYMENT` in `.env.local` and confirm that its team, project, and
deployment are the intended target. Stop and ask if the target is unclear.

Plain `npx convex dev` and the root Convex scripts use the configured
`CONVEX_DEPLOYMENT`. That deployment may be cloud-hosted, and development,
codegen, run, environment, and deployment commands may read or mutate it.

For isolated local validation, explicitly force anonymous agent mode:

```bash
CONVEX_AGENT_MODE=anonymous npx convex dev --once
```

Never run `convex deploy` or `npm run convex:deploy` without explicit user
authorization for that production deployment operation.

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
