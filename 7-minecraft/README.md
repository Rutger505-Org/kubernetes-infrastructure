# 7-minecraft

Minecraft server (Vault Hunters Third Edition) behind [mc-router](https://github.com/itzg/mc-router), with auto-sleep.

## Traffic path

```
player -> mc-vault.rutgerpronk.com:25565
       -> home router port-forward 25565
       -> MetalLB IP (TF_VAR_router_ip)
       -> mc-router
       -> vault-hunters-minecraft Service (ClusterIP)
       -> server pod on node k3s-1
```

mc-router reads the hostname out of the Minecraft handshake and looks up a Service annotated with
`mc-router.itzg.me/externalServerName`. One public port can therefore serve more servers later:
give the next server its own hostname annotation, nothing else changes.

## Auto-sleep

`minecraftRouter.autoScale` does both directions:

- **down**: no connections for `idle_shutdown_after` (default `1h`) -> StatefulSet scaled to 0.
- **up**: a player connects -> scaled back to 1, and the client sees a timeout/"server starting" while
  the world loads. Reconnecting after ~a minute lands in the game.

This only works for `kind: StatefulSet`, which is why `workloadAsStatefulSet` is true.

## Modpack

The server uses `AUTO_CURSEFORGE` with the built-in CurseForge API key (included in the Java 17+ image). No custom API key is needed.

The image tag is pinned to `java17` (`TF_VAR_image_tag`). Vault Hunters Third Edition is Minecraft 1.18.2
on Forge 40.x, which crashes on newer JVMs with `Unsupported class file major version`. Java 17 still
carries the baked-in CurseForge key.

The modpack downloads on first boot; the PVC keeps world and mods afterwards.

## Resetting world data

The data lives on the `local-path` PVC on k3s-1. To wipe it:

```bash
kubectl -n minecraft scale statefulset vault-hunters-minecraft --replicas=0
kubectl -n minecraft delete pvc vault-hunters-minecraft-datadir
kubectl -n minecraft scale statefulset vault-hunters-minecraft --replicas=1
```

The chart recreates the PVC and the server generates a fresh world.

## Variables

Set through the deploy workflow:

| Variable | Source |
| --- | --- |
| `TF_VAR_router_ip` | `vars.MINECRAFT_ROUTER_IP` |
| `TF_VAR_hostname` | `vars.MINECRAFT_HOSTNAME` |
| `TF_VAR_server_type` | `vars.MINECRAFT_SERVER_TYPE` |
| `TF_VAR_idle_shutdown_after` | `vars.MINECRAFT_IDLE_SHUTDOWN_AFTER` |
| `TF_VAR_curseforge_slug` | `vars.MINECRAFT_CURSEFORGE_SLUG` |

The rest have defaults in `variables.tf`.
