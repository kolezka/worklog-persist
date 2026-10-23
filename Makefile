# Makefile: one entry point for this plugin repo.
#
# Each recipe line is its own shell (no .ONESHELL), so multi-step recipes chain
# with && or run as one-line loops. `make` with no target prints the list.

SHELL := /bin/bash

# install.sh records this checkout's path in the claude CLI registry. From a
# linked worktree that path is deleted with the branch.
define require_main_checkout
	@test "$$(git rev-parse --git-dir)" = "$$(git rev-parse --git-common-dir)" || { \
	  echo "REFUSING: this is a linked worktree ($$(git rev-parse --git-dir))."; \
	  echo "  Run install targets from the main checkout."; \
	  exit 1; }
endef

.DEFAULT_GOAL := help

.PHONY: help
help: ## This list
	@echo "Targets:"
	@grep -hE '^[a-z][a-z0-9._-]*:.*?## ' $(MAKEFILE_LIST) \
	  | sort | awk 'BEGIN{FS=":.*?## "}{printf "  \033[1m%-12s\033[0m %s\n", $$1, $$2}'

# ── verify ───────────────────────────────────────────────────────────────

.PHONY: test
test: ## Python suite (redaction, docs layout)
	env -u FORCE_COLOR uv run pytest -q

.PHONY: test-sh
test-sh: ## Shell suites (identity, off switch, structure, installer)
	@# Not collected by pytest, so `make test` never runs them.
	@fail=0; for t in tests/*.sh; do \
	  if out=$$(bash "$$t" 2>&1); then printf '  ok   %s\n' "$$t"; \
	  else fail=1; printf '  FAIL %s\n%s\n' "$$t" "$$out"; fi; \
	done; exit $$fail

.PHONY: lint
lint: ## shellcheck every shell file, at warning severity
	uvx --from shellcheck-py shellcheck -S warning install.sh scripts/*.sh tests/*.sh

.PHONY: check
check: test test-sh ## Everything offline: both suites plus the structure check
	./install.sh --check

.PHONY: test-native
test-native: ## Native panel: validate the plugin, run its engine tests (needs the claude CLI)
	@command -v claude >/dev/null || { echo "FAIL: claude CLI not found; native tests did not run"; exit 1; }
	claude plugin validate .
	claude plugin test .

.PHONY: typecheck-native
typecheck-native: ## Type-check hooks/ and tests/ against TYPES=<claude-code.d.ts>
	@test -f "$(TYPES)" || { echo "FAIL: set TYPES to this build's claude-code.d.ts (see docs/verification/OPERATIONS.md)"; exit 1; }
	@command -v pnpm >/dev/null || { echo "FAIL: pnpm not found; the type-check did not run"; exit 1; }
	@dir=$$(mktemp -d) && root=$$(pwd) && printf '%s\n' \
	  '{"compilerOptions":{"target":"es2023","lib":["es2023"],"types":[],"module":"esnext",' \
	  '"moduleResolution":"bundler","strict":true,"noUncheckedIndexedAccess":true,"noEmit":true,' \
	  '"skipLibCheck":true,"jsx":"react","jsxFactory":"h","jsxFragmentFactory":"Fragment"},' \
	  "\"files\":[\"$(TYPES)\"],\"include\":[\"$$root/hooks\",\"$$root/types\",\"$$root/tests/*.tsx\"]}" \
	  > "$$dir/tsconfig.json" && pnpm --package=typescript@5.6.3 dlx tsc -p "$$dir/tsconfig.json"

.PHONY: live
live: ## Opt-in reachability check against the real Outline endpoint
	WORKLOG_PERSIST_LIVE=1 bash tests/test_live_outline.sh

# ── install ──────────────────────────────────────────────────────────────

.PHONY: plan
plan: ## Print what `make install` would run. Changes nothing
	./install.sh

.PHONY: install
install: ## Register the marketplace and install the plugin
	$(require_main_checkout)
	./install.sh --apply
