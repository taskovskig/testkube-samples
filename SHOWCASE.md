# Local testing and showcase guide

Run the steps in order from the repository root. See the [developer guide](DEVELOPER-GUIDE.md) for prerequisites and troubleshooting.

```sh
cd /path/to/your/testkube-samples
```

## 1. Install the platform CLI and dependencies

Python 3.10+ and pipx are required for the CLI; Node 24 is required for the tests.
Use the default local environment for this showcase, with `CI` and
`PLATFORM_ENVIRONMENT` unset.

```sh
make setup
npm ci
npx cypress install
```

Fetch the platform tag pinned in `platform.lock.json` (it must already be published):

```sh
make platform-fetch
make platform-version
```

For an unpublished local platform checkout, prefix platform commands with `PLATFORM_TOOLS_DIR=../platform-tools`, for example `PLATFORM_TOOLS_DIR=../platform-tools make up`.

For a single-command acceptance run after CLI setup, start Docker and run
`make local-tests` instead of the individual test/deployment steps below. It
installs test dependencies, runs the same local acceptance stages, manages its
own browser tunnels, and leaves the cluster running. Stop any existing tunnels
first. After it passes, use `make open` for manual browsing and follow the cleanup
step when finished.

## 2. Run application and chart checks

```sh
make test
make chart-test
```

`make test` runs two API unit tests (the original greeting test and the environment database credential test) and builds the frontend with TypeScript and Vite. `make chart-test` lints the shared Helm chart and checks its rendered resources, configuration and release isolation.

## 3. Deploy to the local cluster

Start Docker Desktop, then run:

```sh
make doctor
make up
make status
```

`make up` creates or reuses the dedicated kind cluster, builds the application images, installs the separate `db`, `api` and `web` releases, and checks the frontend HTML, API greeting and actual database query response.

Expect all three workloads to be ready. To repeat just the deployed smoke checks:

```sh
make check
```

## 4. Test rollback and database recovery

Run these sequentially, without another deployment in progress:

```sh
make helm-test
make resilience
```

`make helm-test` upgrades and rolls back each application independently, checking that the other application and database release remain unchanged.

`make resilience` verifies that a SQL row survives database pod replacement, temporarily stops the database, and restores it. The API stays Ready and returns HTTP 200 with a failure message during the outage; the test explicitly checks this limitation and verifies recovery afterward.

## 5. Run browser tests and demonstrate the UI

In the first terminal, keep both local tunnels running:

```sh
make open
```

Ports **4173** and **8080** must be available. In a second terminal, from the same repository root, run:

```sh
make browser-test
```

Expect **1 original browser test and 3 platform browser tests** to pass.

Visit **http://localhost:4173** to demonstrate the application manually:

1. Confirm the teal **Web visual update v1** badge appears below the heading.
2. Click the counter and confirm it increments.
3. Enter a name and click the API greeting button.
4. Click the database greeting button and confirm the PostgreSQL greeting appears.

Keep `make open` running while using the browser. If a deployment replaces a pod and closes a tunnel, restart `make open`.

## 6. Clean up

Press **Ctrl+C** in the terminal running `make open` to stop both tunnels. Then run:

```sh
make down CONFIRM=testkube-platform
```

**This deletes the local cluster and its database data.** Docker Desktop remains running. Run `make up` again when you want a new environment.

## If a check fails

Stop at the failing step and keep its output. For a running cluster, gather diagnostics with:

```sh
make diagnose
```

Consult the [developer guide](DEVELOPER-GUIDE.md) before retrying or deleting an environment containing data you want to keep.
