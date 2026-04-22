# Secure Claude Baseline — developer Makefile.
# Mirrors what .github/workflows/ci.yml runs, so `make` locally == CI.
#
# Required tools: bash, jq, perl, curl, shellcheck, yq.
# Optional:       sqlite3, gitleaks (self-test falls back without them).

SHELL              := /usr/bin/env bash
GITLEAKS_VERSION   ?= 8.18.4
SHELLCHECK_EXCLUDE := SC1091

SHELL_SCRIPTS := \
	bootstrap.sh \
	secure-claude/.claude/hooks/*.sh \
	secure-claude/.claude/hooks/lib/*.sh

.PHONY: help test verify lint shellcheck validate-json validate-yaml gitleaks \
        install-local install-global dry-run clean

help:
	@echo "Secure Claude Baseline — developer targets"
	@echo
	@echo "  make test             shellcheck + validate-json + validate-yaml + verify"
	@echo "  make verify           ./bootstrap.sh --verify (all hook behaviour tests)"
	@echo "  make lint             alias for shellcheck"
	@echo "  make shellcheck       lint every bash script in the repo"
	@echo "  make validate-json    jq empty every *.json"
	@echo "  make validate-yaml    yq '.' every *.yml / *.yaml"
	@echo "  make gitleaks         run gitleaks against the working tree"
	@echo "  make install-local    install the baseline into \$$PWD"
	@echo "  make install-global   install the baseline into ~/.claude"
	@echo "  make dry-run          ./bootstrap.sh --local . --dry-run"
	@echo "  make clean            remove generated files (settings.json.bak.*)"

test: shellcheck validate-json validate-yaml verify

verify:
	./bootstrap.sh --verify

lint: shellcheck

shellcheck:
	shellcheck --severity=warning --exclude=$(SHELLCHECK_EXCLUDE) $(SHELL_SCRIPTS)

validate-json:
	@set -e; for f in $$(find . -name '*.json' -not -path './node_modules/*' -not -path './.git/*'); do \
		echo "→ $$f"; jq empty "$$f"; \
	done

validate-yaml:
	@set -e; for f in $$(find . \( -name '*.yml' -o -name '*.yaml' \) -not -path './.git/*'); do \
		echo "→ $$f"; yq '.' "$$f" > /dev/null; \
	done

gitleaks:
	@command -v gitleaks >/dev/null 2>&1 || { \
	  echo "gitleaks not installed. Install v$(GITLEAKS_VERSION) — see README.md § Prerequisites."; exit 1; }
	gitleaks detect --source . --no-banner --redact

install-local:
	./bootstrap.sh --local "$(CURDIR)"

install-global:
	./bootstrap.sh --global

dry-run:
	./bootstrap.sh --local . --dry-run

clean:
	find . -maxdepth 3 -name 'settings.json.bak.*' -print -delete
