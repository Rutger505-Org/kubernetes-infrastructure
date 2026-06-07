# 4-livekit

Self-hosted [LiveKit](https://livekit.io) SFU for 1:1 voice calls (used by the
`relay` app). Because LiveKit is an SFU, **all media flows through the server —
calls are never peer-to-peer**, which satisfies the "all traffic via the server"
requirement.

## What it deploys

- `livekit` namespace
- A `livekit-server` Deployment (single replica)
- Config (incl. API key/secret) as a Secret mounted at `/etc/livekit`
- `livekit-signaling` ClusterIP + traefik Ingress + cert-manager Certificate →
  **`wss://livekit.<BASE_DOMAIN>`** (the signaling URL clients connect to)
- `livekit-media` LoadBalancer (MetalLB) exposing the RTC ports:
  - TCP `7881` and UDP `7882` (single muxed ports)

## Required configuration

Set on the `Rutger505-Org` (or repo) **Actions secrets**:

- `LIVEKIT_API_KEY`
- `LIVEKIT_API_SECRET`

And the existing `BASE_DOMAIN` variable is reused for the host.

## Network requirements (must be done by hand)

LiveKit media is real-time WebRTC and cannot be proxied by traefik:

1. **DNS:** point `livekit.<BASE_DOMAIN>` at the traefik LoadBalancer IP (for
   the `wss` signaling), same as other apps.
2. **RTC reachability:** the `livekit-media` LoadBalancer gets its own MetalLB
   IP. For internet clients, port-forward **TCP 7881** and **UDP 7882** on the
   router to that IP. `rtc.use_external_ip` lets LiveKit advertise the public
   IP it discovers; verify it matches your forwarded address.
3. Verify with two real browsers before relying on it — media networking is
   environment-specific and is not checked by CI.

## Wiring the app

In the `relay` repo, set these `DEPLOYMENT_`-prefixed values so they reach the
app as env vars:

- `DEPLOYMENT_LIVEKIT_URL = wss://livekit.<BASE_DOMAIN>`
- `DEPLOYMENT_LIVEKIT_API_KEY` (same as `LIVEKIT_API_KEY`)
- `DEPLOYMENT_LIVEKIT_API_SECRET` (same as `LIVEKIT_API_SECRET`)

Until these are set, the app runs fine and the call API returns a clear
"voice calling is not configured" error.
