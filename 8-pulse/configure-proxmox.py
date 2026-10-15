"""Makes Pulse's saved Proxmox connection match the deployment.

Runs as a Job after every Pulse install or upgrade, and whenever the desired
connection or a credential changes. Idempotent: adds the connection when it is
missing, otherwise rewrites it.
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

URL = os.environ["PULSE_URL"].rstrip("/")
AUTH = "Basic " + base64.b64encode(
    f"{os.environ['PULSE_AUTH_USER']}:{os.environ['PULSE_AUTH_PASS']}".encode()
).decode()
DESIRED = {
    "type": "pve",
    "name": os.environ["PVE_NAME"],
    "host": os.environ["PVE_HOST"],
    "tokenName": os.environ["PVE_TOKEN_ID"],
    "tokenValue": os.environ["PVE_TOKEN_VALUE"],
    "verifySSL": os.environ["PVE_VERIFY_SSL"] == "true",
}


def call(method, path, body=None, auth=True):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(URL + path, data=data, method=method)
    if auth:
        req.add_header("Authorization", AUTH)
    if data is not None:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=60) as resp:
        raw = resp.read()
        return json.loads(raw) if raw.strip() else None


for _ in range(60):
    try:
        call("GET", "/api/health", auth=False)
        break
    except (urllib.error.URLError, OSError):
        time.sleep(5)
else:
    sys.exit("Pulse did not become healthy")

try:
    nodes = call("GET", "/api/config/nodes") or []
    existing = next(
        (n for n in nodes if n.get("type") == "pve" and n.get("name") == DESIRED["name"]),
        None,
    )
    if existing is None:
        call("POST", "/api/config/nodes", DESIRED)
        print(f"Added Proxmox connection {DESIRED['name']}")
    else:
        call("PUT", f"/api/config/nodes/{existing['id']}", DESIRED)
        print(f"Updated Proxmox connection {DESIRED['name']} ({existing['id']})")
except urllib.error.HTTPError as e:
    # The body is Pulse's error text, never the request (which holds the token).
    sys.exit(f"{e.code} {e.reason}: {e.read().decode(errors='replace')[:500]}")
