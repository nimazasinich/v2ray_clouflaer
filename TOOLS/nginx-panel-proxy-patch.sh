# --- PASTE THIS ENTIRE BLOCK INTO VNC CONSOLE ---
# Adds /panel-proxy/ location to Nginx (port 2053) WITHOUT rewriting full config

# 1. Check where the port 2053 server block lives
grep -n "listen 2053" /etc/nginx/nginx.conf /etc/nginx/conf.d/*.conf /etc/nginx/sites-enabled/* 2>/dev/null

# 2. Backup
cp /etc/nginx/nginx.conf /root/nginx.conf.bak.$(date +%Y%m%d%H%M%S)

# 3. Insert /panel-proxy/ before the "location /" catch-all (or before closing brace)
#    Uses sed to insert before the first "location / {" line
sed -i '/location \/ {/{
i\
        location /panel-proxy/ {\
            proxy_pass              https://127.0.0.1:2822/jZMb26oGjigaPhSgj9/;\
            proxy_ssl_verify        off;\
            proxy_set_header        Host              82.115.26.105:2822;\
            proxy_set_header        X-Real-IP         127.0.0.1;\
            proxy_set_header        X-Forwarded-For   127.0.0.1;\
            proxy_http_version      1.1;\
            proxy_set_header        Upgrade           $http_upgrade;\
            proxy_set_header        Connection        "upgrade";\
            proxy_buffering         off;\
            proxy_request_buffering off;\
        }
}' /etc/nginx/nginx.conf

# 4. Test and reload
nginx -t && systemctl reload nginx && echo "SUCCESS - panel-proxy active" || echo "FAILED - check nginx -t output"

# 5. Verify
grep -A5 "panel-proxy" /etc/nginx/nginx.conf | head -10
