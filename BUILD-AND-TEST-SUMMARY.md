# OpenDesk RHEL Image Mode - Build and Test Summary

## What Was Created

A complete deployment system for running OpenDesk on RHEL image mode (bootc) with KVM testing capabilities.

### Project Structure

```
opendesk/
├── bootc/
│   ├── Containerfile              # RHEL 10 bootc image definition
│   └── setup-storage.sh           # Storage setup with SELinux contexts
├── manifests-minimal/
│   ├── opendesk-minimal.yaml      # Dev/eval deployment manifest
│   └── opendesk-minimal-production.yaml  # Production manifest
├── quadlets/
│   └── opendesk-minimal.kube      # systemd quadlet for podman kube play
├── Makefile                       # Complete automation
├── test-kvm.sh                    # Automated KVM testing script
├── README.md                      # Complete documentation
├── QUICKSTART.md                  # 5-minute getting started
├── KVM-TESTING.md                 # Comprehensive KVM testing guide
└── .gitignore                     # Ignore build outputs
```

### Services Deployed

**Core Application:**
- **Nextcloud** - File management and collaboration (port 8080)

**Infrastructure (embedded mode):**
- **PostgreSQL 15** - Database (port 5432)
- **Redis 7** - Caching (port 6379)
- **MinIO** - S3-compatible storage (ports 9000, 9001)

**Architecture:**
- Single pod with 4 containers sharing network namespace
- Containers communicate via localhost
- Persistent storage in `/var/opendesk/`
- systemd-managed via quadlets
- SELinux enforcing mode

## Build Process Tested

The build was successfully tested:

```
✓ Container image built: opendesk-minimal:latest (1.57 GB)
✓ RHEL 10 bootc base image
✓ Manifests and quadlets embedded
✓ Storage directories configured
✓ SELinux contexts applied
```

## Next Steps: Build and Test with KVM

### Option 1: Automated Build and Test

Run the complete build and test pipeline:

```bash
cd /home/limershe/src/opendesk

# Automated test (builds container, qcow2, creates VM, tests)
./test-kvm.sh
```

This script will:
1. ✅ Check prerequisites (libvirt, virsh, podman, etc.)
2. ✅ Build the bootc container image
3. ✅ Use bootc-image-builder to create qcow2
4. ✅ Create KVM VM with the qcow2
5. ✅ Wait for boot and obtain IP
6. ✅ Test service connectivity
7. ✅ Display VM information

**Expected time:** 10-20 minutes (depending on system)

### Option 2: Step-by-Step with Make

```bash
cd /home/limershe/src/opendesk

# 1. Build container image (already done ✓)
make build

# 2. Build bootable qcow2 disk image (5-15 minutes)
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

### Option 3: Just Build qcow2 (No VM)

If you just want the bootable image:

```bash
make build-qcow2
```

Output will be in: `output/qcow2/disk.qcow2`

## What to Expect

### Build qcow2 Output

```
output/
└── qcow2/
    ├── disk.qcow2      # Bootable disk image (~2-3 GB)
    └── manifest.json   # Build manifest
```

### VM Creation Output

```
✓ VM created and started!
  Name: opendesk-test
  Memory: 4096 MB
  CPUs: 2

Connect to console: make vm-console
Check status: make vm-status
Get IP address: make vm-ip
```

### Boot Process

1. **GRUB** bootloader starts
2. **Kernel** loads (RHEL 10)
3. **systemd** starts as PID 1
4. **Podman quadlet** service starts
5. **Pod creation** - opendesk-minimal pod created
6. **Containers start** - PostgreSQL, Redis, MinIO, Nextcloud
7. **Services available** - Nextcloud on port 8080, MinIO on 9001

**Expected boot time:** 1-3 minutes

### Verify Services Inside VM

Once you connect to the VM console (`make vm-console`):

```bash
# Check quadlet service
systemctl status opendesk-minimal.service

# Check pod and containers
podman pod ps
podman ps -a

# Test services
curl http://localhost:8080           # Nextcloud
curl http://localhost:9001           # MinIO Console
podman exec opendesk-minimal-postgresql psql -U opendesk -c "SELECT 1;"
podman exec opendesk-minimal-redis redis-cli ping

# Check SELinux
getenforce                           # Should be: Enforcing
ls -lZ /var/opendesk/

# View logs
journalctl -u opendesk-minimal.service -f
```

## Access from Host

Once VM has an IP address:

```bash
# Get IP
VM_IP=$(make vm-ip | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}')

# Access services
curl http://$VM_IP:8080              # Nextcloud
curl http://$VM_IP:9001              # MinIO Console

# SSH into VM (if configured)
ssh root@$VM_IP
```

## Common Issues and Solutions

### Issue: bootc-image-builder fails

**Solution:**
```bash
# Ensure podman storage is accessible
sudo ls -la /var/lib/containers/storage

# Check disk space (need ~10 GB free)
df -h

# Try pulling the builder image first
sudo podman pull registry.redhat.io/rhel9/bootc-image-builder:latest
```

### Issue: VM won't start

**Solution:**
```bash
# Check libvirtd is running
sudo systemctl status libvirtd
sudo systemctl start libvirtd

# Check default network
sudo virsh net-list --all
sudo virsh net-start default
```

### Issue: Can't get VM IP

**Solution:**
```bash
# VMs need DHCP, wait 1-2 minutes after boot
sleep 120
make vm-ip

# Alternative: connect to console and check manually
make vm-console
# Inside VM: ip addr show
```

### Issue: Services not starting in VM

**Solution:**
```bash
# Connect to console
make vm-console

# Check logs
journalctl -u opendesk-minimal.service -n 100

# Check SELinux denials
ausearch -m avc -ts recent

# Verify quadlet file exists
ls -l /etc/containers/systemd/opendesk-minimal.kube
cat /etc/opendesk/manifests/opendesk-minimal.yaml
```

## Performance Notes

### Build Resources

- **Container build:** ~30 seconds, 1.57 GB image
- **qcow2 build:** 5-15 minutes, ~2-3 GB disk image
- **Disk space needed:** ~10 GB total

### VM Resources

- **Default:** 4 GB RAM, 2 CPUs
- **Recommended:** 8 GB RAM, 4 CPUs for production testing
- **Minimum:** 2 GB RAM, 1 CPU (may be slow)

Adjust in Makefile:
```makefile
VM_MEMORY := 8192  # 8 GB
VM_CPUS := 4       # 4 cores
```

## Production Deployment

After successful VM testing:

### 1. Deploy to Bare Metal

```bash
# Write qcow2 to disk
sudo dd if=output/qcow2/disk.qcow2 of=/dev/sdX bs=4M status=progress

# Or convert to ISO and boot
# (See KVM-TESTING.md for details)
```

### 2. Use Production Manifest

Edit `manifests-minimal/opendesk-minimal-production.yaml`:
- Replace `EXTERNAL_POSTGRES_HOST` with your PostgreSQL server
- Replace `EXTERNAL_REDIS_HOST` with your Redis server
- Replace `EXTERNAL_S3_*` with your S3 credentials

### 3. Configure Secrets

Use proper secrets management:
```bash
# podman secrets
echo "mypassword" | podman secret create db_password -

# systemd credentials
systemd-creds encrypt - db-password.cred
```

## Make Command Reference

### Build Commands

| Command | Description | Time |
|---------|-------------|------|
| `make build` | Build bootc container | ~30s |
| `make build-qcow2` | Build qcow2 from container | 5-15m |

### VM Commands

| Command | Description |
|---------|-------------|
| `make vm-create` | Build qcow2 and create VM |
| `make vm-start` | Start stopped VM |
| `make vm-stop` | Stop running VM |
| `make vm-status` | Show VM status |
| `make vm-console` | Connect to serial console |
| `make vm-ip` | Get VM IP address |
| `make vm-clean` | Destroy and remove VM |

### Deployment Commands

| Command | Description |
|---------|-------------|
| `make deploy` | Deploy on current host |
| `make deploy-prod` | Deploy production config |
| `make status` | Show service status |
| `make logs` | Follow service logs |
| `make backup` | Create backup |
| `make clean` | Remove deployment |

### Utility Commands

| Command | Description |
|---------|-------------|
| `make help` | Show all commands |
| `make test` | Run connectivity tests |
| `make update-images` | Pull latest images |
| `make selinux-status` | Check SELinux |

## Quick Reference Card

```bash
# BUILD AND TEST WORKFLOW
cd /home/limershe/src/opendesk

# Option A: Automated
./test-kvm.sh

# Option B: Manual
make build           # Build container (done ✓)
make build-qcow2     # Build qcow2 disk
make vm-create       # Create VM
make vm-status       # Check status
make vm-ip           # Get IP
make vm-console      # Connect (Ctrl+] to exit)

# Inside VM
systemctl status opendesk-minimal.service
podman ps -a
curl http://localhost:8080

# Cleanup
make vm-clean        # Remove VM
rm -rf output/       # Remove qcow2
```

## Documentation

- **README.md** - Complete documentation with all deployment options
- **QUICKSTART.md** - Get running in 5 minutes
- **KVM-TESTING.md** - Comprehensive KVM testing guide (this file has everything)
- **BUILD-AND-TEST-SUMMARY.md** - This summary

## Support and Troubleshooting

1. **Check logs:** `make vm-console` then `journalctl -u opendesk-minimal.service -f`
2. **Verify SELinux:** `getenforce` should show "Enforcing"
3. **Check networking:** `make vm-ip` and `ping <VM_IP>`
4. **Review docs:** See KVM-TESTING.md for comprehensive troubleshooting

## Success Criteria

Your deployment is successful when:

- ✅ Container image builds without errors
- ✅ qcow2 image is created in `output/qcow2/`
- ✅ VM boots and obtains an IP address
- ✅ systemd is running as PID 1
- ✅ opendesk-minimal.service is active
- ✅ All 4 containers are running
- ✅ Nextcloud responds on port 8080
- ✅ MinIO responds on port 9001
- ✅ SELinux is enforcing
- ✅ No critical errors in logs

## Ready to Start?

```bash
cd /home/limershe/src/opendesk
./test-kvm.sh
```

Good luck! 🚀
