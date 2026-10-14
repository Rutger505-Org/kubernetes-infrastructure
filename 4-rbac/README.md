# 4-rbac

Read-only RBAC for debugging deployments without exposing secrets, used through a
**permanent kubeconfig** (like the admin one, but with far fewer rights) that keeps
working when the cluster is reinstalled.

It creates:

- a `log-reader` **ClusterRole** granting `get/list/watch` on `pods`, `pods/log`,
  `events`, `deployments`, `replicasets`, `statefulsets`, `services`,
  `namespaces` and `persistentvolumeclaims` across **all** namespaces (including
  dynamic `pr-*` preview namespaces),
- a ClusterRoleBinding granting it to the user `readonly`.

The role intentionally **does not** include `secrets` or `configmaps`, so a holder
can inspect why a pod fails to become ready (crash loops, image pull errors, failing
probes) without reading sensitive data. RBAC is default-deny: only the verbs/resources
listed above are allowed.

## Why a client certificate

The `readonly` user is the CN of a client certificate signed by the k3s client CA.
homelab-infrastructure restores the same CAs on every rebuild (`K3S_CA_BUNDLE`), and
CI recreates this binding, so the same kubeconfig works on every new cluster.

A service account token cannot do that: it is bound to the service account's UID,
which is new in every cluster, so a reinstall invalidates it.

## Creating the kubeconfig

Once, by hand, not in CI: the client CA key must not leave k3s-1, and this repo is
public. You need SSH access to k3s-1 and your admin kubeconfig (for the server CA).
The private key is generated locally and never leaves your machine.

```bash
server=debian@192.168.178.201
tls=/var/lib/rancher/k3s/server/tls

# Key and certificate request for the user "readonly".
openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
  -subj /CN=readonly -addext extendedKeyUsage=clientAuth \
  -keyout readonly.key -out readonly.csr

# Sign it with the client CA on k3s-1. Valid until the CA itself expires.
scp readonly.csr "$server":
ssh -t "$server" "sudo openssl x509 -req -in readonly.csr -out readonly.crt \
  -CA $tls/client-ca.crt -CAkey $tls/client-ca.key \
  -set_serial 0x$(openssl rand -hex 16) -days 3650 -copy_extensions copyall"
scp "$server":readonly.crt .
ssh "$server" rm readonly.csr readonly.crt

# Server CA from the admin kubeconfig.
kubectl config view --raw --minify \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > server-ca.crt

k="kubectl config --kubeconfig readonly.kubeconfig"
$k set-cluster homelab --server https://192.168.178.201:6443 \
  --certificate-authority server-ca.crt --embed-certs
$k set-credentials readonly --client-certificate readonly.crt \
  --client-key readonly.key --embed-certs
$k set-context readonly --cluster homelab --user readonly
$k use-context readonly
rm readonly.key readonly.csr readonly.crt server-ca.crt

KUBECONFIG=readonly.kubeconfig kubectl auth whoami   # Username: readonly
KUBECONFIG=readonly.kubeconfig kubectl get pods -A
```

Keep the file like your admin kubeconfig and hand it to whoever (or whatever agent)
needs to debug.

## Revoking access

A client certificate cannot be revoked and stays valid until the client CA expires.
To cut off a leaked kubeconfig, change the user name in the ClusterRoleBinding (and the
`CN` above), deploy, and create new kubeconfigs: the old certificate then authenticates
as a user without any rights.
