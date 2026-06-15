# 5-rbac

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

Set the `CLUSTER_ENDPOINT` GitHub Actions **variable** (the API server URL, e.g.
`https://1.2.3.4:6443`) so the apply can bake it into the generated kubeconfig.
Then, with access to the Tofu state (your normal admin kubeconfig):

```bash
cd 5-rbac
tofu output -raw kubeconfig > readonly.kubeconfig
KUBECONFIG=readonly.kubeconfig kubectl get pods -A
```

That file is a normal, **non-expiring** kubeconfig — keep it like your admin one,
hand it to whoever (or whatever agent) needs to debug. It can read pods/logs/
events cluster-wide and nothing else.

If you'd rather build the kubeconfig by hand, grab just the token:

```bash
tofu output -raw token
```

## Security notes

- The token does **not** expire. To revoke it, delete the `readonly-token`
  secret (and re-apply to mint a fresh one) — that immediately invalidates any
  kubeconfig built from it.
- `pods/log` is granted cluster-wide. The role can't read `secrets`, but
  application logs can still contain sensitive data an app chose to log. That's
  inherent to log access, not specific to this setup.

## Alternative: short-lived token

If you ever want a throwaway credential instead of the permanent one, the same
service account can mint one on demand (expires automatically, nothing stored):

```bash
kubectl create token readonly -n readonly --duration=2h
```
