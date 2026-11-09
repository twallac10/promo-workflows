# promo-workflows

Reusable workflows (`workflow_call`) for the promo demo app repos. Callers pin by tag (`VERSION`).

- `mirror.yaml`: mirror upstream chart into a wrapper, push to GHCR, open the first-tier PR.
- `promote.yaml`: on a Flux `repository_dispatch` event, validate it, check it against `main`,
- `actions/guardrails`: composite action behind each app repo's `promotion-gate` check (PR classification, files,
  release, evidence, sources, gitleaks). Called from the app repo's `gate.yaml`.
  record a Deployment, and open the promotion PR (success) or the revert PR (failure in a
  rollback tier). Logic lives in `actions/promote/*.sh`; `tests/run.sh` tests it.
