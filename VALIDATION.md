# Validation evidence

The corrected platform was verified locally on macOS ARM64 on 2026-10-03. This records the split into independent api, web and db releases. The updated GitHub Actions workflow has not been run on GitHub.

| Check | Observed result |
| --- | --- |
| Application ownership | No differences against origin/main for apps/, package.json, package-lock.json or docker-compose.yaml |
| Original API test | Previously passed: 1 test; application unchanged in this release split |
| Original frontend build | Previously passed; original Dockerfile build also succeeded during this verification |
| Helm chart | Strict lint and rendered configuration contracts passed, including release isolation, absence of database resources, existing-route probes, runtime ports and invalid-value rejection |
| Original Dockerfiles | Both images built without Dockerfile or application changes |
| Kubernetes deployment | Separate db, api and web installations passed; application server dry-runs passed; all workloads ready; frontend HTML, API greeting and actual SQL response passed |
| Helm upgrade and rollback | Each application scaled from 1 to 2 replicas and rolled back independently; the other release revision/deployment generation, db revision, PVC UID and Secret resource version remained unchanged |
| Database persistence | Inserted SQL row survived PostgreSQL pod replacement |
| Database outage | API stayed Ready, returned HTTP 200 with message "request failed", and did not restart; database restoration and SQL smoke check passed |
| Browser journeys | Original counter test passed; 3 separate platform tests passed for frontend counter, API greeting and PostgreSQL greeting |
| Design PDF | Seven pages rendered and visually inspected |

## Runtime and limitations

- kind v0.33.0, Kubernetes v1.37.0, Helm v4.3.0; image pair `32ed227-20261003184112-37445`. All three releases installed at revision 1. Application upgrade/rollback checks advanced api and web independently; db remained at revision 1.
- Application Dockerfiles use floating `node:lts`, full Node images and development dependencies. The build reported npm audit findings; no vulnerability remediation or production image hardening is claimed. Host tests used Node 26.10.0; CI selects Node 24 and remains unverified on hosted Linux/AMD64.
- The original browser requires localhost:8080. The API embeds api-user/api-password/api-db, does not expose database-aware readiness, and uses an unreliable shutdown integration. These are documented application limitations requiring separately agreed developer-owned changes before production.
- Both local tunnels are required for browser acceptance. The smoke check uses independent random ports and exact response bodies; HTTP 200 alone cannot establish database health.
- The database uses groundhog2k postgres chart 1.6.8, with a SHA-256-verified download and local PostgreSQL 17 image override. The PVC is data-db-0. A managed database was not tested; changing the API host still requires the original fixed database name and credentials.
- The local database has one instance and a PVC, without off-machine backups. Cluster deletion destroys its data. Shared-environment identity, network isolation, TLS, telemetry and Git-based promotion remain proposed work.
- Cypress emitted a non-fatal terminal-size helper architecture warning on macOS ARM64; both test runs completed successfully.
- Application files remain identical to origin/main. Shell syntax, chart rendering and changed-file whitespace checks passed.
- API-only `make deploy SERVICE=api` built and deployed only API, advanced it to revision 6, and passed smoke checks; web stayed at revision 5 and db at revision 1. Its image tag was `32ed227-20261003184907-44342`.
- Both browser tunnels were stopped and the disposable verification cluster was deleted after testing.

## Platform v0.2.0 consumer migration (2026-10-04)

- Downloaded the published tag through `make platform-fetch`, without a local override; manifest and packaged-file checks passed. `make platform-version` reports `v0.2.0`.
- Shared-chart checks and all eight application bootstrap unit tests passed.
- Rendered the pinned PostgreSQL chart with the downloaded platform defaults, generated resource names, and reduced application overrides. Output is identical to the previous full database values file.
- The default kind configuration matches the removed local file. Generated namespace and service-account names and security settings preserve the previous configuration.
- Application code, Dockerfiles, root npm manifests, and Compose were not changed by this migration.
- Live cluster deployment, persistence, rollback, browser acceptance, and hosted CI were not rerun for this migration; the earlier runtime evidence above is historical.

## Development PR gate / platform v0.3.0 (2026-10-04)

- Prepared platform v0.3.0 and aligned both reusable-workflow references with the consumer lock. Verified a temporary package assembled from the release manifest using the actual consumer verifier; this is not a published-tag download test.
- Fourteen platform tests passed, including execution of deployment scripts with mocked Kubernetes, Docker, registry, and Helm boundaries plus a real localhost HTTP contract endpoint. They cover digest deployment, Linux amd64 builds, namespace/context targeting, rejection of shared-cluster lifecycle operations, anonymous-pull failure before mutations, and preservation of local kind loading.
- Nine application bootstrap tests passed, including rejection of mismatched development-workflow pins. Shared-chart tests passed with the explicit local platform override.
- actionlint v1.7.7 validated the application workflow and all platform workflows. All sixteen combinations of success/failure/cancelled/skipped job results were checked against the actual gate shell; only two successful jobs pass.
- Manifest generation excludes ignored local credentials and rejects tracked `.kube` contents. Shell syntax and whitespace checks passed. Application sources, Dockerfiles, npm manifests, and Compose remain unchanged.
- No credentials were read, no images were published, and no operations were run against the home cluster. Live GHCR publishing, runner-to-cluster access, RBAC authorization, deployment/recovery/browser acceptance, and GitHub environment/branch protection remain to be verified after platform publication and administrator setup described in DEVELOPMENT.md.

## Shared CI and development delivery / platform v0.4.0 (2026-10-04)

- Twenty-one platform tests passed. Mocked CLI integration covers CI build tags and digest deployment, release/PVC/Secret reset restricted to app-ci, promotion without rebuilding, rejection of untested or mismatched source images, and local-tests command order and workflow/shared-environment rejection. Kubernetes, Helm, Docker and registry boundaries were mocked.
- Nine consumer bootstrap tests and the shared-chart checks passed. The actual consumer verifier accepted a temporary package assembled from the prepared release manifest; this is not a published-tag download test.
- actionlint validated the application workflow and all three platform workflows. Shell syntax and whitespace checks passed. Application sources, Dockerfiles, root npm manifests and Compose remain unchanged.
- Feature pushes and main promotion now share a serialized workflow; neither creates a kind cluster. Production has no deployment path.
- The v0.4.0 manifest and consumer pin are prepared locally. Publish that platform release before pushing the consumer change.
- No home-cluster operations or image publishing were performed. Live reset, registry promotion and deployed acceptance still need verification after publication.

## Installed platform CLI / v0.5.0 (2026-10-04)

- All 33 platform tests passed, including the migrated bootstrap tests and new application discovery, dispatch, and incompatible CLI API checks. Kubernetes and registry operations remained mocked.
- Built and installed the Python package in a temporary virtual environment. Both CLI entry points expose help, and the platform CLI reports version 0.5.0. The optional ReportLab extra installs separately; no design PDF was regenerated.
- The installed CLI passed shared-chart tests through the application Makefile with the explicit local platform override. Missing-CLI handling prints the tagged installation command.
- The installed CLI verified a temporary package assembled from the prepared manifest against the application lock. This is not a published-tag installation/download test.
- Workflow lint and whitespace checks passed. No application sources, Dockerfiles, npm manifests or Compose changes; no live cluster operations, commits, tags or pushes. Publish platform-tools v0.5.0 before pushing this consumer upgrade, and install the CLI locally before using platform Make targets.

## Environment database secrets / platform v0.6.0 (2026-10-04)

- Two API tests passed, including exercising the database route with injected credentials containing URL-sensitive characters. The PostgreSQL client is mocked for this unit test.
- All 35 platform tests passed, including missing shared secrets, safe JSON Secret creation with special characters, and generated database Secret references. Cluster and registry boundaries were mocked.
- Shared-chart tests and workflow lint passed. Rendered the pinned upstream PostgreSQL chart and verified POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD and PGDATABASE reference the namespace-local database Secret. No credentials are placed in Helm values.
- Prepared v0.6.0 release pins. No live cluster deployment, GitHub secret inspection, commits, tags or pushes were performed. Existing retained databases/legacy Secrets require deliberate migration; fresh CI data and first development deployment use the selected GitHub secrets.

## Production release and approved deployment / platform v0.7.0 (2026-10-05)

- All 49 platform tests passed. New tests cover UTC release identity, PR-delta deduplication, mixed/untested development image rejection, draft snapshot reuse, published retries without retagging, stale-run rejection, manifest tamper detection, exact digest deployment and production namespace guards. GitHub, registry and cluster boundaries were mocked.
- Shared-chart checks, all workflow actionlint checks, shell syntax and whitespace checks passed. The v0.7.0 distribution was verified against the consumer lock using the actual CLI verifier.
- Updated the operator guide and rendered/visually checked the interview PDF. Existing uncommitted documentation corrections were preserved.
- No GitHub Release, registry tags, approvals or production deployment were performed. Live publication, PR-association coverage for repository history, environment approval, production RBAC and rollout/HTTP checks must be verified after publishing v0.7.0 and completing successful development delivery from main.

## 2026-10-05: deployed application version metadata

Prepared platform-tools v0.8.0 and matching application pins. All 53 platform
unit/contract tests pass, including real deployment-script tests with mocked CLI
boundaries for CI, development, production, and local appVersion selection.
Chart-copy tests verify source immutability, release isolation, input validation,
and refusal to overwrite an existing copy. Real Helm lint and `helm show chart`
confirm appVersion ci-42 while chart version remains 0.3.0. Reusable workflow
linting passes. No live deployment or tag publication was performed for this
change; existing cluster revisions retain their previous metadata.
