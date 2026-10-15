# 8-pulse

[Pulse](https://github.com/rcourtman/Pulse) in `pulse`: a Proxmox dashboard that shows real VM memory use. It reads `MemAvailable` through the QEMU guest agent, so guest page cache doesn't count as used like it does in the Proxmox UI.

LAN only on MetalLB `pulse_load_balancer_ip` (`.232`, not port-forwarded) behind homelab Caddy as `pulse.homelab.rutgerpronk.com`. Pulse trusts forwarded headers from `trusted_proxy_cidrs` (the Caddy VM) only.

No CI secrets: the Proxmox connection is set up in the UI and stored encrypted on the PVC (local-path, not backed up).

First run:

1. Get the bootstrap token (needs an admin kubeconfig, the read-only one can't exec): `kubectl -n pulse exec deploy/pulse -- /app/pulse bootstrap-token`.
2. Open the UI, create the admin account, add each Proxmox node with the generated read-only setup script.
3. VMs need `qemu-guest-agent` running and **Options → QEMU Guest Agent** on in Proxmox, otherwise Pulse falls back to the Proxmox numbers.
