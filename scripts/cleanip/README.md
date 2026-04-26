# Clean IP scanner + v2rayN subscription helpers

Copy these scripts to the German VPS, e.g.:

```bash
# Optional layout: all three under /root/scripts/
sudo mkdir -p /root/scripts
sudo cp scan-cf-ws-clean-ips.sh generate-final-configs-cleanip.sh update-subscription-nginx.sh /root/scripts/
sudo chmod +x /root/scripts/*.sh
```

Paths in the scripts default to `/root/clean-ips.txt`, `/root/FINAL-CONFIGS-CLEANIP.txt`, and `/var/www/cleanip-subscription/sub` unless overridden by environment variables.

## 1. Scan Cloudflare edge IPs (WebSocket 101)

Runs from the **origin** (or any host that can reach CF edges). It **samples** a few addresses per published IPv4 CIDR (full sweep is not feasible). Outputs IPs where **both** `:80/ws80` and `:443/ws-vless` return HTTP `101`.

```bash
sudo DOMAIN=cdn.dreammaker-groupsoft.ir /root/scripts/cleanip/scan-cf-ws-clean-ips.sh
# result: /root/clean-ips.txt
```

Optional: `EXTRA_IPS="1.2.3.4 5.6.7.8"` to force more candidates. Tune `SAMPLES_PER_CIDR` (default 3).

## 2. Build VLESS one-liners

```bash
sudo UUID='a959df86-fce5-474f-a94c-049e24746713' \
  /root/scripts/cleanip/generate-final-configs-cleanip.sh
# result: /root/FINAL-CONFIGS-CLEANIP.txt
```

Replace `UUID` with your real inbound UUID on the server before distributing links.

## 3. Subscription file for v2rayN (`/sub`)

```bash
sudo /root/scripts/cleanip/update-subscription-nginx.sh
# writes /var/www/cleanip-subscription/sub (base64)
```

Add Nginx `location = /sub` (see `nginx-cleanip-subscription.conf.example`), then reload Nginx.  
Subscription URL: `https://cdn.dreammaker-groupsoft.ir/sub` (same domain as TLS).

No API tokens or passwords are embedded in these scripts.
