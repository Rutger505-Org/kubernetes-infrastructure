# 5-seaweedfs — Self-hosted object storage (personal CDN)

Publishes [SeaweedFS](https://github.com/seaweedfs/seaweedfs) (S3-compatible
object storage) as a personal CDN for two use cases:

1. **Sharing clips** with friends via direct, linkable URLs (Discord previews
   the file inline when the URL points straight at it).
2. **Hosting build artifacts** — e.g. the `real-life-soundboard` debug APK — so
   they can be downloaded straight onto a phone for testing.

SeaweedFS itself runs on its own VM, `seaweedfs-server`, created and configured by
[homelab-infrastructure](https://github.com/Rutger505-Org/homelab-infrastructure)
(`ansible/roles/seaweedfs`). The k3s nodes do not have the disk for it. Buckets,
S3 credentials and anonymous read access are configured there.

## What it creates

- A `seaweedfs-s3` Service without a selector, and an EndpointSlice pointing it
  at the VM's S3 port (`SEAWEEDFS_IP`:8333).
- A Traefik `IngressRoute` with a cert-manager certificate for
  `cdn.rutgerpronk.com`. Objects are anonymously readable at
  `https://cdn.rutgerpronk.com/<bucket>/<file>`; anonymous listing and writes
  are denied.

## Required CI configuration

| Kind | Name           | Example               |
| ---- | -------------- | --------------------- |
| var  | `CDN_HOSTNAME` | `cdn.rutgerpronk.com` |
| var  | `SEAWEEDFS_IP` | `192.168.178.214`     |

The hostname must have a DNS A-record pointing at the Traefik LoadBalancer IP
(`TRAEFIK_IP` from `3-metallb-config`).

## Uploading

Any S3 client works, with the admin keys from the `SEAWEEDFS_ADMIN_ACCESS_KEY`
and `SEAWEEDFS_ADMIN_SECRET_KEY` secrets (also in `/etc/seaweedfs/s3.json` on
the VM):

```bash
mcli alias set cdn https://cdn.rutgerpronk.com <access_key> <secret_key>
mcli cp clip.mp4 cdn/clips/clip.mp4
# -> https://cdn.rutgerpronk.com/clips/clip.mp4
```
