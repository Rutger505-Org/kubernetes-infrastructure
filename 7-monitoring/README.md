# 7-monitoring — Monitoring and alerting

Watches the k3s cluster, the Proxmox hosts and the public sites, and posts
alerts to Discord.

## What it creates

- **kube-prometheus-stack** in the `monitoring` namespace: Prometheus,
  Alertmanager, kube-state-metrics and node-exporter. Covers crashlooping pods,
  unavailable replicas, node pressure and filling disks out of the box.
- **Grafana** on MetalLB IP `192.168.178.234`, reachable on the LAN and over
  Tailscale only. No IngressRoute, no public certificate. Ships Proxmox,
  blackbox and Kubernetes dashboards.
- **blackbox-exporter**: HTTP probes of `probe_targets` (site down, slow, TLS
  certificate expiring within 14 days).
- **pve-exporter**: Proxmox host/guest/storage metrics over the API with a
  read-only token. Nothing here can change the hypervisor.

Prometheus runs inside the cluster it watches, so it cannot report the cluster
itself going down. That is left to an external check (HetrixTools on
`rutgerpronk.com`). Optionally set `watchdog_ping_url` to route the
always-firing Watchdog alert to a dead man's switch such as healthchecks.io.

## Required CI configuration

| Kind   | Name                     | Value                                 |
| ------ | ------------------------ | ------------------------------------- |
| secret | `DISCORD_WEBHOOK_URL`    | Discord channel webhook               |
| secret | `GRAFANA_ADMIN_PASSWORD` | Grafana `admin` password              |
| secret | `PROXMOX_TOKEN_VALUE`    | Secret of `prometheus@pve!monitoring` |

## Proxmox API token

Run once on a Proxmox host (once per host if they are not clustered):

```bash
pveum user add prometheus@pve --comment "Prometheus monitoring (read-only)"
pveum acl modify / --users prometheus@pve --roles PVEAuditor
pveum user token add prometheus@pve monitoring --privsep 0
```

The token value is shown only once; store it as `PROXMOX_TOKEN_VALUE`.

## Alerts

Only `warning` and `critical` alerts reach Discord; `info` alerts are dropped.
Related alerts are grouped into one message and repeated every 4 hours while
still firing. `ProxmoxGuestStopped` only covers guests with "Start at boot"
enabled, so templates and guests that are kept off on purpose stay quiet.
