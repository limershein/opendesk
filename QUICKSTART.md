# OpenDesk RHEL Image Mode - Quick Start Guide

Get OpenDesk running on RHEL in 5 minutes.

## Prerequisites

- RHEL 9 or 10
- sudo/root access
- 4 GB RAM minimum
- 20 GB disk space

## Quick Deploy (Evaluation)

### 1. Clone or copy this repository

```bash
cd /home/$(whoami)/src
# Repository should be in opendesk/
```

### 2. Deploy with Make

```bash
cd opendesk
make deploy
```

That's it! The `make deploy` command will:
- Set up storage directories with SELinux contexts
- Copy manifests and quadlets to system locations
- Enable and start the OpenDesk service

### 3. Access Services

- **Nextcloud**: http://localhost:8080
- **MinIO Console**: http://localhost:9001 (credentials: minioadmin/changeme)

Default PostgreSQL credentials:
- User: `opendesk`
- Password: `changeme`
- Database: `opendesk`

## Test in KVM (Recommended)

Test OpenDesk in a virtual machine before deploying directly:

```bash
# Build and test in one command
make vm-create

# Wait for boot (~2 minutes), then access:
make vm-ip        # Get VM IP address
make vm-console   # Connect to console
```

This creates a bootable qcow2 image and tests it in KVM. See [KVM-TESTING.md](KVM-TESTING.md) for details.

## Management Commands

```bash
# View status
make status

# View logs
make logs

# Restart service
make restart

# Stop service
make stop

# Create backup
make backup

# Update images
make update-images
```

## Production Deployment

For production use with external services:

### 1. Edit the production manifest

```bash
vi manifests-minimal/opendesk-minimal-production.yaml
```

Replace all `EXTERNAL_*` placeholders:
- `EXTERNAL_POSTGRES_HOST`
- `EXTERNAL_POSTGRES_USER`
- `EXTERNAL_POSTGRES_PASSWORD`
- `EXTERNAL_REDIS_HOST`
- `EXTERNAL_REDIS_PASSWORD`
- `EXTERNAL_S3_HOST`
- `EXTERNAL_S3_ACCESS_KEY`
- `EXTERNAL_S3_SECRET_KEY`

### 2. Deploy

```bash
make deploy-prod
```

## Manual Deployment (Without Make)

If you prefer manual deployment:

### 1. Set up storage

```bash
sudo bash bootc/setup-storage.sh
```

### 2. Copy files

```bash
sudo mkdir -p /etc/opendesk/manifests /etc/containers/systemd
sudo cp manifests-minimal/opendesk-minimal.yaml /etc/opendesk/manifests/
sudo cp quadlets/opendesk-minimal.kube /etc/containers/systemd/
```

### 3. Start service

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now opendesk-minimal.service
```

## Troubleshooting

### Check service status

```bash
sudo systemctl status opendesk-minimal.service
```

### View logs

```bash
sudo journalctl -u opendesk-minimal.service -f
```

### Check pod status

```bash
podman pod ps
podman ps -a
```

### SELinux issues

```bash
# Check denials
sudo ausearch -m avc -ts recent

# Relabel storage
sudo chcon -R -t container_file_t /var/opendesk/
```

### Reset everything

```bash
make clean-all
```

⚠️ This removes all data!

## Next Steps

1. **Configure TLS/SSL**: Set up a reverse proxy (nginx, HAProxy)
2. **External Database**: Migrate to external PostgreSQL for production
3. **Backups**: Set up automated backups with `make backup`
4. **Monitoring**: Configure monitoring and alerting
5. **Scale Up**: Add more OpenDesk services (Element, Collabora, etc.)

See [README.md](README.md) for detailed documentation.

## Common Commands Reference

| Task | Command |
|------|---------|
| Deploy | `make deploy` |
| Status | `make status` |
| Logs | `make logs` |
| Restart | `make restart` |
| Stop | `make stop` |
| Start | `make start` |
| Backup | `make backup` |
| Update | `make update-images` |
| Test | `make test` |
| Clean | `make clean` |
| Help | `make help` |

## Resource Usage

Typical resource usage for minimal deployment:

- **CPU**: 1-2 cores (idle), 2-4 cores (active)
- **Memory**: 2-3 GB (idle), 4-6 GB (active)
- **Disk**: 5 GB (images) + data storage
- **Network**: Minimal (local deployment)

## Support

- Full documentation: [README.md](README.md)
- OpenDesk docs: https://docs.opendesk.eu/
- RHEL docs: https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9

## License

See [README.md](README.md) for license information.
