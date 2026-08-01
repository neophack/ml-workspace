#!/bin/sh
# Provision an SSL certificate for websockify (noVNC over wss://).
#
# If a certificate is supplied via docker secrets (/run/secrets/cert.*), it is
# copied into $SSL_RESOURCES_PATH. Otherwise a self-signed certificate is
# generated. The private key is locked down to 0600.
#
# SECURITY: the certificate is NOT installed into the system CA store or the
# Python certifi bundle. Injecting a self-signed / deployment-specific CA into
# the global trust store would let anyone holding the matching private key MITM
# all TLS traffic originating from the container. The certificate here is only
# used to serve noVNC; clients must trust it explicitly (or accept the warning).

SSLNAME=cert
SSL_DIR="${SSL_RESOURCES_PATH:-/resources/ssl}"
mkdir -p "$SSL_DIR"

# Prefer a caller-provided certificate (docker secrets).
[ -f "/run/secrets/$SSLNAME.crt" ] && cp "/run/secrets/$SSLNAME.crt" "$SSL_DIR/$SSLNAME.crt"
[ -f "/run/secrets/$SSLNAME.key" ] && cp "/run/secrets/$SSLNAME.key" "$SSL_DIR/$SSLNAME.key"
[ -f "/run/secrets/$SSLNAME.pem" ] && cp "/run/secrets/$SSLNAME.pem" "$SSL_DIR/$SSLNAME.pem"

if [ ! -f "$SSL_DIR/$SSLNAME.crt" ]; then
    echo "Generating self-signed certificate for SSL/HTTPS (noVNC only)."
    SSLDAYS=365
    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout "$SSL_DIR/$SSLNAME.key" -out "$SSL_DIR/$SSLNAME.crt" \
        -days "$SSLDAYS" -subj '/C=CN/ST=Local/L=Local/CN=localhost' > /dev/null 2>&1
else
    echo "Certificate for SSL/HTTPS was found in $SSL_DIR"
fi

# Lock down the private key: readable by root only. Never world/group-readable.
if [ -f "$SSL_DIR/$SSLNAME.key" ]; then
    chmod 0600 "$SSL_DIR/$SSLNAME.key"
fi
if [ -f "$SSL_DIR/$SSLNAME.crt" ]; then
    chmod 0644 "$SSL_DIR/$SSLNAME.crt"
fi
