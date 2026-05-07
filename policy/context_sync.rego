package context_sync

# Enforces that any modification to src/ is accompanied by updates to
# docs/JOURNEY.md and CLAUDE.md. Prevents documentation drift.

default allow = false

allow {
	not input.src_changed
}

allow {
	input.src_changed
	input.journey_updated
	input.claude_updated
}

deny[msg] {
	input.src_changed
	not input.journey_updated
	msg := "POLICY VIOLATION: src/ was modified but docs/JOURNEY.md was not updated. Every source change must be accompanied by a timestamped JOURNEY.md entry documenting the session intent, actions taken, and validation results."
}

deny[msg] {
	input.src_changed
	not input.claude_updated
	msg := "POLICY VIOLATION: src/ was modified but CLAUDE.md was not updated. If the system architecture or dependencies changed, CLAUDE.md must reflect those changes."
}
