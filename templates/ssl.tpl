ssl_prefer_server_ciphers  on;
ssl_session_timeout  5m;
ssl_session_cache    shared:SSL:1m;
ssl_ciphers EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+AES128:RSA+AES128:EECDH+AES256:RSA+AES256::!MD5;
ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
ssl_certificate     {REMOTE_ROOT}/certs/{DOMAIN}.cer;
ssl_certificate_key {REMOTE_ROOT}/certs/{DOMAIN}.key;