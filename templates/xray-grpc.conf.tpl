server {
    listen __GRPC_PUBLIC_PORT__ ssl http2;
    server_name __CDN_SUB__ __DOMAIN__;

    ssl_certificate     __LE_LIVE_DIR__/fullchain.pem;
    ssl_certificate_key __LE_LIVE_DIR__/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location /__GRPC_SERVICE_NAME__ {
        grpc_pass            grpc://127.0.0.1:__XRAY_GRPC_BACKEND_PORT__;
        grpc_set_header      X-Real-IP $remote_addr;
        grpc_read_timeout    86400s;
        grpc_send_timeout    86400s;
        client_max_body_size 0;
    }
}
