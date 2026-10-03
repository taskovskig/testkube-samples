.DEFAULT_GOAL := help
# Resolve pipx's executable directory even before ensurepath takes effect.
PLATFORM ?= $(shell command -v platform-tools 2>/dev/null || { cli_bin=$$(pipx environment --value PIPX_BIN_DIR 2>/dev/null); if [ -n "$$cli_bin" ]; then printf '%s/platform-tools' "$$cli_bin"; else printf 'platform-tools'; fi; })
.PHONY: setup platform-cli-check help platform-fetch platform-version doctor up ci-reset ci-up ci-passed promote local-tests db-up deploy rollback render check open status logs diagnose releases down test resilience chart-test helm-test browser-test install-tools browser-ci
help:
	@echo 'make setup    Install/update the pinned platform CLI (requires pipx)'
	@echo 'make platform-fetch | platform-version   Fetch or inspect pinned platform tag'
	@echo 'make up | open | check | status | releases'
	@echo 'make local-tests    Developer-only local acceptance (never used by workflows)'
	@echo 'PLATFORM_ENVIRONMENT=app-ci KUBECONFIG=<file> make ci-reset | ci-up'
	@echo 'PLATFORM_ENVIRONMENT=app-dev KUBECONFIG=<file> make promote'
	@echo 'make deploy SERVICE=api    Deploy one application (omit SERVICE for both)'
	@echo 'make rollback SERVICE=api REVISION=<number>'
	@echo 'make db-up | logs SERVICE=db | diagnose'
	@echo 'make test | chart-test | helm-test | resilience | browser-test'
	@echo 'make down CONFIRM=testkube-platform    Delete cluster and its data'
setup:
	@command -v pipx >/dev/null 2>&1 || { echo 'Install pipx first, then run make setup.' >&2; exit 1; }
	@set -e; source=$$(python3 -c 'import json,re; c=json.load(open("platform.lock.json")); r=c["repository"]; t=c["tag"]; assert re.fullmatch(r"[\w.-]+/[\w.-]+",r) and re.fullmatch(r"v\d+\.\d+\.\d+(?:-[\w.-]+)?",t), "Invalid platform repository or tag"; print("git+https://github.com/"+r+".git@"+t)'); \
		pipx install --force "$$source"; \
		pipx ensurepath
	@echo 'CLI installed. Make targets work in this terminal; standalone commands may need a new shell.'
platform-cli-check:
	@command -v "$(PLATFORM)" >/dev/null 2>&1 || { echo 'Run make setup to install the platform CLI.' >&2; exit 1; }
platform-fetch: | platform-cli-check
	@"$(PLATFORM)" fetch
platform-version: | platform-cli-check
	@"$(PLATFORM)" version
doctor up ci-reset ci-up ci-passed promote local-tests db-up deploy rollback render check open status logs diagnose releases down resilience chart-test helm-test install-tools browser-ci: | platform-cli-check
	@"$(PLATFORM)" $@
test:
	npm run test --workspace=testkube-sample-api
	npm run build --workspace=testkube-sample-web
browser-test:
	@CYPRESS_BASE_URL=$$(node -p "'http://localhost:' + require('./platform.json').applications.web.localPort") && \
		export CYPRESS_BASE_URL && \
		npm run test:e2e --workspace=testkube-sample-web && \
		./node_modules/.bin/cypress run --project tests/platform
