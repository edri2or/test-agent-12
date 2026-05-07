package adr

# Enforces that any modification to terraform/ or docs/adr/ is accompanied
# by a new or updated Architectural Decision Record (ADR) in docs/adr/.
# Prevents infrastructure changes from proceeding without documented rationale.

default allow = false

allow {
	not input.terraform_changed
}

allow {
	input.terraform_changed
	input.adr_updated
}

allow {
	not input.terraform_changed
	input.adr_updated
}

deny[msg] {
	input.terraform_changed
	not input.adr_updated
	msg := "POLICY VIOLATION: terraform/ was modified but no ADR was added or updated in docs/adr/. Infrastructure changes require an Architectural Decision Record documenting: context, options considered, decision outcome, and consequences. Use docs/adr/template.md as a starting point."
}

deny[msg] {
	file := input.changed_files[_]
	startswith(file, "docs/adr/")
	not startswith(file, "docs/adr/template")
	not contains(file, "0001")
	not _is_valid_adr_filename(file)
	msg := sprintf("POLICY VIOLATION: ADR file '%v' does not follow naming convention. Expected format: docs/adr/NNNN-kebab-case-title.md (e.g., docs/adr/0002-database-selection.md)", [file])
}

_is_valid_adr_filename(path) {
	parts := split(path, "/")
	filename := parts[count(parts) - 1]
	regex.match(`^\d{4}-[a-z0-9-]+\.md$`, filename)
}
