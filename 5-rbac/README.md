# 5-rbac

Read-only RBAC for debugging deployments without exposing secrets.

It creates:

- a `readonly` namespace (anchors the service account, holds no workloads),
- a `readonly` service account,
- a `log-reader` **ClusterRole** granting `get/list/watch` on `pods`,
  `pods/log`, `events`, `deployments` and `replicasets` across **all**
  namespaces (including dynamic `pr-*` preview namespaces),
- a ClusterRoleBinding tying the two together.

The role intentionally **does not** include `secrets` or `configmaps`, so a
holder can inspect why a pod fails to become ready (crash loops, image pull
errors, failing probes) without reading sensitive data. RBAC is default-deny —
only the verbs/resources listed above are allowed.

## Handing out access

Mint a short-lived token (no long-lived credential is stored anywhere):

```bash
kubectl create token readonly -n readonly --duration=2h
```

Combine that token with the cluster API server URL and CA certificate into a
kubeconfig for the person/agent doing the debugging. It expires automatically.
