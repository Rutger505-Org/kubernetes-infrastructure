# 8-home-assistant — Home Assistant and MQTT

Home Assistant with a Mosquitto broker, reachable on the LAN only. Built for
[motorized-blinds](https://github.com/Rutger505/motorized-blinds): the drivers built with the
`mqtt` feature connect to Mosquitto and publish MQTT discovery configs, so each blind shows
up in Home Assistant as a cover (`rolgordijn_<id>`) without any YAML.

## What it creates

- Namespace `home-assistant`.
- **Mosquitto** on `MQTT_IP:1883` (MetalLB). Anonymous access is off; one user from
  `MQTT_USERNAME`/`MQTT_PASSWORD`, hashed into a password file by an init container.
  Retained messages persist on a 100Mi PVC.
- **Home Assistant** on `http://HOME_ASSISTANT_IP:8123` (MetalLB), `/config` on a PVC.

Both are Deployments with `Recreate`, so a pod-template change always replaces the pod
(RWO volumes, and no stuck RollingUpdate behind an unhealthy pod).

## Required CI configuration

| Kind   | Name                | Value             |
| ------ | ------------------- | ----------------- |
| var    | `MQTT_IP`           | `192.168.178.231` |
| var    | `HOME_ASSISTANT_IP` | `192.168.178.232` |
| var    | `MQTT_USERNAME`     | `homeassistant`   |
| secret | `MQTT_PASSWORD`     | MQTT password     |

## First start

1. Open `http://192.168.178.232:8123` and finish onboarding (creates the owner account).
2. Settings → Devices & services → Add integration → **MQTT**: broker `mosquitto.home-assistant.svc`
   (or `192.168.178.231`), port `1883`, the MQTT user and password.
3. Flash each driver with the mqtt feature, from `motorized-blinds/driver`:

   ```sh
   BLIND_ID=1 WIFI_SSID=... WIFI_PASSWORD=... MQTT_BROKER=192.168.178.231 \
     MQTT_USERNAME=homeassistant MQTT_PASSWORD=... \
     cargo run --release --no-default-features --features mqtt
   ```

   The blinds appear under the MQTT integration as `rolgordijn_1` / `rolgordijn_2`.

## Validation

```bash
kubectl get pods,svc,pvc -n home-assistant
timeout 5 bash -c 'cat </dev/null >/dev/tcp/192.168.178.231/1883' && echo MQTT OPEN
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.178.232:8123/
mosquitto_sub -h 192.168.178.231 -u homeassistant -P ... -t 'homeassistant/#' -v   # discovery configs
```
