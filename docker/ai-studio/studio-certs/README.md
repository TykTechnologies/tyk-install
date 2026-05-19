# AI Studio TLS Certificates

Place the local TLS certificate files here before starting the stack:

- `tls-certificate.pem`
- `tls-private-key.pem`

For local development, generate a self-signed certificate from `docker/ai-studio`:

```bash
mkdir -p studio-certs

openssl req \
  -x509 \
  -newkey rsa:4096 \
  -sha256 \
  -nodes \
  -days 365 \
  -subj "/CN=ai-studio.localhost" \
  -addext "subjectAltName=DNS:ai-studio.localhost" \
  -keyout studio-certs/tls-private-key.pem \
  -out studio-certs/tls-certificate.pem
```
