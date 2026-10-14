# 7-monitoring

Prometheus stack in `monitoring`, alerting to Discord: kube-prometheus-stack, Grafana on `GRAFANA_HOSTNAME` (Traefik, admin password), blackbox probes of `probe_targets` (down, slow, TLS expiring within 14 days), pve-exporter (read-only Proxmox token), and the OpenClaw Gateway's `/api/diagnostics/prometheus` on `openclaw_target` (off when `OPENCLAW_GATEWAY_TOKEN` is empty).

Prometheus can't report its own cluster going down; HetrixTools checks `rutgerpronk.com` externally. Optionally set `watchdog_ping_url` for a dead man's switch.

CI config: secrets `DISCORD_WEBHOOK_URL`, `GRAFANA_ADMIN_PASSWORD`, `PROXMOX_TOKEN_VALUE`, `OPENCLAW_GATEWAY_TOKEN` (optional); var `GRAFANA_HOSTNAME`.

Proxmox token, once on a node (value is shown once → `PROXMOX_TOKEN_VALUE`):

```bash
pveum user add prometheus@pve --comment "Prometheus monitoring (read-only)"
pveum acl modify / --users prometheus@pve --roles PVEAuditor
pveum user token add prometheus@pve monitoring --privsep 0
```

Alerts: only `warning` and `critical` reach Discord, grouped and repeated every 4 h while firing. `ProxmoxGuestStopped` only covers guests with "Start at boot".
