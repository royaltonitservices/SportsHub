# Makefile — local developer shortcut for Phase 9 coherence checks.
# Run `make check` to execute all checks against the current working tree.
# Each check also runs independently in CI via .github/workflows/coherence_checks.yml.
#
# Usage:
#   make check                  — run all checks
#   make check-fake-delays      — fake delay stub detection
#   make check-empty-actions    — empty swipeActions detection
#   make check-hardcoded-cdn    — hardcoded external URL detection
#   make check-todo-handlers    — TODO/FIXME in action closures
#   make validate-contract      — Phase 7 API contract validator

.PHONY: check check-fake-delays check-empty-actions check-hardcoded-cdn check-todo-handlers validate-contract

check: check-fake-delays check-empty-actions check-hardcoded-cdn check-todo-handlers validate-contract

check-fake-delays:
	@bash scripts/check_fake_delays.sh

check-empty-actions:
	@bash scripts/check_empty_actions.sh

check-hardcoded-cdn:
	@bash scripts/check_hardcoded_cdn.sh

check-todo-handlers:
	@bash scripts/check_todo_action_handlers.sh

validate-contract:
	@bash validate_api_contract.sh
