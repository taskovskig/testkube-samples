# Shared-cluster delivery

The application workflow runs on branch pushes only. Non-main branches use GitHub
environment `app-ci`; pushes to `main` use `app-dev`. Each environment supplies its
own `KUBECONFIG` secret for context `kind-testkube-samples`. `app-prod` is deployed separately through the manually triggered, approval-gated [production release workflow](PRODUCTION.md). No workflow creates a disposable kind
cluster. Pull requests do not trigger a duplicate run.

## Feature branch pushes: app-ci

1. Uninstall the configured application releases (`api`, `web`) and database release
   (`db`), waiting for deletion. Delete `data-db-0` and the `database` Secret.
   **Every CI run destroys the previous CI database data.** Namespace, deployment
   service account and RBAC remain in place. Unknown/unrelated releases are not removed.
2. Build the unchanged application Dockerfiles for Linux amd64 and publish each
   image as `ci-<GH_BUILD_NUMBER>` and `ci-latest` to public GHCR packages.
   `GH_BUILD_NUMBER` is `github.run_number` of the application workflow. Rerunning
   the same workflow run reuses the number; tags are therefore not immutable.
3. Install `db`, `api`, and `web` in `app-ci`. Application image references use
   `ci-<number>@sha256:<digest>` so the numbered tag is visible while the digest
   pins the exact image even if a tag later changes.
4. Run existing API unit tests, frontend build and chart checks on the runner.
   Run HTTP checks, Helm release isolation/rollback,
   and both browser suites against `app-ci`. The browser uses temporary localhost
   port forwards on the runner.
5. Only after all tests pass, tag those images `ci-passed`. This internal marker
   lets promotion reject a `ci-latest` build that failed acceptance.

The namespace remains deployed after tests for inspection. Failed runs can leave
it empty or partially deployed; the next CI run resets it again. CI tags and
packages are not deleted by namespace reset; registry retention is separate work.

Database fault injection (`make resilience`) is an optional recovery drill and
is not part of required delivery CI. It remains available manually and in the
developer-invoked `make local-tests` suite. In a managed database setup, failover
and recovery validation would be handled separately from application delivery.

## Main pushes: promote to app-dev

Main never builds application images. It pulls `ci-latest` and `ci-passed`, verifies
that they refer to the same tested image, and checks the image's source-tree label
against the checked-out main tree. Both applications must originate from the same
CI build. It then adds/pushes `dev-latest` and upgrades releases in `app-dev` using
`dev-latest@sha256:<digest>`. Database bootstrap/upgrade preserves existing data and
credentials. HTTP checks verify the deployed services; destructive CI tests are
not run in development. Only after rollout and HTTP checks succeed does promotion
add the internal `dev-passed` tag. Production publication requires `dev-latest`
and `dev-passed` to identify the same image.

The source-tree check works with merge, squash and rebase merges when the merged
source matches the tested feature branch. Require branches to be up to date before
merging. A different branch may have moved `ci-latest`; in that case promotion fails
before changing development tags/releases. Rerun the intended feature-branch CI,
then rerun main promotion. Direct main changes without a matching tested CI image
also fail rather than silently rebuilding or deploying unrelated code.

CI and promotion share a single workflow concurrency group with cancellation of
running jobs disabled. GitHub keeps at most one pending run in a group, so a newer
pending run may replace an older one. Rerun a canceled required check before merging.
This serializes this application's namespace mutations and alias updates; do not
run manual deployment commands concurrently with the workflow.

## Identifying a deployed build

With platform-tools v0.8.0, the API and web releases show `ci-<run number>` in
Helm's **APP VERSION** column in both app-ci and app-dev. Development derives this
version from the promoted image's validated CI build label while its deployed
image reference remains `dev-latest@sha256:<digest>`. The shared chart version is
unchanged; each deployment uses a private chart copy with the application metadata.
PostgreSQL keeps its upstream chart's application version.

Existing revisions retain their original metadata; new deployments record the
new behavior. Helm rollback restores the selected revision's recorded version
and image. CI reruns can reuse a run number, so inspect the digest for an exact
image identity. With an authorized development kubeconfig:

```sh
helm --kubeconfig .kube/kubeconfig_macpro \
  --kube-context kind-testkube-samples -n app-dev ls
helm --kubeconfig .kube/kubeconfig_macpro \
  --kube-context kind-testkube-samples -n app-dev get values web --all
```

Replace the kubeconfig path with your own local file. Production records its
release timestamp tag instead; see [PRODUCTION.md](PRODUCTION.md).

## GitHub setup and release order

1. Publish the prepared `platform-tools` **v0.8.0** tag before pushing this consumer
   upgrade. The reusable workflow installs the CLI from that tag before fetching
   the platform package. Commit its release manifest with the release. Update
   `platform.lock.json` with that tag and checksum, and pin both
   `.github/workflows/platform.yaml` and `.github/workflows/production.yaml`
   to the same tag. Keep existing tags unchanged.
2. Keep `app-ci`, `app-dev`, and `app-prod` environments in `testkube-samples`.
   Each `KUBECONFIG` secret must contain a portable kubeconfig, not a file path.
   Prefer separate `platform-deployer` credentials restricted to the corresponding
   namespace. Do not put a cluster administrator credential in the application repo.
3. Permit feature branch deployment refs in `app-ci`; allow only `main` in `app-dev`.
   Restrict/review who can push feature-branch code because those runs get CI cluster
   credentials and package-write permission. Fork PRs do not run trusted deployments;
   review and copy their changes to an authorized branch if needed.
4. Keep both GHCR packages public and grant this repository Actions access:
   `ghcr.io/taskovskig/testkube-samples/api` and
   `ghcr.io/taskovskig/testkube-samples/web`. Publishing uses `GITHUB_TOKEN`.
   New packages start private: switch both to public, then rerun if the anonymous
   pull check fails. Public pulls require no Kubernetes registry secret.
5. Require **Platform gate** on `main` and require the feature branch to be up to
   date. The check now comes from the feature-branch push, not a PR-triggered job.
   A passed CI check permits merging; development promotion runs after the merge,
   so its failure cannot undo a merge. Production promotion is manual and approval-gated; see [PRODUCTION.md](PRODUCTION.md).

Platform namespace and RBAC provisioning remains the `platform-tools` main-push
workflow. It creates `app-ci`, `app-dev`, and `app-prod` with separate deployment
identities. The `platform-administration` credential in that repo remains separate
from these application credentials. See [platform provisioning documentation](https://github.com/taskovskig/platform-tools/blob/v0.8.0/PLATFORM.md#cluster-provisioning-on-main);
the platform README contains only tag-publishing instructions.
Service-account tokens expire; renew each environment secret before expiry.
Namespaces share node/control-plane failure domains despite separate RBAC.

## Developer-only local tests

```sh
make setup
make local-tests
```

This command is never called by any workflow and refuses to run when `CI` is set
or a shared environment is selected. It installs npm/Cypress dependencies, runs
API/build/chart tests, creates or reuses the local kind cluster, deploys, and runs
HTTP, release-isolation, recovery and browser tests. Install local Docker, kind,
kubectl, Helm, Node and Python prerequisites first. It uses the original local
cluster `testkube-platform` and namespace `testkube-sample`, not the home cluster.

The local cluster is left running for inspection, including after failures:

```sh
make status
make down CONFIRM=testkube-platform
```

Existing fine-grained commands (`make test`, `make browser-test`, etc.) still work.
For shared-cluster inspection, explicitly choose the environment and credential:

```sh
PLATFORM_ENVIRONMENT=app-ci KUBECONFIG="$PWD/.kube/ci.json" make status
PLATFORM_ENVIRONMENT=app-dev KUBECONFIG="$PWD/.kube/dev.json" make releases
```

`up` and `down` reject shared environments. Fault-injection tests reject `app-dev`.
Use `make ci-reset` only with the CI credential and `PLATFORM_ENVIRONMENT=app-ci`;
it permanently deletes CI database data. Failed promotion can require a deliberate
Helm rollback; it does not automatically restore all previously deployed releases.

## Database credentials

Configure `DB_NAME`, `DB_USER`, and `DB_PASSWORD` alongside `KUBECONFIG` in each GitHub environment. Shared deployment fails if any database secret is empty. For example, app-ci can use `ci-api-db` / `ci-api-user`, while app-dev uses its own values. app-prod secrets are used only by the approved production deployment job; see [PRODUCTION.md](PRODUCTION.md).

The platform creates the namespace-local `database` Kubernetes Secret with `POSTGRES_DB`, `POSTGRES_USER`, and `POSTGRES_PASSWORD`. PostgreSQL and the API consume matching values through Secret references, not plaintext Helm values. Host `db` and port `5432` remain ordinary API configuration. PostgreSQL readiness checks use the configured database via `PGDATABASE`.

Local deployments take `developmentName`, `developmentUser`, and `developmentPassword` from `platform.json`, ignoring shared-environment credential variables. Direct execution of the API outside Kubernetes retains the original defaults unless its DB environment variables are set.

CI resets database data before initialization. The first app-dev deployment creates its database using app-dev secrets. Existing Secrets are compared with the requested database name and credentials; a mismatch (including a legacy Secret without POSTGRES_DB) stops deployment. Credentials are never silently rotated against retained data. For disposable local data, `make down CONFIRM=testkube-platform` followed by `make up` initializes the new Secret format. For retained data, coordinate the database change and Secret update manually before retrying; changing GitHub secrets alone is insufficient.
