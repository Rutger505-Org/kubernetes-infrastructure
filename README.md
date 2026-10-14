# Kubernetes Infrastructure

Cluster add-ons (numbered dirs, applied in order by `.github/workflows/deploy-infrastructure.yaml`) and the reusable workflows apps deploy with.

## Application deployments

Apps call `.github/workflows/deployments.yaml`:

- Push to `main`: production on `<BASE_DOMAIN>`, OpenTofu workspace `production`.
- Pull request: preview on `pr-<number>.<BASE_DOMAIN>`, workspace `pr-<number>`, destroyed when the PR closes.
- Both get Let's Encrypt production certificates. Tell them apart with `terraform.workspace == "production"`.
