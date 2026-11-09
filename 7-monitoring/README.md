# 7-monitoring

Prometheus stack in `monitoring`, alerting to Discord: kube-prometheus-stack, Grafana LAN-only on MetalLB `grafana_load_balancer_ip` (`.231`, not port-forwarded) behind homelab Caddy as `grafana.homelab.rutgerpronk.com` (admin password, self-probed on its Service), blackbox probes of `probe_targets` (down, slow, TLS expiring within 14 days), and pve-exporter (read-only Proxmox token). The probes include the ZeroClaw gateway and someclaw by LAN IP. The Proxmox dashboard (vendored grafana.com 10347) adds real used %, reclaimable cache and PSI memory pressure per node-exporter VM to its summary table, plus per-VM used/cache/free graphs (Proxmox counts guest page cache as used). The Memory pressure dashboard shows real MemAvailable, page cache, PSI, page faults and OOM kills for k3s nodes and node-exporter VMs; Kubernetes panels compare container working set with limits.

Prometheus can't report its own cluster going down; HetrixTools checks `rutgerpronk.com` externally. `watchdog_ping_url` is a HetrixTools Cron Job heartbeat ("Homelab AlertManager", timeout + grace 5 min each): the always-firing Watchdog alert POSTs to it every minute, so it goes DOWN when Prometheus or Alertmanager stops.

CI config: secrets `DISCORD_WEBHOOK_URL`, `GRAFANA_ADMIN_PASSWORD`, `PROXMOX_TOKEN_VALUE`, `WATCHDOG_PING_URL`.

Proxmox token, once on a node (value is shown once → `PROXMOX_TOKEN_VALUE`):

```bash
pveum user add prometheus@pve --comment "Prometheus monitoring (read-only)"
pveum acl modify / --users prometheus@pve --roles PVEAuditor
pveum user token add prometheus@pve monitoring --privsep 0
```

Alerts: only `warning` and `critical` reach Discord, one Discord message per alert (title `<alert>` or `<alert> - Resolved`, pings `discord_user_id`), repeated every 4 h while firing. Grafana alerting is off. Grafana loads dashboards and datasources only at start-up, so a new `grafana_dashboard` ConfigMap needs a Grafana restart. `ProxmoxGuestStopped` only covers guests with "Start at boot". Memory alerts cover Proxmox nodes (>90%) and LXC containers (>95%); node-exporter VM metrics are shown in Grafana, not alerted on yet.
