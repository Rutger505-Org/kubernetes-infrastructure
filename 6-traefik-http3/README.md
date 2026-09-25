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
