# Testkube Sample Application

A sample 3-tier application to run tests on.
The application is composed of a React frontend, NodeJs backend and a PostgreSQL database.

It can be used to showcase Testkube tests workflows.

![Testkube Sample Application](./docs/images/app.png)

## Kubernetes developer platform

Start with the [platform design and critical analysis](PLATFORM-DESIGN.md),
or its [shareable PDF](PLATFORM-DESIGN.pdf),
then follow the [developer guide and demo runbook](DEVELOPER-GUIDE.md).
See [validation evidence](VALIDATION.md) for what has actually been tested.

Install the platform CLI once (Python 3.10+, Git and pipx required):

```sh
make setup
make platform-version
```

`make setup` installs or replaces the CLI using the tag in `platform.lock.json` and runs `pipx ensurepath`. Make targets work immediately, without reopening the terminal. Standalone CLI commands may need a new shell. The pinned platform tag must be published first.

With the CLI, Docker, kind, kubectl and Helm 4.3 installed:

```sh
make platform-fetch
make platform-version
make up
make open
```

Open http://localhost:4173. Keep port 8080 available for the API tunnel.
The platform preserves the application files and Dockerfiles from `main`;
the browser requires localhost API access; the API now accepts environment-specific database credentials. The shared Helm chart and runtime are owned by [platform-tools](https://github.com/taskovskig/platform-tools).
The original files in `apps/api/k8s/` are retained as historical examples only.

The shared application chart has separate `api` and `web` releases. PostgreSQL
is a separate `db` release using a pinned upstream chart. Values live in `deploy/`.
Use `make deploy SERVICE=api` or `make deploy SERVICE=web` for independent updates;
`make db-up` explicitly manages the database.

Inspect release history with `make releases`. Restore one application revision with
`make rollback SERVICE=api REVISION=<number>`, then run `make open` again if its pod was replaced.
Use `make chart-test` to validate configuration; its isolated test dependencies install automatically.

### Stopping the local environment

Press **Ctrl+C** in the terminal running `make open` to stop both local tunnels.
The application and cluster keep running until you remove them:

```sh
make down CONFIRM=testkube-platform
```

**This deletes the local Kubernetes cluster, the application, and its PostgreSQL
data.** Docker Desktop remains running and can be quit separately. Run `make up`
to recreate the environment, then `make open` to access the application.

## Running the application

You can either use docker-compose.yaml:

```
docker compose up --build
```

Or run it locally:

```
npm run start
```

When running locally you should start your own PostgreSQL database.
There are many ways to do this, one suggestion is to use Docker:

```
docker run --name testkube-sample-db \
  -p 127.0.0.1:15432:5432 \
  -e POSTGRES_DB=api-db \
  -e POSTGRES_USER=api-user \
  -e POSTGRES_PASSWORD=api-password \
  --rm -d postgres:17-bookworm
```

## Running tests

Unit tests can be executed without a running appliction:

```
npm run test
```

For E2E test, you should first run the application as described above:

```
npm run test:e2e
```

## Versioned platform tooling

`platform.lock.json` pins `taskovskig/platform-tools` to a tag and content manifest checksum. The installed `platform-tools` CLI downloads that tag and verifies every packaged file before use. The shared Helm chart is included in the same release. CI calls the reusable workflow at the same tag. The platform tag must be published before normal download or hosted CI can work; unpublished tags never fall back to a branch or local checkout.

The pinned platform release supplies kind configuration, namespace and database service-account generation, and database infrastructure defaults. Application-specific configuration lives in `platform.json` and `deploy/`; `deploy/db.values.yaml` keeps the PostgreSQL image version and database name explicit. Browser and outage acceptance checks live in `tests/platform/`. For explicit pre-release development only:

```sh
PLATFORM_TOOLS_DIR=../platform-tools make chart-test
PLATFORM_TOOLS_DIR=../platform-tools make up
```

The override is rejected in CI. See [the developer guide](DEVELOPER-GUIDE.md#platform-version-and-ownership) for upgrades and first-release publication.

## Shared-cluster delivery

Feature branch pushes reset and test applications in `app-ci`, publishing
`ci-<run number>` and `ci-latest` images. Main promotes matching tested images to
`dev-latest` and upgrades `app-dev` without rebuilding. `app-prod` is deployed through the manually triggered, approval-gated [production release workflow](PRODUCTION.md).
Workflows use the existing cluster; `make local-tests` runs the developer-only
local kind acceptance flow. See [delivery setup and operations](DEVELOPMENT.md)
for v0.7.0 publication, environment secrets, reset semantics and promotion checks.
