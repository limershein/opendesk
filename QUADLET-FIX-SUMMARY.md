# Quadlet "Transient Service" Fix - Summary

## The Problem

You encountered this error:
```
Failed to enable unit: Unit /run/systemd/generator/opendesk-minimal.service is transient or generated
```

## Root Cause

Podman quadlets work differently from regular systemd services:

- **Regular systemd service:** Must be explicitly enabled with `systemctl enable`
- **Podman quadlet:** **Automatically enabled** by its presence in `/etc/containers/systemd/`

When `systemctl daemon-reload` runs, systemd's `podman-systemd-generator` creates a **transient service** in `/run/systemd/generator/`. These generated services cannot be enabled/disabled directly.

## What Was Fixed

### 1. Makefile Changes

**Before (WRONG):**
```makefile
sudo systemctl daemon-reload
sudo systemctl enable --now opendesk-minimal.service  # ❌ Fails!
```

**After (CORRECT):**
```makefile
sudo systemctl daemon-reload
sudo systemctl start opendesk-minimal.service  # ✅ Works!
# Note: Quadlets are automatically enabled by their presence in /etc/containers/systemd/
```

### 2. Files Modified

- **Makefile** - Fixed `deploy` and `deploy-prod` targets
- **Makefile** - Fixed `clean` target (removed `systemctl disable`)
- **README.md** - Removed `systemctl enable` from deployment instructions
- **QUADLETS-EXPLAINED.md** - Created comprehensive quadlet documentation

## How Quadlets Work Now

### Deployment

```bash
# 1. Place quadlet file
sudo cp quadlets/opendesk-minimal.kube /etc/containers/systemd/

# 2. Place manifest
sudo cp manifests-minimal/opendesk-minimal.yaml /etc/opendesk/manifests/

# 3. Generate service (systemd reads quadlet and creates transient service)
sudo systemctl daemon-reload

# 4. Start service
sudo systemctl start opendesk-minimal.service

# ✅ Service is now running AND will start on boot automatically!
```

### Why It Works

The quadlet file contains an `[Install]` section:

```ini
[Install]
WantedBy=multi-user.target
```

This tells systemd to start the service at boot, even though the service itself is transient.

### Cleanup

```bash
# 1. Stop service
sudo systemctl stop opendesk-minimal.service

# 2. Remove quadlet file
sudo rm /etc/containers/systemd/opendesk-minimal.kube

# 3. Regenerate services
sudo systemctl daemon-reload

# ✅ Service is gone and won't start on boot!
```

## Corrected Deployment Commands

### Using Make (Recommended)

```bash
cd /home/limershe/src/opendesk

# Deploy (now works correctly)
make deploy

# Check status
make status

# Stop
make stop

# Start
make start

# Clean up
make clean
```

### Manual Deployment

```bash
# Set up storage
sudo bash bootc/setup-storage.sh

# Copy files
sudo mkdir -p /etc/opendesk/manifests /etc/containers/systemd
sudo cp manifests-minimal/opendesk-minimal.yaml /etc/opendesk/manifests/
sudo cp quadlets/opendesk-minimal.kube /etc/containers/systemd/

# Start (NO systemctl enable needed!)
sudo systemctl daemon-reload
sudo systemctl start opendesk-minimal.service
```

## Verification

Check that everything is working:

```bash
# Service should be running
systemctl status opendesk-minimal.service

# Should show: Active: active (running)

# Check pod
podman pod ps

# Should show opendesk-minimal pod

# Check containers
podman ps -a

# Should show 4 containers: postgresql, redis, minio, nextcloud

# Check if enabled for boot
systemctl is-enabled opendesk-minimal.service

# Should show: enabled (from quadlet [Install] section)
```

## Testing in KVM

The KVM testing still works as before:

```bash
# Build and test
make vm-create

# Or automated test
./test-kvm.sh
```

The bootc image has the quadlet file embedded in `/etc/containers/systemd/`, so the service starts automatically when the VM boots.

## Key Takeaways

1. **Never use `systemctl enable` with quadlet services** - they're enabled automatically
2. **Quadlet files in `/etc/containers/systemd/` = service enabled**
3. **Just use `systemctl start`** after `daemon-reload`
4. **To disable:** Remove the `.kube` file and run `daemon-reload`
5. **The `[Install]` section** in the quadlet handles boot-time startup

## Documentation

For more details, see:
- **[QUADLETS-EXPLAINED.md](QUADLETS-EXPLAINED.md)** - Complete quadlet guide
- **[README.md](README.md)** - Updated deployment instructions
- **[Makefile](Makefile)** - Corrected automation

## Quick Reference

| Task | Command | Note |
|------|---------|------|
| Deploy | `make deploy` | No enable needed |
| Start | `systemctl start opendesk-minimal.service` | - |
| Stop | `systemctl stop opendesk-minimal.service` | - |
| Status | `systemctl status opendesk-minimal.service` | - |
| Enable | Place `.kube` in `/etc/containers/systemd/` | Automatic |
| Disable | Remove `.kube` + `daemon-reload` | Automatic |
| Logs | `journalctl -u opendesk-minimal.service` | - |

## Try It Now

```bash
cd /home/limershe/src/opendesk

# Clean deployment with fixed code
make deploy

# Check status
make status

# View logs
make logs
```

Should work without the "transient or generated" error! ✅
