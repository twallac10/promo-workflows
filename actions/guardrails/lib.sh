# Shared by the guardrail scripts. Run inside the base (main) checkout.
fail() { echo "guardrail: $*" >&2; exit 1; }
# Files the PR changes (relative to the merge base).
changed_files() { git diff --name-only "$1...$2"; }
