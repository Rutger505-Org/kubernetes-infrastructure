# 6-pihole

Network-wide DNS ad-blocker (Pi-hole) for the home LAN, deployed via the
`mojo2600/pihole-kubernetes` Helm chart.

## What it does

- **DNS** on a fixed MetalLB IP (`dns_ip`, port 53 TCP+UDP mixed service).
  Point the router's **primary DNS** at this address so the whole LAN filters
  through Pi-hole.
- **Admin web UI** on a second fixed MetalLB IP (`web_ip`), reachable only on
  the LAN at `http://<web_ip>/admin`. No public hostname / TLS on purpose.
- **DHCP disabled** — the router stays the DHCP server.
- Config + gravity/adlist DB persist on a `local-path` PVC.

## Config (CI)

| Terraform var    | Source                              |
| ---------------- | ----------------------------------- |
| `dns_ip`         | `vars.PIHOLE_DNS_IP` (192.168.178.231) |
| `web_ip`         | `vars.PIHOLE_WEB_IP` (192.168.178.232) |
| `web_password`   | `secrets.PIHOLE_WEB_PASSWORD`       |

Both IPs must sit inside the MetalLB pool defined in `3-metallb-config`
(`192.168.178.230-250`) and not collide with `TRAEFIK_IP` (.230).

## Resilience

If the cluster or Pi-hole is down, LAN DNS stops. Configure a **secondary DNS**
in the router (e.g. `1.1.1.1`) as a fallback.
