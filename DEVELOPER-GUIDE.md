# Developer guide

Install the platform CLI once (Python 3.10+, Git and pipx required):

```sh
make setup
make platform-version
```

`make setup` installs or replaces the CLI using the tag in `platform.lock.json` and runs `pipx ensurepath`. Make targets work immediately, without reopening the terminal. Standalone CLI commands may need a new shell. The pinned platform tag must be published first.

## First deployment

Prerequisites: Python 3.10+, pipx, the platform CLI, Docker with a running daemon, kind **v0.33.0**, kubectl **v1.37.x**, Helm **v4.3.0**, make, Bash, curl, tar, OpenSSL, shasum, and Git. Use macOS or Linux (or Linux under WSL2). Allocate approximately 4 CPUs, 6 GiB RAM and 10 GiB free disk to Docker as a starting estimate. Initial downloads need network access. Node 24 is needed only for host-side tests and hot reload.

Install kind using the [official instructions](https://kind.sigs.k8s.io/docs/user/quick-start/#installation). The script also discovers tools in the ignored `.platform/bin` directory. Kubernetes is pinned to 1.37.0 and its image digest in the pinned platform release.

```sh
make doctor
make up
make open
```

Visit **http://localhost:4173**. Try the counter and both Greet buttons. Keep `make open` running; Ctrl-C stops both tunnels, not the application. Change `applications.web.localPort` in `platform.json` to change the frontend port. API port 8080 must be free because the unchanged browser bundle hardcodes localhost:8080.

`make up` creates or reuses the dedicated `testkube-platform` cluster, builds two images, loads them into kind, creates a database Secret if absent and verifies the pinned upstream database chart, installs or upgrades the separate `db`, `api` and `web` Helm releases, waits for readiness, and smoke-tests both services and the actual SQL result. Repeating it preserves database data and credentials. It does not change your default kubeconfig. Do not run concurrent mutations from multiple shells: this MVP uses a single local state directory.

## Everyday work

| Need | Command |
| --- | --- |
| Deploy changed source | `make deploy SERVICE=api` or `make deploy SERVICE=web` (omit SERVICE for both) |
| Explicitly install/upgrade local database | `make db-up` |
| Check deployed request path | `make check` |
| See pods, services and storage | `make status` |
| Follow API or web logs | `make logs` / `make logs SERVICE=web` |
| Gather events and recent logs | `make diagnose` |
| Inspect generated manifests | `make render` |
| List Helm release revisions | `make releases` |
| Restore a Helm release revision | `make rollback SERVICE=api REVISION=<number>` |
| Lint and validate chart configuration | `make chart-test` (isolated dependencies install automatically) |
| Run unit tests and compile frontend | `npm ci` then `make test` |
| Run browser tests (both tunnels running) | `make browser-test` |

Release tags include the Git revision, timestamp and process ID, so uncommitted edits produce a new image. Helm stores up to ten release revisions. `make rollback SERVICE=api REVISION=<number>` restores only the selected application release's manifests, values and image reference, then smoke-tests the result. It creates a new revision; it does not reset the history counter. Keep old application images available in kind (or a registry); if kind has garbage-collected a local image, reload it with `kind load docker-image --name testkube-platform <image:tag>` before rollback. The namespace, database Secret and database release are outside both application releases. Database contents, schema and volume resizing are not undone. Each application has independent history; deploying both is sequential and is not transactional. `make deploy` never upgrades the database. `make up` is the complete bootstrap; `make db-up` explicitly manages only the database. There is no automatic rollback; a failed Helm operation leaves evidence available for `make diagnose` and `make releases`.

`make check` uses its own temporary tunnels and checks the frontend HTML, named API greeting, actual PostgreSQL query result. It allows bounded HTTP retries for transient service-routing convergence after a rollout and cleans up its tunnels on exit, including failures. A persistent failure still exits nonzero. Browser tests additionally execute React and assert visible counter, API and database results.

## Faster local feedback

Kubernetes deployment is the integration loop. For hot reload, start a disposable development database and run the existing Vite/Node dev servers:

```sh
docker run --name sample-dev-db --rm -d -p 127.0.0.1:15432:5432 \
  -e POSTGRES_DB=api-db -e POSTGRES_USER=api-user \
  -e POSTGRES_PASSWORD=api-password postgres:17-bookworm
npm ci
npm run start
# When finished:
docker stop sample-dev-db
```

The original browser calls localhost:8080 directly. Local Kubernetes uses platform.json development credentials; shared deployments use GitHub environment secrets. A second option remains `docker compose up --build`, which uses the same web/API Dockerfiles. Do not run Compose, Vite and the Kubernetes tunnel on port 4173 simultaneously.

## Troubleshooting and recovery

All low-level commands explicitly select this cluster:

```sh
kubectl --kubeconfig .platform/kubeconfig --context kind-testkube-platform \
  -n testkube-sample get pods
```

| Symptom | First action | Likely issue |
| --- | --- | --- |
| `make doctor` fails | Start Docker; verify kind and kubectl and Helm versions | Missing tool, daemon stopped or inaccessible |
| Image load/build fails | Read build output; check Docker disk/network | Registry access, architecture or dependency failure |
| Pod Pending / PVC Pending | `make diagnose` | Insufficient memory or kind storage provisioner |
| API rollout times out | `make logs`; inspect PostgreSQL logs via diagnose | Database not ready or credentials mismatch |
| Page loads; database greeting fails | `make check`; `make diagnose` | Database availability or the missing API tunnel |
| Address already in use | Change web localPort in platform.json | Another tunnel or dev server; port 8080 must also be free |
| Tunnel stops after a redeploy | Restart `make open` | Port-forward was attached to a replaced web or API pod |
| Secret missing with existing PVC | Restore original Secret | Regenerating credentials cannot change an initialized database password |

If a Secret is lost while its database volume remains, restore its original POSTGRES_DB, POSTGRES_USER and POSTGRES_PASSWORD from your credential source. The platform no longer writes a local password file. Do not create new credentials for an already initialized volume.

Never commit `.platform`, paste the password into logs, or use the development defaults in shared environments. A Kubernetes Secret alone is not a production secret management solution. PostgreSQL's local application role is also the initialization superuser; production requires a separate, least-privileged application role.

## Demo and failure drill

1. Run `make up`, then `make open`; demonstrate the three UI interactions.
2. Run `make status` and `make check`; explain the browser-to-database request path.
3. Note the current web revision from `make releases`. Edit a UI heading, run `make deploy SERVICE=web`, restart the tunnel, and show the change.
4. Use `make rollback SERVICE=web REVISION=<number>` to restore the original release, then restart the tunnel and verify the UI.
5. Optionally simulate a database outage with the explicit-context command below. Observe the limitation: the API stays Ready and returns HTTP 200 with message "request failed" for database requests. Probes cannot distinguish this failure. Restore the database and run `make check`.

```sh
kubectl --kubeconfig .platform/kubeconfig --context kind-testkube-platform \
  -n testkube-sample scale statefulset/db --replicas=0
# Restore promptly after observing the failure:
kubectl --kubeconfig .platform/kubeconfig --context kind-testkube-platform \
  -n testkube-sample scale statefulset/db --replicas=1
make check
```

`make resilience` is an optional showcase command, excluded from delivery CI but included in the developer-invoked `make local-tests` suite. It automates a persistence and outage drill: it inserts a unique probe row, replaces the database pod, verifies the row, scales the database down, verifies the documented HTTP 200 failure body, unchanged readiness and restart count, and restores the database. An exit trap restores the database replica count if a check fails. Run only when no other demo operation is in progress; the drill temporarily interrupts database access. A PVC survives pod replacement; **it is not a backup**. Deleting the kind cluster loses its data.

## Cleanup

```sh
make down CONFIRM=testkube-platform
```

This deliberately deletes the dedicated local cluster and all its database data. The shared `testkube-samples` cluster remains running. Local Docker images, npm cache and `.platform` files remain for inspection. Treat `.platform/kubeconfig` as sensitive even after the cluster is removed. Current tooling does not create `.platform/database.env`; if an older checkout left that file behind, treat it as sensitive too.

## Chart configuration and migration

The shared chart lives in the pinned platform-tools package; `deploy/api.values.yaml` and `deploy/web.values.yaml` configure releases `api` and `web`. `db` uses a separately downloaded, version- and checksum-pinned upstream PostgreSQL chart, configured by `deploy/db.values.yaml`. See [platform chart documentation](https://github.com/taskovskig/platform-tools/tree/v0.8.0/helm).

Platform v0.2.0 supplies the default kind configuration and generates the namespace and database service account in `.platform/infrastructure/`. The names come from `platform.json`; the namespace retains restricted Pod Security and the service account disables token automount. Optional `kindConfig`, `namespaceManifest`, and `database.serviceAccountManifest` paths can override these defaults when required.

Database values are applied in order: platform defaults, `deploy/db.values.yaml`, then generated resource names and database Secret references. This application's file retains PostgreSQL `17-bookworm`; security, storage retention, and resource defaults now come from the platform release. Review database image upgrades separately from tooling upgrades. Helm merges maps but replaces lists, so an `env` override must include all required entries.

Existing combined release `testkube-sample`, legacy StatefulSet `postgres`, or its retained PVC cause bootstrap/deploy to stop before deployment changes. Helm ownership and immutable selectors cannot be safely transferred by renaming a release. For disposable local data, run `make down CONFIRM=testkube-platform`, then `make up`. For valuable data, take and verify a logical backup, deploy the new releases in a fresh cluster, restore into `db`, verify SQL and browser checks, then retire the old environment. Do not delete the old cluster before verifying the restore. No automatic adoption or data migration is implemented.

The new database PVC is `data-db-0`. Application rollback never touches it. Database chart and image upgrades require their own backup and compatibility review; the wrapper deliberately offers no generic database rollback command.

## Application ownership and existing installations

The developer Dockerfiles, root npm manifests and docker-compose.yaml are preserved. Application changes remain developer-owned: the web app now includes the visible Web visual update v1 badge, and the API reads DB_NAME, DB_USER and DB_PASSWORD from environment variables, with a corresponding unit test and original defaults for direct local execution. Application-specific acceptance tests live under tests/platform/. The generic chart checks and YAML parser dependency are owned by platform-tools. Builds use the developer Dockerfiles with an allowlisted tar context; local platform state cannot enter their COPY instructions.

The API and PostgreSQL now use matching Secret references for database name, username and password. Local deployments source these from platform.json; shared deployments require the selected GitHub environment secrets. A cluster from an earlier implementation may contain different credentials or a Secret without POSTGRES_DB. The wrapper refuses that mismatch instead of changing credentials on an existing PVC. Back up valuable data and plan a database migration; for disposable demo data, use make down CONFIRM=testkube-platform then make up. The original application also lacks database-aware readiness and reliable graceful shutdown; these need separately agreed application changes before production.

## Platform version and ownership

The platform team owns [platform-tools](https://github.com/taskovskig/platform-tools). This application owns `platform.json`, `deploy/`, `tests/platform/`, its documentation, and the platform release lock. CLI source, bootstrap tests and documentation rendering belong to `platform-tools`; there is no `tooling/` source directory in this application.

`make platform-fetch` retrieves exactly the Git tag and content manifest pinned in `platform.lock.json`. Downloads are checked before extraction is activated, and cached files are verified again before execution. No mutable branch is used. `make platform-version` shows the selected version. Public downloads need no credentials; private downloads can use an authenticated GitHub CLI with repository read access.

For an upgrade, the platform team updates VERSION, regenerates `distribution.json` with `python3 scripts/release.py`, commits the complete package, and publishes a new annotated tag. Never move published tags. The application team copies the emitted lock JSON into `platform.lock.json` and updates every reusable platform workflow reference in the same PR, including `.github/workflows/platform.yaml` and `.github/workflows/production.yaml`. The bootstrap rejects mismatched workflow and runtime pins. Both repositories must publish their changes in that order: platform tag first, then application consumer.

This application targets v0.8.0; publish the prepared platform release before pushing the consumer upgrade. For unpublished platform development, use `PLATFORM_TOOLS_DIR=../platform-tools make <target>` explicitly for platform commands. This bypasses release integrity checks for development and is forbidden in CI. The default download path never silently uses the sibling checkout. The platform repository README contains exact tagging instructions.

To roll back tooling, restore `platform.lock.json` and all reusable platform workflow references to the same earlier published release. Tooling rollback does not roll back Helm releases or database data. Review `platform.json` changes for compatibility with the chosen release. Rolling back to v0.1.0 also requires restoring the explicit kind, namespace, and database service-account files and their configuration paths, plus the full database values; revert the consumer migration together with the lock and all workflow references.

## Shared CI and development cluster

Feature pushes reset `app-ci` and run acceptance there. Merges to main promote
existing tested CI images into `app-dev`. GitHub environments use those exact
names and contain separate `KUBECONFIG` secrets. See [the delivery guide](DEVELOPMENT.md)
for setup, destructive CI reset behavior, image tags and promotion recovery.

Use `make local-tests` for developer-local end-to-end tests. It runs the original
local kind flow and leaves the cluster available for inspection. No workflow calls
this command or creates a disposable kind cluster. Production deployment uses the separate manual, approval-gated workflow described in [PRODUCTION.md](PRODUCTION.md).

### Render the design PDF

Install the CLI with its optional documentation dependency, then render explicitly:

```sh
pipx install --force 'platform-tools-cli[docs] @ git+https://github.com/taskovskig/platform-tools.git@v0.8.0'
platform-render-design PLATFORM-DESIGN.md PLATFORM-DESIGN.pdf
```

`platform-tools --version` shows the installed CLI; `make platform-version` shows this application's pinned platform release. The lock's `cliApiVersion` is checked before platform execution.

Database credentials now come from the local defaults in `platform.json` or the selected GitHub environment secrets. The API reads DB_NAME, DB_USER and DB_PASSWORD from the namespace-local Secret. See [database credential setup](DEVELOPMENT.md#database-credentials), including migration of old local Secrets.

## Identifying deployed application builds

With platform-tools v0.8.0, `helm ls` and `helm history` record the application
version for each API and web release. app-ci and app-dev display `ci-<run number>`;
app-dev still deploys the digest-pinned dev-latest image, but its APP VERSION shows
the original tested CI build. app-prod displays `prod-YYYYMMDDTHHMMSSZ`. Local
releases display their generated image tag. The CHART column continues to show
the shared chart version; PostgreSQL retains its upstream application version.

These values appear on the next deployment, without changing existing revisions.
A rollback restores the selected revision's recorded version and image. CI reruns
can reuse a run number, so use `helm get values api --all` (or web) and inspect the
image digest when an exact image identity is needed. Publish platform-tools
v0.8.0 before pushing this consumer upgrade.
