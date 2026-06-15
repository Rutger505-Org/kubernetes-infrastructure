# 4-rbac

Read-only RBAC for debugging deployments without exposing secrets, exposed as a
**permanent kubeconfig** (like the admin one, but with far fewer rights).

It creates:

- a `readonly` namespace (anchors the service account, holds no workloads),
- a `readonly` service account,
- a `log-reader` **ClusterRole** granting `get/list/watch` on `pods`,
  `pods/log`, `events`, `deployments` and `replicasets` across **all**
  namespaces (including dynamic `pr-*` preview namespaces),
- a ClusterRoleBinding tying the two together,
- a long-lived `readonly-token` secret holding a non-expiring token for the
  service account.

The role intentionally **does not** include `secrets` or `configmaps`, so a
holder can inspect why a pod fails to become ready (crash loops, image pull
errors, failing probes) without reading sensitive data. RBAC is default-deny —
only the verbs/resources listed above are allowed.

## Getting the kubeconfig

The module is applied automatically by the tag-deploy GitHub Action, which also
writes the Tofu state into the cluster (`backend "kubernetes"`,
`secret_suffix = "rbac"`). CI does **not** hand you the kubeconfig as a file —
this repo is public, so the credential must never land in Action artifacts or
logs. Instead you pull it afterwards from your own machine.

The API server URL is baked in via the `cluster_endpoint` variable (defaults to
the Tailscale-exposed endpoint). With your normal **admin** kubeconfig (needed
to read the remote state):

```bash
cd 4-rbac
tofu init
tofu output -raw kubeconfig > readonly.kubeconfig
KUBECONFIG=readonly.kubeconfig kubectl get pods -A
```

No re-apply is needed — `tofu output` just reads the state CI already wrote.

That file is a normal, **non-expiring** kubeconfig — keep it like your admin one,
hand it to whoever (or whatever agent) needs to debug. It can read pods/logs/
events cluster-wide and nothing else.

## Security notes

- The token does **not** expire. To revoke it, delete the `readonly-token`
  secret (and re-apply to mint a fresh one) — that immediately invalidates any
  kubeconfig built from it.
- `pods/log` is granted cluster-wide. The role can't read `secrets`, but
  application logs can still contain sensitive data an app chose to log. That's
  inherent to log access, not specific to this setup.
