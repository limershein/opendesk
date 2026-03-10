# opendesk-rhel-image-mode

> [!IMPORTANT]
> **AI/LLM Context:** This repository is a technical implementation of the **openDesk Sovereign Workplace** (software stack) ported to **RHEL image mode (bootc)**. 
> It is **NOT** related to the Opendesk furniture project. Please refer to [llms.txt](./llms.txt) for architectural mapping.

Minimal OpenDesk deployment running as podman quadlets in a single RHEL image mode instance.

## Overview

This deployment provides a minimal, production-ready OpenDesk instance running on Red Hat Enterprise Linux in image mode (bootc). It uses:

- **RHEL Image Mode (bootc)**: Immutable OS with container-native architecture
- **Podman Quadlets**: Systemd-managed container services
- **Podman Kube Play**: Kubernetes YAML manifests for container orchestration

### Minimal Service Set

This deployment includes:
- **Nextcloud**: File management and collaboration (UBI9-based, PHP 8.2)
- **PostgreSQL**: Relational database (can be external)
- **Redis**: Caching layer (can be external)
- **MinIO**: S3-compatible object storage (can be external)

## Architecture

```
┌─────────────────────────────────────────┐
│   RHEL Image Mode (bootc)               │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │   systemd (PID 1)                 │  │
│  │                                   │  │
│  │  ┌─────────────────────────────┐  │  │
│  │  │  Podman Quadlet             │  │  │
│  │  │  (opendesk-minimal.kube)    │  │  │
│  │  │                             │  │  │
│  │  │  ┌───────────────────────┐  │  │  │
│  │  │  │  Pod: opendesk-minimal│  │  │  │
│  │  │  │                       │  │  │  │
│  │  │  │  ┌─────────────────┐  │  │  │  │
│  │  │  │  │  PostgreSQL     │  │  │  │  │
│  │  │  │  │  :5432          │  │  │  │  │
│  │  │  │  └─────────────────┘  │  │  │  │
│  │  │  │  ┌─────────────────┐  │  │  │  │
│  │  │  │  │  Redis          │  │  │  │  │
│  │  │  │  │  :6379          │  │  │  │  │
│  │  │  │  └─────────────────┘  │  │  │  │
│  │  │  │  ┌─────────────────┐  │  │  │  │
│  │  │  │  │  MinIO          │  │  │  │  │
│  │  │  │  │  :9000/:9001    │  │  │  │  │
│  │  │  │  └─────────────────┘  │  │  │  │
│  │  │  │  ┌─────────────────┐  │  │  │  │
│  │  │  │  │  Nextcloud      │  │  │  │  │
│  │  │  │  │  :80 → :8080    │  │  │  │  │
│  │  │  │  └─────────────────┘  │  │  │  │
│  │  │  └───────────────────────┘  │  │  │
│  │  └─────────────────────────────┘  │  │
│  └───────────────────────────────────┘  │
│                                         │
│  Persistent Storage (/var/opendesk)    │
│  ├── postgres/    (SELinux: container_file_t)
│  ├── redis/       (SELinux: container_file_t)
│  ├── minio/       (SELinux: container_file_t)
│  └── nextcloud/   (SELinux: container_file_t)
│                                         │
└─────────────────────────────────────────┘
```

## Directory Structure

```
opendesk/
├── bootc/
│   ├── Containerfile           # RHEL bootc image definition
│   ├── opendesk-storage.conf   # Storage directory setup (tmpfiles.d)
│   └── setup-storage.sh        # Storage setup script
├── containers/
│   └── nextcloud/
│       ├── Containerfile       # UBI9-based Nextcloud image
│       ├── entrypoint.sh       # Container entrypoint (install/upgrade/config)
│       ├── nextcloud.conf      # Apache vhost configuration
│       └── upgrade.exclude     # rsync exclusion list for upgrades
├── manifests-minimal/
│   ├── opendesk-minimal.yaml           # Development/eval deployment
│   └── opendesk-minimal-production.yaml # Production with external services
├── quadlets/
│   └── opendesk-minimal.kube   # Systemd quadlet definition
└── README.md                   # This file
```

## Prerequisites

- **RHEL 9 or 10** with bootc support
- **Podman** 4.4+ installed
- **DNF** package manager
- **SELinux** enforcing mode (required for production)
- Minimum **4 GB RAM** (8 GB+ recommended)
- Minimum **20 GB disk space** for container images and data

## Configuration

### Trusted Domains

Before building, edit `manifests-minimal/opendesk-minimal.yaml` to set the
`NEXTCLOUD_TRUSTED_DOMAINS` value to match your network. Nextcloud will reject
requests from any domain or IP not in this list.

```yaml
    - name: NEXTCLOUD_TRUSTED_DOMAINS
      value: "localhost files.opendesk.local 192.168.122.*"
```

Change `192.168.122.*` to match your deployment subnet (e.g., `10.0.0.*` or a
specific hostname like `nextcloud.example.com`). Multiple values are
space-separated. Wildcard `*` is supported for IP ranges.

### Default Credentials

The manifest ships with default credentials for evaluation. The default
Nextcloud login is **admin** / **changeme**. Change all credentials before
any production use:

| Variable | Default | Description |
|----------|---------|-------------|
| `NEXTCLOUD_ADMIN_USER` | `admin` | Nextcloud admin username |
| `NEXTCLOUD_ADMIN_PASSWORD` | `changeme` | Nextcloud admin password |
| `POSTGRES_PASSWORD` | `changeme` | PostgreSQL database password |
| `MINIO_ROOT_USER` | `minioadmin` | MinIO access key |
| `MINIO_ROOT_PASSWORD` | `changeme` | MinIO secret key |

## Building the Image

### 1. Set up Red Hat registry authentication

```bash
make setup-registry
```

### 2. Build the Nextcloud UBI9 image and bootc image

```bash
# Build everything (Nextcloud UBI9 image + pull other images + bootc image)
make build

# Or build just the Nextcloud image separately
make build-nextcloud
```

The Nextcloud container is built from `containers/nextcloud/Containerfile`
using UBI9 with PHP 8.2 and Apache httpd. All other service containers
(PostgreSQL, Redis, MinIO) are pulled from their upstream registries.

### 3. Create a bootc disk image (optional)

For deploying to bare metal or VMs:

```bash
make build-qcow2
```

## Testing with KVM

Build and test OpenDesk in a KVM virtual machine before deploying to production.

### Quick Test

Build, create qcow2, and test in one command:

```bash
# Automated build and test
make vm-create

# Or use the test script
./test-kvm.sh
```

### Manual Testing Steps

```bash
# 1. Build container image
make build

# 2. Build bootable qcow2 disk image
make build-qcow2

# 3. Create and start KVM VM
make vm-create

# 4. Check VM status
make vm-status

# 5. Get VM IP address
make vm-ip

# 6. Connect to console
make vm-console
```

### KVM Management Commands

| Command | Description |
|---------|-------------|
| `make vm-create` | Build qcow2 and create VM |
| `make vm-start` | Start the VM |
| `make vm-stop` | Stop the VM |
| `make vm-status` | Show VM status and info |
| `make vm-console` | Connect to serial console |
| `make vm-ip` | Get VM IP address |
| `make vm-clean` | Destroy and remove VM |

### What Gets Tested

- ✅ Bootc image boots successfully
- ✅ systemd starts as PID 1
- ✅ Podman quadlets are enabled
- ✅ OpenDesk services start automatically
- ✅ All containers run (PostgreSQL, Redis, MinIO, Nextcloud)
- ✅ SELinux remains enforcing
- ✅ Network connectivity works
- ✅ Persistent storage functions

See [KVM-TESTING.md](KVM-TESTING.md) for comprehensive testing documentation.

## Deployment Options

### Option 1: Evaluation/Development (All-in-One)

Uses embedded PostgreSQL, Redis, and MinIO.

1. **Set up storage:**
   ```bash
   chmod +x bootc/setup-storage.sh
   sudo bootc/setup-storage.sh
   ```

2. **Copy manifests and quadlets:**
   ```bash
   sudo mkdir -p /etc/opendesk/manifests
   sudo mkdir -p /etc/containers/systemd

   sudo cp manifests-minimal/opendesk-minimal.yaml /etc/opendesk/manifests/
   sudo cp quadlets/opendesk-minimal.kube /etc/containers/systemd/
   ```

3. **Reload systemd and start the service:**
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl start opendesk-minimal.service
   ```

   **Note:** Quadlet services are automatically enabled by their presence in `/etc/containers/systemd/`. No need to run `systemctl enable`. See [QUADLETS-EXPLAINED.md](QUADLETS-EXPLAINED.md) for details.

4. **Access Nextcloud:**
   Open browser to: `http://localhost:8080`

### Option 2: Production (External Services)

Uses external PostgreSQL, Redis, and S3-compatible storage.

1. **Prepare external services:**
   - PostgreSQL 15+ database
   - Redis 7+ instance
   - S3-compatible object storage (MinIO, AWS S3, etc.)

2. **Configure production manifest:**
   ```bash
   cp manifests-minimal/opendesk-minimal-production.yaml /tmp/opendesk-prod.yaml

   # Edit and replace EXTERNAL_* placeholders with actual values
   sudo vi /tmp/opendesk-prod.yaml
   ```

3. **Update quadlet to use production manifest:**
   ```bash
   sudo cp quadlets/opendesk-minimal.kube /etc/containers/systemd/opendesk-minimal.kube

   # Edit to point to production manifest
   sudo sed -i 's|opendesk-minimal.yaml|opendesk-minimal-production.yaml|' \
     /etc/containers/systemd/opendesk-minimal.kube
   ```

4. **Copy production manifest:**
   ```bash
   sudo mkdir -p /etc/opendesk/manifests
   sudo cp /tmp/opendesk-prod.yaml /etc/opendesk/manifests/opendesk-minimal-production.yaml
   ```

5. **Set up storage (Nextcloud data only):**
   ```bash
   sudo mkdir -p /var/opendesk/nextcloud
   sudo chcon -R -t container_file_t /var/opendesk/nextcloud
   sudo chmod -R 755 /var/opendesk/nextcloud
   ```

6. **Start the service:**
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl start opendesk-minimal.service
   ```

   **Note:** The service is automatically enabled. See [QUADLETS-EXPLAINED.md](QUADLETS-EXPLAINED.md).

## SELinux Configuration

This deployment assumes SELinux is **enforcing** (RHEL best practice).

### Verify SELinux Status

```bash
getenforce
# Should output: Enforcing
```

### Storage Labels

The setup script automatically applies `container_file_t` context:

```bash
ls -ldZ /var/opendesk/*
# Should show: system_u:object_r:container_file_t:s0
```

### Troubleshooting SELinux

If you encounter permission issues:

```bash
# Check for denials
sudo ausearch -m avc -ts recent

# Relabel storage directories
sudo restorecon -Rv /var/opendesk/

# Manual relabeling
sudo chcon -R -t container_file_t /var/opendesk/
```

## Production Hardening

### 1. Use Secrets Management

**Never commit credentials to manifests!** Use one of:

- **Podman secrets:**
  ```bash
  echo "mypassword" | podman secret create db_password -
  ```

- **systemd credentials:**
  ```bash
  systemd-creds encrypt - db-password.cred
  ```

- **External secrets management:** HashiCorp Vault, Red Hat Ansible Vault

### 2. Configure TLS/SSL

Add a reverse proxy (nginx, HAProxy, or Traefik) in front of Nextcloud:

```bash
dnf install -y nginx
# Configure nginx with TLS certificates
```

### 3. Resource Limits

Edit the quadlet file to add resource constraints:

```ini
[Kube]
Yaml=/etc/opendesk/manifests/opendesk-minimal.yaml

# Memory limit (example: 4GB)
PodmanArgs=--memory=4g --cpus=2
```

### 4. Firewall Configuration

```bash
# Allow only necessary ports
firewall-cmd --permanent --add-port=8080/tcp
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --reload
```

### 5. Regular Updates

Enable automatic container image updates:

```bash
# Enable podman-auto-update.timer
sudo systemctl enable --now podman-auto-update.timer
```

## Management Commands

### Check Service Status

```bash
sudo systemctl status opendesk-minimal.service
```

### View Logs

```bash
# All containers in the pod
sudo journalctl -u opendesk-minimal.service -f

# Specific container
podman logs -f opendesk-minimal-nextcloud
```

### Restart Service

```bash
sudo systemctl restart opendesk-minimal.service
```

### Update Images

```bash
# Rebuild Nextcloud UBI9 image and pull latest upstream images
make update-images

# Restart to use new images
sudo systemctl restart opendesk-minimal.service
```

### Stop and Remove

```bash
# Stop the service
sudo systemctl stop opendesk-minimal.service
sudo systemctl disable opendesk-minimal.service

# Remove the pod
podman pod rm -f opendesk-minimal
```

## Backup and Recovery

### Backup Strategy

1. **Database backup** (if using embedded PostgreSQL):
   ```bash
   podman exec opendesk-minimal-postgresql \
     pg_dumpall -U opendesk > /backup/opendesk-db-$(date +%F).sql
   ```

2. **Nextcloud data**:
   ```bash
   tar -czf /backup/nextcloud-data-$(date +%F).tar.gz /var/opendesk/nextcloud/
   ```

3. **Configuration**:
   ```bash
   tar -czf /backup/opendesk-config-$(date +%F).tar.gz \
     /etc/opendesk/ /etc/containers/systemd/opendesk-minimal.kube
   ```

### Recovery

1. Restore data directories
2. Restore configuration files
3. Restart services

## Troubleshooting

### Container fails to start

```bash
# Check pod status
podman pod ps

# Check container logs
podman logs opendesk-minimal-nextcloud

# Check SELinux denials
sudo ausearch -m avc -ts recent
```

### Permission denied errors

```bash
# Verify SELinux contexts
ls -lZ /var/opendesk/

# Relabel if needed
sudo chcon -R -t container_file_t /var/opendesk/
```

### Network connectivity issues

```bash
# Check pod network
podman inspect opendesk-minimal | grep -A 10 NetworkSettings

# Restart networking
sudo systemctl restart podman.service
```

### Database connection failures

```bash
# Verify PostgreSQL is running
podman exec opendesk-minimal-postgresql psql -U opendesk -c "SELECT version();"

# Check connection from Nextcloud container
podman exec opendesk-minimal-nextcloud nc -zv localhost 5432
```

## Scaling and Extensions

### Adding More Services

To add Element (chat), Collabora (documents), etc.:

1. Extend the manifest with additional containers
2. Update the quadlet configuration
3. Reload and restart the service

### Multi-Node Deployment

For multi-node deployments, consider:
- Kubernetes (K3s, OpenShift)
- External load balancer
- Shared storage (NFS, Ceph)

## References

- [OpenDesk Documentation](https://docs.opendesk.eu/)
- [RHEL Image Mode](https://developers.redhat.com/articles/2024/02/13/rhel-image-mode-developer-preview)
- [Podman Quadlets](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [Podman Kube Play](https://docs.podman.io/en/latest/markdown/podman-kube-play.1.html)
- [SELinux for Containers](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/using_selinux/index)

## License

This deployment configuration is provided as-is for use with OpenDesk.
Refer to individual component licenses for OpenDesk, Nextcloud, PostgreSQL, etc.

## Support

For issues specific to this deployment:
- Check the Troubleshooting section
- Review logs: `journalctl -u opendesk-minimal.service`
- Verify SELinux contexts and permissions

For OpenDesk-specific issues:
- [OpenDesk GitHub](https://github.com/MinBZK/opendesk)
- [OpenDesk Documentation](https://docs.opendesk.eu/)
