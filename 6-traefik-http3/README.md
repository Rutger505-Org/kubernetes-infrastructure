# 6-traefik-http3

Enables HTTP/3 (QUIC) on the k3s-bundled Traefik ingress controller.

k3s installs Traefik itself via a packaged `HelmChart` in `kube-system`. This module does
not install Traefik; it adds a `HelmChartConfig` named `traefik` in `kube-system`, whose
`valuesContent` the k3s helm-controller merges into that chart on the next reconcile.

What it turns on:

- `ports.websecure.http3.enabled = true` — Traefik listens on **UDP/443** in addition to
  TCP/443 and sends `Alt-Svc: h3=":443"` so browsers upgrade to HTTP/3 on the next request.
- `service.spec.loadBalancerIP` is pinned to the same MetalLB address used in
  `3-metallb-config`, so the chart's own Service template cannot drop the static IP when
  helm-controller re-renders it.

Notes:

- HTTP/3 needs TLS, so only the `websecure` entrypoint is affected. Plain HTTP stays HTTP/1.1.
- UDP/443 must be open to the cluster: forward it on the router next to TCP/443, otherwise
  clients simply fall back to HTTP/2.
- `advertised_port` should match the public port; change it only if UDP is forwarded from a
  different external port.

## Validation

```bash
kubectl get svc traefik -n kube-system -o jsonpath='{.spec.ports[*].port}{"\n"}{.spec.ports[*].protocol}'
curl -sI https://rutgerpronk.com | grep -i alt-svc
curl -sI --http3 https://rutgerpronk.com | head -1
```

The Service should list a UDP port next to the TCP ones, and the response should carry
`alt-svc: h3=":443"`.

## Why the Service is patched by hand

The chart *does* render `websecure-http3/UDP/443` (`helm template` shows it), but it never
reaches the cluster intact: Kubernetes merges Service ports, and container ports, by **port
number only**, ignoring the protocol. Helm's strategic-merge patch folds the UDP/443 entry
into the TCP/443 one. That is why the Service and the pod never showed a UDP port.

So the module writes the Service's full port list itself (`web`, `websecure`,
`websecure-http3` -> numeric `8443`), with a merge patch that replaces the whole list.
Allocated `nodePort`s are kept, and it is a no-op when the Service already matches.

**It must run after helm-controller's upgrade.** On a fresh cluster the HelmChartConfig and
the patch land in the same apply. The patch once ran a second before the helm upgrade,
which then merged the chart's UDP entry over it and left `websecure/TCP/443` with
`targetPort: websecure-http3`, a port the pod does not have: all HTTPS refused, port 80
fine. The provisioner therefore waits until the traefik Deployment runs with
`--entryPoints.websecure.http3` and is rolled out.

It runs on every apply, so a later helm upgrade (for example a k3s version bump) that
mangles the ports again is repaired by the next deploy or a `workflow_dispatch` run.
