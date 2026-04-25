server {
    listen __WSS_PUBLIC_PORT__ ssl;
    server_name __DOMAIN__ __CDN_SUB__;

    ssl_certificate     __LE_LIVE_DIR__/fullchain.pem;
    ssl_certificate_key __LE_LIVE_DIR__/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location / {
        proxy_pass          http://127.0.0.1:__XRAY_WS_BACKEND_PORT__;
        proxy_http_version  1.1;
        proxy_set_header    Upgrade    $http_upgrade;
        proxy_set_header    Connection "upgrade";
        proxy_set_header    Host       $host;
        proxy_read_timeout  86400s;
        proxy_send_timeout  86400s;
    }
}
