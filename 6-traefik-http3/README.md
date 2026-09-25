# 6-traefik-http3

Enables HTTP/3 (QUIC) on the k3s-bundled Traefik ingress controller.

k3s installs Traefik itself through a packaged `HelmChart` in `kube-system`, so this module
does not install Traefik. It owns two things:

1. A `HelmChartConfig` named `traefik`, whose values the k3s helm-controller merges into that
   chart. It enables `ports.websecure.http3`, pins the LoadBalancer address, and adds the
   MetalLB IP-sharing annotation.
2. A `traefik-http3` Service that exposes Traefik's QUIC listener on UDP.

Result: Traefik listens on UDP/443 next to TCP/443 and sends `Alt-Svc: h3=":443"`, so browsers
upgrade to HTTP/3 on the next request.

## Why a second Service instead of one

The Traefik chart is supposed to add the UDP port to its own Service once http3 is enabled.
The chart bundled with this k3s release does not: `helm get manifest traefik` renders a Service
with only `web/TCP` and `websecure/TCP`, even though `helm get values traefik --all` shows the
http3 values arrived and the pod runs with `--entryPoints.websecure.http3`. Rendering the exact
same chart version (`37.1.1+up37.1.0`) with the same values outside the cluster *does* produce
`websecure-http3/UDP/443`.

Patching a helm-owned Service from a provisioner works but is invisible and gets undone by the
next chart upgrade. A separate Service is a plain object this module owns end to end, survives
chart upgrades, and shows up in a `tofu plan`.

Both Services carry the same `metallb.io/allow-shared-ip` key and the same `loadBalancerIP`,
which is what allows MetalLB to serve TCP/443 and UDP/443 from one address.

## Things that will cost you an hour if you forget them

- **`targetPort` must be numeric.** A named `targetPort` only resolves to a containerPort with a
  matching protocol, and the Traefik pod declares `websecure` as TCP only. With the name, the
  Service looks perfectly healthy in `kubectl get svc` while every QUIC handshake times out.
- **The LoadBalancer IP lives in the chart values**, not in a kubectl patch. The MetalLB pool has
  `autoAssign = false`, so a Service that loses its explicit `loadBalancerIP` during a helm
  re-render gets no address at all.
- **HTTP/3 needs TLS**, so only the `websecure` entrypoint is affected. Plain HTTP stays HTTP/1.1.
- **UDP/443 must be open end to end.** If the router only forwards TCP/443, clients quietly fall
  back to HTTP/2 and nothing looks broken.

## Validation

```bash
kubectl get svc -n kube-system traefik traefik-http3
curl -sI https://rutgerpronk.com | grep -i alt-svc
curl -s --http3-only -o /dev/null -w '%{http_version}\n' https://rutgerpronk.com
```

Both Services should report the same `EXTERNAL-IP`, the response should carry
`alt-svc: h3=":443"`, and the last command should print `3`. Use `--http3-only`, not `--http3`:
the latter silently falls back to HTTP/2 and will make a broken setup look fine.
