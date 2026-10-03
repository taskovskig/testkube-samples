#!/usr/bin/env bash
# Application-owned expectation: the original API returns 200 even on DB failure.
set -euo pipefail
kubectl --kubeconfig "$KUBECONFIG_FILE" --context "${KUBE_CONTEXT:-kind-$CLUSTER}" -n "$NAMESPACE" \
  exec "$1" -- node --input-type=module -e '
const hello = await fetch("http://127.0.0.1:8080/hello", {signal: AbortSignal.timeout(10000)});
if (hello.status !== 200) throw new Error("Greeting unavailable during DB outage");
const response = await fetch("http://127.0.0.1:8080/hello-pg", {signal: AbortSignal.timeout(10000)});
const body = await response.json();
if (response.status !== 200 || body.message !== "request failed") throw new Error("Unexpected database failure contract");
'
