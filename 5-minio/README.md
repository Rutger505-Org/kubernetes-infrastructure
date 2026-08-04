# 5-minio — Self-hosted object storage (personal CDN)

Deploys [MinIO](https://min.io/) (S3-compatible object storage) as a personal
CDN for two use cases:

1. **Sharing clips** with friends via direct, linkable URLs (Discord previews
   the file inline when the URL points straight at it).
2. **Hosting build artifacts** — e.g. the `real-life-soundboard` debug APK — so
   they can be downloaded straight onto a phone for testing (no cable needed).

## What it creates

- A single-node MinIO `helm_release` in the `minio` namespace.
- A persistent volume on the node's local disk (default `30Gi`, `local-path`
  StorageClass) — see [storage](#storage).
- A public, anonymous read-only bucket (`cdn` by default) so uploads are
  directly downloadable.
- Two Traefik `IngressRoute`s with cert-manager certificates:
  - `cdn.rutgerpronk.com` → S3 API (public file URLs).
  - `minio.rutgerpronk.com` → admin console.

## Required CI configuration

Set these on the repo/org before tagging a release:

| Kind   | Name                     | Example                    |
| ------ | ------------------------ | -------------------------- |
| secret | `MINIO_ROOT_USER`        | `admin`                    |
| secret | `MINIO_ROOT_PASSWORD`    | (strong password)          |
| var    | `MINIO_CDN_HOSTNAME`     | `cdn.rutgerpronk.com`      |
| var    | `MINIO_CONSOLE_HOSTNAME` | `minio.rutgerpronk.com`    |

Both hostnames must have DNS A-records pointing at the Traefik LoadBalancer IP
(`TRAEFIK_IP` from `3-metallb-config`).

## Storage

MinIO's data lives on a PVC backed by the K3s node's **local disk**. To use the
spare 250GB drives, mount one into the K3s VM and make sure the node's
`local-path` provisioner writes there. See the storage section in
`homelab-infrastructure` for the Proxmox disk passthrough + mount steps.

To grow later: bump `storage_size` (and the underlying disk/mount).

## Uploading

Any S3 tool works (`aws s3`, `rclone`, `mc`). A small purpose-built uploader for
`~/Videos/Clips` lives in the `clipcdn` project.

```bash
# Example with the MinIO client (mc):
mc alias set homecdn https://cdn.rutgerpronk.com admin '<password>'
mc cp clip.mp4 homecdn/cdn/clips/clip.mp4
# -> https://cdn.rutgerpronk.com/cdn/clips/clip.mp4
```
