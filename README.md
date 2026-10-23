# Repolupe

### Docker Compose Setup

On the first startup, the admin user `admin` is created with the password `ADMIN_PASSWORD` (default `repolupe123`),
which has to be changed on the first login.

Set `TOKEN_ENCRYPTION_KEY` (required), it encrypts repository access tokens and LLM API keys:

```bash
echo "TOKEN_ENCRYPTION_KEY=$(openssl rand -hex 32)" >> .env
```

Start the service with the latest release from `ghcr.io/repolupe/repolupe`:

```bash
docker compose up -d
```

Update it with `docker compose pull && docker compose up -d`. To pin a version, replace `latest` in
`docker-compose.yml` with a release (e.g. `0.1.0`), or use `main` for the latest build of the main branch.
