# Production releases

Production is a manual, two-job workflow. It promotes existing application images; it never builds them. The reusable implementation is in platform-tools and the application trigger is `.github/workflows/production.yaml`.

## Prerequisites and first run

1. Publish platform-tools v0.8.0, then merge the matching application pins and production configuration into main.
2. Wait for that main commit's **Platform delivery** workflow to succeed. It deploys dev-latest and writes an internal dev-passed marker only after rollout and HTTP checks succeed. Older tooling did not write this marker.
3. Keep the app-prod environment's protection rules and KUBECONFIG, DB_NAME, DB_USER and DB_PASSWORD secrets configured. Restrict its deployment branches to main. The kubeconfig must target kind-testkube-samples with access to app-prod; namespace/RBAC provisioning remains separate.
4. In Actions, select **Production release**, choose **Run workflow**, and select **main**. A dispatch from another branch is skipped. This implementation releases the selected main commit only; a newer main commit without successful development delivery is rejected.

The first release compares against `productionRelease.initialBaseline` in platform.json. Its default is the original application baseline d7754b564e61b38149f6cc264fa073b308c1e2f5, so the merged platform PR is included. Subsequent releases use the source commit in the previous published production release's manifest.

## Job 1: publication (no environment)

This job has repository/package write and Actions/PR read permission, but no GitHub environment or cluster credential configuration. It:

- Requires a successful main delivery run for the selected commit.
- Pulls each dev-latest image and verifies it matches dev-passed, the selected main source tree, and the other application's CI build identity.
- Saves the exact digests, source commit, run ID and previous source in a `release.json` asset on a draft GitHub Release.
- Tags those images `prod-YYYYMMDDTHHMMSSZ` and `latest`, using UTC and one timestamp for all applications. The timestamp is derived from the workflow run creation time and remains stable across retries.
- Publishes the GitHub Release and source Git tag. Notes list merged PR titles/links whose merge commits are in the source delta, plus a full comparison link and image digests. Direct commits are visible in the comparison link; they do not invent PR entries.

The GitHub Release and latest image aliases exist **before deployment approval**. They mean published, not deployed. A rejected or failed deployment leaves those artifacts published. The next notes delta is from the previous published production release, whether or not it reached the cluster.

## Job 2: approved deployment

This job depends on publication and selects **environment: app-prod**, so GitHub applies that environment's protection rules before the job starts. Review the release notes and images, then approve through the workflow's environment review UI.

After approval, the job reads only app-prod's cluster/database secrets. It verifies the release manifest checksum passed by job 1, the source commit, release identity, image repositories and digests. It rejects older releases if a newer production release record exists. It never resolves latest or dev-latest again.

The job installs or upgrades db, api and web in app-prod, preserving PostgreSQL data. It deploys the application's prod timestamp tags with their exact recorded digests, waits for rollout and runs HTTP checks including the database-backed API response. Failure diagnostics run without modifying image aliases. Production unit/browser/Helm mutation/resilience tests are not run here. GitHub's app-prod deployment status records the outcome.

## Concurrency, retries and recovery

Production uses the **same workflow concurrency group as feature CI and development promotion**, with running cancellation disabled. This prevents moving image aliases or namespace mutations from overlapping release creation/deployment. The lock is held while approval is pending: CI and development are blocked until approval, rejection, or cancellation. GitHub retains only one pending run per group and can replace older pending runs. Coordinate release approvals promptly and rerun a replaced required CI check when needed.

A failed publication may leave a draft release and some image tags. Rerun the same workflow: once release.json exists it reuses the saved digest snapshot, not new moving tags. Publishing an already-published run does not move aliases again. A tag collision or changed manifest fails closed. Do not edit/remove release assets or move production tags.

If only deployment failed, use **Re-run failed jobs** to keep the original publication outputs. Approval is governed by app-prod's rules on each attempt. If a newer production release exists, an older run cannot be retried as a rollback. Deliberate rollback needs a separately reviewed operation; do not delete newer release records to bypass this check.

Database credentials initialize fresh data. Changing environment secrets does not rotate an existing PostgreSQL database. A mismatch stops deployment; coordinate database/Secret migration separately. Application upgrades are sequential, not an atomic multi-release transaction, and failed deployment does not automatically roll back every release.
