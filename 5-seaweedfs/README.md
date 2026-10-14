# 5-seaweedfs

Publishes SeaweedFS as the CDN `https://cdn.rutgerpronk.com/<bucket>/<file>` (clips, build artifacts such as the soundboard APK). Objects are anonymously readable; listing and writes are denied.

SeaweedFS itself runs on its own VM, managed by homelab-infrastructure (`ansible/roles/seaweedfs`: buckets, credentials, access). This module only adds a selector-less Service + EndpointSlice to `SEAWEEDFS_IP:8333` and a Traefik IngressRoute with a cert-manager certificate on `CDN_HOSTNAME` (CI vars; DNS must point at Traefik).

Upload with any S3 client and the `SEAWEEDFS_ADMIN_*` keys (also in `/etc/seaweedfs/s3.json` on the VM):

```bash
mcli alias set cdn https://cdn.rutgerpronk.com <access_key> <secret_key>
mcli cp clip.mp4 cdn/clips/clip.mp4
```
