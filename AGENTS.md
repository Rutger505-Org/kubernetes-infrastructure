# kubernetes-infrastructure

K3s cluster add-ons + the reusable app deploy workflow. Usage: README.md; per-module details: `<N>-<module>/README.md`.

## Layout
- One numbered dir per module (`0-cert-manager` … `7-monitoring`), each a **standalone OpenTofu root**: backend `"kubernetes"` with its own `secret_suffix`, `config_path = "~/.kube/config"`. Gaps in numbering are removed modules (6 = Traefik, now configured by homelab-infrastructure's k3s role).
- `.github/workflows/deploy-infrastructure.yaml`: applies **every module in order on every push to main** (no path filter, so a docs-only merge also runs a full apply) + workflow_dispatch.
- `.github/workflows/deployments.yaml`: reusable workflow apps call (`workflow_call`); production on push to main, `pr-<n>` previews.
- `.github/actions/setup-kubernetes`; `with-post-step` is vendored (pyTooling).
- Cluster/VM side (k3s, Traefik IP + HTTP/3, SeaweedFS VM, Caddy, CA bundle) lives in Rutger505-Org/homelab-infrastructure.

## Rules
- Branch from `origin/main`, PR, squash-merge. **Merge = deploy.** No tags/releases.
- CI steps are inline bash+jq `run:` blocks, same style as `deployments.yaml`. No new `.mjs` or `actions/github-script`.
- Per-env values + secrets are variables, passed as `TF_VAR_*` from `vars.*`/`secrets.*` in the module's workflow step. Never hardcode test values.
- Pin Helm chart versions. Versions: `curl -s https://<repo>/index.yaml`; read `values.yaml` from the tarball URL in the index (may be GitHub release assets).

## MetalLB IPs
- Pool `METALLB_IP_ADDRESSES` (repo var) = `192.168.178.230-250`, `autoAssign = false`: a LoadBalancer Service without an explicit IP gets none.
- Pick by hand. Taken: `.230` Traefik (homelab-infrastructure `k3s_traefik_ip`), `.231` Grafana (`7-monitoring` `grafana_load_balancer_ip`), `.233` relay LiveKit media (relay `deploy/main.tf`), `.234` finance (finance `deploy/main.tf`). Free: `.232`, `.235`+.
- IPs are claimed across repos; check the live cluster too: `kubectl get svc -A | grep LoadBalancer`.

## Add a module
1. New `N-<service>/`: `main.tf`, `variables.tf`, `outputs.tf`, `README.md`. Copy the closest sibling; providers/backend verbatim, new `secret_suffix`.
2. Step in `deploy-infrastructure.yaml` in module order, every variable as `TF_VAR_*`.
3. Create repo vars/secrets **before merging**, else apply gets empty strings: `gh variable set NAME --body ...`; `printf '%s' <value> | gh secret set NAME`. A placeholder secret is fine if a mode doesn't read it.
4. Validate against the cluster, not the green check.

## Remove a module + its data
Apply-only CI: deleting the dir orphans releases, namespace, PVC. Destroy first, delete second:
1. PR 1: switch the step to `tofu destroy -input=false -auto-approve`, keep dir + `TF_VAR_*`. State in the PR that PVC data is destroyed permanently.
2. Merge. Steps run sequentially without `if: always()`: an earlier failing module **skips** the destroy (`gh run view <id>` shows `-`, not failure).
3. Read the destroy log. `Destroy complete! Resources: 0 destroyed.` after a clean refresh = already gone. Confirm from the LAN (closed port).
4. PR 2: delete dir + step; `grep -ri <service> README.md .github/` must be empty. Delete orphaned `<SERVICE>_*` vars/secrets.

## Debugging
- Read-only kubeconfig: `4-rbac` (README there). Covers pods, logs, events, deployments, replicasets, statefulsets, services, namespaces, PVCs, node/pod metrics, Prometheus service proxy. **Not** nodes, secrets, configmaps, deletes. Widen via PR on `4-rbac/main.tf`.
- Broken service: first prove what's deployed. `git fetch --all` (stale `origin/main` invents phantom bugs), check PR status and that the fix's deploy run succeeded. A fix often already exists.
- LAN probe: `timeout 5 bash -c 'cat </dev/null >/dev/tcp/<ip>/<port>' && echo OPEN`. Service IP also shows in its `IPAllocated` event.
- Timers/delays: make the delay a `TF_VAR_*` from a repo var, set short (2m), verify in logs, restore and redeploy.

## Pitfalls
- New fix branched from a squash-merged branch → CONFLICTING PR. Fix: `git rebase --onto origin/main HEAD~1`, force-push.
- Green apply ≠ pod changed. StatefulSet with `OnDelete` never replaces the pod; use `RollingUpdate` for CI-changed templates.
- `RollingUpdate` won't replace an unready (CrashLoopBackOff) pod: `kubectl get sts <name> -o jsonpath='{.status}'` shows `currentRevision ≠ updateRevision`, `availableReplicas 0`. Only fix: `kubectl -n <ns> delete pod <pod>` with an admin kubeconfig. Retrying the deploy doesn't help.
- Pending with `Insufficient memory`: lower `resources.requests`; node capacity isn't readable with the read-only kubeconfig.
- Aborting a running apply can leave a module's state lock held (workflow queues, never cancels).
