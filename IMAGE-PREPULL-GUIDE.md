# Pre-Pulling Container Images in bootc

## Overview

This bootc image uses a **pre-pull strategy** where container images are:
1. Pulled during the image build (using your Red Hat credentials)
2. Saved as a tar archive in the image
3. Loaded into podman on first boot
4. No runtime authentication needed!

## How It Works

### Build Time

```
Host-side preparation (make pull-images):
1. Use registry-auth.json for authentication
2. podman pull postgresql, redis, minio, nextcloud on host
3. podman save → bootc/opendesk-images.tar (~1.5 GB)

Containerfile build process:
1. COPY bootc/opendesk-images.tar → /usr/share/opendesk/images/
2. No nested podman needed during build
```

### First Boot

```
VM boot sequence:
1. systemd starts
2. opendesk-load-images.service runs (oneshot)
   → podman load -i /usr/share/opendesk/images/opendesk-images.tar
   → Creates /var/lib/opendesk/.images-loaded marker
3. opendesk-minimal.service starts
   → Images already available locally
   → No registry pull needed!
```

### Subsequent Boots

The `.images-loaded` marker prevents re-loading images (they're already in podman storage).

## Setup Instructions

### Step 1: Configure Registry Authentication

```bash
# Option A: Automated
make setup-registry

# Option B: Manual
sudo podman login registry.redhat.io
sudo cp /root/.config/containers/auth.json bootc/registry-auth.json
```

### Step 2: Pull Container Images

```bash
# Pull images on the host and create tar archive
make pull-images

# This will:
# - Pull PostgreSQL 15 (~200 MB)
# - Pull Redis 7 (~100 MB)
# - Pull MinIO (~200 MB)
# - Pull Nextcloud (~1 GB)
# - Save all to bootc/opendesk-images.tar (~1.5 GB)

# Pull time: 5-10 minutes (depending on network)
```

### Step 3: Build the Bootc Image

```bash
# Build the bootc image (includes pre-pulled images)
make build

# This will:
# - Verify opendesk-images.tar exists
# - Build the bootc container image
# - Copy the tar into the image

# Build time: 2-3 minutes
```

### Step 4: Create bootable qcow2

```bash
make build-qcow2
```

### Step 5: Test

```bash
make vm-create
make vm-console
# Login: admin / opendesk

# Inside VM - images should already be loaded
sudo podman images

# Service should start immediately (no pulling)
sudo systemctl status opendesk-minimal.service
```

## Image Size

**Trade-off:** Larger image size for faster boot and no auth requirement

- Base bootc image: ~1.5 GB
- Pre-pulled images: ~1.5 GB
- **Total: ~3 GB**

Subsequent VMs created from the same qcow2 don't need to pull images.

## Benefits

✅ **No runtime authentication needed**
✅ **Faster first boot** (no image pulling)
✅ **Works offline** (after initial build)
✅ **Predictable** (exact image versions baked in)
✅ **Secure** (no credentials in running VM)

## Limitations

❌ **Larger image size** (~3 GB vs ~1.5 GB)
❌ **Image updates** require rebuild (can't auto-update)
❌ **Build-time auth required** (need RHCP credentials)

## Updating Images

To update to newer image versions:

```bash
# Rebuild with latest images
make setup-registry  # Refresh credentials if needed
make pull-images     # Re-pull latest :latest tags
make build           # Rebuild bootc image with new images
make build-qcow2
make vm-create
```

## Alternative: Runtime Pulling

If you prefer smaller images with runtime pulling:

1. **Remove pre-pull from Containerfile:**
   - Comment out the `podman pull` and `podman save` lines
   - Keep `COPY bootc/registry-auth.json /etc/containers/auth.json`

2. **Rebuild:**
   ```bash
   make build
   make build-qcow2
   ```

3. **Result:**
   - Smaller image (~1.5 GB)
   - Images pulled on first boot
   - Requires embedded credentials

## Files

- `bootc/Containerfile` - Image build (copies pre-pulled images)
- `bootc/opendesk-images.tar` - Pre-pulled container images (gitignored, created by make pull-images)
- `bootc/opendesk-load-images.service` - Systemd service to load images on boot
- `bootc/registry-auth.json` - Red Hat registry credentials (gitignored)
- `setup-registry-auth.sh` - Helper script to set up auth
- `/usr/share/opendesk/images/opendesk-images.tar` - Pre-pulled images (in bootc image)

## Security Note

✅ **The auth.json file is NOT embedded in the bootc image**:
- Only used on the build host to pull images
- Images are pre-pulled and saved to a tar file
- The tar file (not credentials) is copied into the bootc image
- No credentials in the final VM

For added security with service accounts:
1. Create at https://access.redhat.com/terms-based-registry/
2. Download auth.json
3. Use it as `bootc/registry-auth.json`

## Troubleshooting

### Build fails: "auth.json not found"

```bash
# Run setup
make setup-registry

# Or manually create it
sudo podman login registry.redhat.io
sudo cp /root/.config/containers/auth.json bootc/registry-auth.json
```

### Build fails: "unauthorized"

Your credentials expired or are invalid:

```bash
# Re-login
sudo podman logout registry.redhat.io
sudo podman login registry.redhat.io
make setup-registry
```

### Images not loaded on boot

Check the service:

```bash
# Inside VM
sudo systemctl status opendesk-load-images.service

# Manual load
sudo podman load -i /usr/share/opendesk/images/opendesk-images.tar
```

### Want to update one image

You'd need to rebuild the entire bootc image. For frequent updates, consider runtime pulling instead.

## Comparison

| Aspect | Pre-pull | Runtime Pull |
|--------|----------|--------------|
| Image size | ~3 GB | ~1.5 GB |
| First boot time | Fast | Slow (pulls images) |
| Requires auth | Build-time only | Runtime (embedded) |
| Offline capable | Yes | No |
| Image updates | Rebuild required | Automatic |
| Best for | Production VMs | Development |

## Recommended

**Use pre-pull for:**
- Production deployments
- Air-gapped environments
- Predictable, tested configurations
- Multiple VM instances from same image

**Use runtime pull for:**
- Development/testing
- Frequently updated images
- Smaller image requirements
