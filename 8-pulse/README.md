# 8-pulse

[Pulse](https://github.com/rcourtman/Pulse) in `pulse`: a Proxmox dashboard that shows real VM memory use. It reads `MemAvailable` through the QEMU guest agent, so guest page cache doesn't count as used like it does in the Proxmox UI.

LAN only on MetalLB `pulse_load_balancer_ip` (`.232`, not port-forwarded) behind homelab Caddy as `pulse.homelab.rutgerpronk.com`. Pulse trusts forwarded headers from `trusted_proxy_cidrs` (the Caddy VM) only.

Fully configured from code, no setup in the UI:

- Login: `admin` with `GRAFANA_ADMIN_PASSWORD` (same as Grafana). Set from the env, which skips Pulse's bootstrap-token setup.
- Proxmox: the `pulse-configure-proxmox-<hash>` Job adds or rewrites the `homelab` connection through Pulse's API after every install, upgrade or config change. It uses 7-monitoring's `prometheus@pve!monitoring` token (`PROXMOX_TOKEN_VALUE`). The guest agent privileges Pulse needs for VM memory are granted in homelab-infrastructure's `proxmox/`.
- VMs already get `qemu-guest-agent` from homelab-infrastructure.

Other settings changed in the UI (alerts, display) live on the PVC (local-path, not backed up). A Proxmox connection edited in the UI is overwritten on the next Job run.

CI config: secrets `GRAFANA_ADMIN_PASSWORD`, `PROXMOX_TOKEN_VALUE` (both already used by 7-monitoring).
