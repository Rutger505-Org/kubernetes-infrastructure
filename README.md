# Kubernetes Infrastructure

This repository hosts all required resources in a kubernetes cluster to start deploying my applications. 
Including the GitHub Actions for preview deployments and linting and such.

## Application deployments

Apps call the reusable `.github/workflows/deployments.yaml` workflow on pull requests and on pushes to `main`.

- Push to `main` → production on `<BASE_DOMAIN>`, OpenTofu workspace `production`.
- Pull request → preview on `pr-<number>.<BASE_DOMAIN>`, OpenTofu workspace `pr-<number>`. Closing the PR destroys it.
- Both use Let's Encrypt production certificates. To tell environments apart in an app's OpenTofu, use `terraform.workspace == "production"`.
