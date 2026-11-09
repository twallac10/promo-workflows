# Shared by the guardrail scripts. Run inside the base (main) checkout.
fail() { echo "guardrail: $*" >&2; exit 1; }
# Files the PR changes (relative to the merge base). --no-renames: a move lists
# both paths, so moving a prd, base/ or .github/ file elsewhere still counts there.
changed_files() { git diff --no-renames --name-only "$1...$2"; }
