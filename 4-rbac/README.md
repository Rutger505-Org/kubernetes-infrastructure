# 4-rbac

Read-only access for debugging (`readonly.kubeconfig`). The `log-reader` ClusterRole grants `get/list/watch` on pods, logs, events, workloads, services, namespaces and PVCs in all namespaces, but no `secrets` or `configmaps`. Bound to the user `readonly`.

`readonly` is the CN of a client certificate signed by the k3s client CA. homelab-infrastructure restores the same CAs on every rebuild (`K3S_CA_BUNDLE`), so the kubeconfig survives a reinstall; a service account token would not.

## Creating the kubeconfig

Once, by hand, never in CI (the client CA key stays on k3s-1, this repo is public). Needs SSH to k3s-1 and the admin kubeconfig.

```bash
server=debian@192.168.1.201
tls=/var/lib/rancher/k3s/server/tls

openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
  -subj /CN=readonly -addext extendedKeyUsage=clientAuth \
  -keyout readonly.key -out readonly.csr

scp readonly.csr "$server":
ssh -t "$server" "sudo openssl x509 -req -in readonly.csr -out readonly.crt \
  -CA $tls/client-ca.crt -CAkey $tls/client-ca.key \
  -set_serial 0x$(openssl rand -hex 16) -days 3650 -copy_extensions copyall"
scp "$server":readonly.crt .
ssh "$server" rm readonly.csr readonly.crt

kubectl config view --raw --minify \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > server-ca.crt

k="kubectl config --kubeconfig readonly.kubeconfig"
$k set-cluster homelab --server https://192.168.1.201:6443 \
  --certificate-authority server-ca.crt --embed-certs
$k set-credentials readonly --client-certificate readonly.crt \
  --client-key readonly.key --embed-certs
$k set-context readonly --cluster homelab --user readonly
$k use-context readonly
rm readonly.key readonly.csr readonly.crt server-ca.crt

KUBECONFIG=readonly.kubeconfig kubectl auth whoami   # Username: readonly
```

## Revoking

Client certificates can't be revoked. Rename the user in the ClusterRoleBinding (and the CN above), deploy, and issue new kubeconfigs; the old certificate then has no rights.
