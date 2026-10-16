# Contributing

## Setup

```sh
git clone https://github.com/appfide/nija.git
cd nija
./scripts/bootstrap.sh        # installs pre-commit hooks, fetches deps
```

Requirements: Flutter ≥ 3.44 (stable; CI pins 3.47.5), `pre-commit`, `gitleaks`. On macOS: `brew install pre-commit gitleaks`.

## Workflow

1. Branch from `main`: `feat/<topic>`, `fix/<topic>`, `backend/<db>`.
2. Commit using [Conventional Commits](https://www.conventionalcommits.org): enforced by a commit-msg hook.
3. `pre-commit run --all-files` must pass. It runs gitleaks, formatting, analysis and the credential-file check.
4. Open a PR against `main`; the `main protection` ruleset requires green CI, linear history and squash/rebase merges. Required approvals are 0 while there is a single maintainer; raise to 1 in the ruleset once a second maintainer joins.

## Adding a database backend

1. Create `packages/nija_core/lib/src/backends/<name>/<name>_backend.dart` implementing `SyncBackend`.
2. Declare its settings in a `BackendDescriptor`: the settings UI is generated from `configSchema`, so every field the user must enter lives there.
3. Register it in `backend_registry.dart`.
4. Add contract tests (`test/backends/<name>_backend_test.dart`) using the shared `runBackendContractTests` helper.
5. Write `docs/backends/<name>.md` with the exact schema (tables/collections/indexes/rules) and a step-by-step setup.
6. Add credential patterns for that database to `.gitleaks.toml`.

The backend must be reachable **directly from the app** with user-supplied credentials, no proxy, no server component owned by this project.

## UI changes

- Design tokens live in `apps/nija/lib/ui/app_theme.dart`; use `Theme.of(context)` / `context.colors`, never hardcoded colours.
- After visual changes regenerate the screenshots used in the README:
  `cd apps/nija && FLUTTER_ROOT=$(dirname $(dirname $(which flutter))) flutter test test_screenshots --update-goldens`
  and eyeball the PNGs in `docs/screenshots/` in both themes.

## Never commit

- `.env` files, keystores, certificates, provisioning profiles, `google-services.json`, `GoogleService-Info.plist`, `firebase_options.dart`, `key.properties`
- Any real database URL or key, even in tests; use placeholders such as `YOUR_ANON_KEY`
