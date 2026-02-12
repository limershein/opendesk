# OpenDesk KVM Testing Guide

Complete guide for building and testing OpenDesk bootc images in KVM.

## Overview

This guide walks through:
1. Building a bootc container image
2. Converting it to a bootable qcow2 disk image
3. Creating and testing a KVM virtual machine
4. Validating the OpenDesk deployment

## Prerequisites

### System Requirements

- **RHEL/Fedora** with KVM support
- **8 GB RAM minimum** (for both host and VM)
- **30 GB disk space** for images and VM
- **CPU virtualization** enabled (Intel VT-x or AMD-V)

### Required Packages

```bash
# Install virtualization packages
sudo dnf install -y \
    libvirt \
    virt-install \
    virt-manager \
    qemu-kvm \
    qemu-img

# Start and enable libvirtd
sudo systemctl enable --now libvirtd

# Add your user to libvirt group
sudo usermod -aG libvirt $(whoami)
# Log out and back in for group changes to take effect
```

### Verify KVM Support

```bash
# Check CPU virtualization support
egrep -c '(vmx|svm)' /proc/cpuinfo
# Should return > 0

# Check KVM modules
lsmod | grep kvm
# Should show kvm and kvm_intel or kvm_amd

# Verify libvirtd is running
sudo systemctl status libvirtd
```

## Quick Build and Test

### One-Command Build and Deploy

```bash
cd /home/$(whoami)/src/opendesk

# Build container, create qcow2, create and start VM
make vm-create
```

This single command will:
1. Build the bootc container image
2. Use bootc-image-builder to create a qcow2
3. Copy the qcow2 to libvirt storage
4. Create and start a KVM VM
5. Configure networking

### Connect to the VM

```bash
# View VM status
make vm-status

# Get VM IP address
make vm-ip

# Connect to serial console
make vm-console
```

## Step-by-Step Process

### Step 1: Build Container Image

```bash
# Build the bootc container image
make build
```

This creates a container image `opendesk-minimal:latest` with:
- RHEL bootc base
- Podman installed
- OpenDesk manifests and quadlets
- SELinux configurations

Verify the image:
```bash
podman images | grep opendesk-minimal
```

### Step 2: Build qcow2 Disk Image

```bash
# Build bootable qcow2 from container image
make build-qcow2
```

**What happens:**
1. Creates `output/` directory
2. Runs `bootc-image-builder` container
3. Converts container image to bootable disk
4. Outputs to `output/qcow2/disk.qcow2`

**Build time:** 5-15 minutes depending on your system

**Expected output structure:**
```
output/
└── qcow2/
    ├── disk.qcow2
    └── manifest.json
```

**Troubleshooting build failures:**

If the build fails, check:
```bash
# Ensure podman storage is accessible
ls -la /var/lib/containers/storage

# Check available disk space
df -h

# View bootc-image-builder logs (run build manually with less redirection)
sudo podman run --rm -it --privileged \
    --pull=newer \
    --security-opt label=type:unconfined_t \
    -v $(PWD)/output:/output \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    registry.redhat.io/rhel9/bootc-image-builder:latest \
    --type qcow2 \
    --local \
    localhost/opendesk-minimal:latest
```

### Step 3: Create KVM VM

```bash
# Create and start VM
make vm-create
```

**VM Configuration:**
- **Name:** opendesk-test
- **Memory:** 4096 MB (4 GB)
- **CPUs:** 2
- **Disk:** virtio
- **Network:** virtio with NAT (default network)
- **Graphics:** none (serial console only)

**Customize VM resources:**

Edit the Makefile variables:
```makefile
VM_NAME := opendesk-test
VM_MEMORY := 8192    # Change to 8 GB
VM_CPUS := 4         # Change to 4 CPUs
```

### Step 4: Access the VM

#### Serial Console

```bash
# Connect to serial console
make vm-console

# Ctrl+] to disconnect
```

#### SSH Access

Once the VM has booted and obtained an IP:

```bash
# Get the IP address
make vm-ip

# SSH into the VM (assuming default networking)
ssh root@<VM_IP>
# or
ssh <username>@<VM_IP>
```

**Note:** You may need to configure SSH keys or set passwords during first boot.

### Step 5: Verify OpenDesk Services

Once logged into the VM:

```bash
# Check if quadlet service is running
systemctl status opendesk-minimal.service

# Check pod status
podman pod ps

# Check container status
podman ps -a

# View logs
journalctl -u opendesk-minimal.service -f
```

Access OpenDesk services:

```bash
# From the VM
curl http://localhost:8080

# From your host (if networking is configured)
curl http://<VM_IP>:8080
```

## VM Management

### Check VM Status

```bash
# Show VM status
make vm-status

# List all VMs
sudo virsh list --all
```

### Start/Stop VM

```bash
# Start VM
make vm-start

# Stop VM (graceful shutdown)
make vm-stop

# Force stop
sudo virsh destroy opendesk-test
```

### VM Networking

#### View Network Configuration

```bash
# Show VM network interfaces
sudo virsh domiflist opendesk-test

# Get IP address
make vm-ip

# Alternative: from inside VM
ip addr show
```

#### Configure Port Forwarding

To access services from your host:

```bash
# Forward port 8080 from VM to host port 8080
sudo firewall-cmd --add-forward-port=port=8080:proto=tcp:toaddr=<VM_IP>:toport=8080

# Or use iptables
sudo iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination <VM_IP>:8080
```

#### Bridge Networking (Optional)

For direct network access, configure bridge networking:

1. Create bridge network:
```bash
sudo nmcli connection add type bridge con-name br0 ifname br0
sudo nmcli connection modify br0 ipv4.method manual ipv4.addresses 192.168.100.1/24
```

2. Update VM to use bridge:
```bash
sudo virsh edit opendesk-test
# Change <interface> to use bridge
```

### VM Snapshots

```bash
# Create snapshot
sudo virsh snapshot-create-as --domain opendesk-test \
    --name "pre-test" \
    --description "Before testing"

# List snapshots
sudo virsh snapshot-list opendesk-test

# Restore snapshot
sudo virsh snapshot-revert opendesk-test pre-test

# Delete snapshot
sudo virsh snapshot-delete opendesk-test pre-test
```

### Clone VM

```bash
# Clone the VM
sudo virt-clone \
    --original opendesk-test \
    --name opendesk-test-clone \
    --auto-clone
```

## Testing OpenDesk

### Automated Tests

From inside the VM:

```bash
# Run connectivity tests
make test

# Check individual services
podman exec opendesk-minimal-postgresql psql -U opendesk -c "SELECT version();"
podman exec opendesk-minimal-redis redis-cli ping
curl -I http://localhost:8080  # Nextcloud
curl -I http://localhost:9001  # MinIO Console
```

### Manual Testing Checklist

- [ ] VM boots successfully
- [ ] systemd is running as PID 1
- [ ] OpenDesk quadlet service is active
- [ ] All containers are running (postgresql, redis, minio, nextcloud)
- [ ] PostgreSQL is accessible
- [ ] Redis is responding
- [ ] MinIO is accessible
- [ ] Nextcloud web interface loads
- [ ] Persistent storage is working
- [ ] SELinux is enforcing
- [ ] No SELinux denials

### Performance Testing

```bash
# Monitor resource usage
virsh domstats opendesk-test

# View CPU usage
virsh cpu-stats opendesk-test

# View memory usage
virsh dommemstat opendesk-test

# Inside VM
top
htop
podman stats
```

## Troubleshooting

### VM Won't Boot

```bash
# View boot logs
sudo virsh console opendesk-test

# Check VM XML definition
sudo virsh dumpxml opendesk-test

# Verify qcow2 integrity
qemu-img check /var/lib/libvirt/images/opendesk-test.qcow2

# Boot in rescue mode
sudo virsh edit opendesk-test
# Add to <os> section:
#   <kernel>/path/to/rescue/kernel</kernel>
#   <initrd>/path/to/rescue/initrd</initrd>
```

### Networking Issues

```bash
# Check default network is running
sudo virsh net-list --all

# Start default network if stopped
sudo virsh net-start default
sudo virsh net-autostart default

# Check firewall
sudo firewall-cmd --list-all

# From inside VM
ip link
ip route
ping 8.8.8.8
```

### Services Not Starting

```bash
# Inside VM, check quadlet service
systemctl status opendesk-minimal.service
journalctl -u opendesk-minimal.service -n 100

# Check SELinux denials
ausearch -m avc -ts recent

# Check container logs
podman logs opendesk-minimal-nextcloud
```

### SELinux Issues

```bash
# Inside VM
getenforce  # Should be Enforcing

# Check contexts
ls -lZ /var/opendesk/

# Relabel if needed
restorecon -Rv /var/opendesk/

# Check for denials
ausearch -m avc -ts recent

# Temporarily permissive (for debugging only)
setenforce 0
```

## Cleanup

### Remove VM Only

```bash
# Stop and remove VM, keep disk image
make vm-clean
```

### Remove Everything

```bash
# Remove VM
make vm-clean

# Remove qcow2 output
rm -rf output/

# Remove container images
podman rmi opendesk-minimal:latest
```

## Advanced Usage

### Custom VM Configuration

Create a custom VM with specific settings:

```bash
sudo virt-install \
    --name opendesk-production \
    --memory 8192 \
    --vcpus 4 \
    --disk path=/var/lib/libvirt/images/opendesk-production.qcow2,size=50 \
    --cdrom output/qcow2/disk.qcow2 \
    --os-variant rhel9-unknown \
    --network bridge=br0 \
    --graphics spice \
    --noautoconsole
```

### Use virt-manager GUI

```bash
# Launch virt-manager
virt-manager

# Import existing VM
# File > Add Connection > QEMU/KVM
# Import existing disk: /var/lib/libvirt/images/opendesk-test.qcow2
```

### Convert to Other Formats

```bash
# Convert qcow2 to raw
qemu-img convert -f qcow2 -O raw \
    output/qcow2/disk.qcow2 \
    opendesk-minimal.raw

# Convert to vmdk (for VMware)
qemu-img convert -f qcow2 -O vmdk \
    output/qcow2/disk.qcow2 \
    opendesk-minimal.vmdk

# Convert to vdi (for VirtualBox)
qemu-img convert -f qcow2 -O vdi \
    output/qcow2/disk.qcow2 \
    opendesk-minimal.vdi
```

### Cloud-init Configuration

For automated VM configuration, add cloud-init:

```bash
# Create cloud-init ISO
cloud-localds cloud-init.iso cloud-init.yaml

# Attach to VM
sudo virsh attach-disk opendesk-test \
    --source $(PWD)/cloud-init.iso \
    --target sdb \
    --driver qemu \
    --subdriver raw \
    --type cdrom
```

## Performance Optimization

### VM Performance Tuning

```bash
# Enable hugepages
echo 1024 | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages

# Update VM to use hugepages
sudo virsh edit opendesk-test
# Add to <memoryBacking>:
#   <hugepages/>
```

### Disk Performance

```bash
# Use cache=none for better performance
sudo virsh edit opendesk-test
# Change disk cache to:
#   <driver name='qemu' type='qcow2' cache='none'/>

# Use virtio-scsi instead of virtio-blk
# Edit disk interface to use bus='scsi'
```

## CI/CD Integration

### Automated Testing Script

```bash
#!/bin/bash
set -e

# Build and test
make build
make build-qcow2
make vm-create

# Wait for VM to boot
sleep 60

# Get IP
VM_IP=$(sudo virsh domifaddr opendesk-test | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)

# Test connectivity
curl -f http://$VM_IP:8080 || exit 1

# Cleanup
make vm-clean
```

## References

- [libvirt Documentation](https://libvirt.org/docs.html)
- [RHEL Virtualization Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/configuring_and_managing_virtualization/)
- [bootc Image Builder](https://github.com/osbuild/bootc-image-builder)
- [virt-install Man Page](https://linux.die.net/man/1/virt-install)

## Quick Reference

| Task | Command |
|------|---------|
| Build container | `make build` |
| Build qcow2 | `make build-qcow2` |
| Create VM | `make vm-create` |
| Start VM | `make vm-start` |
| Stop VM | `make vm-stop` |
| VM status | `make vm-status` |
| VM console | `make vm-console` |
| VM IP | `make vm-ip` |
| Remove VM | `make vm-clean` |
| List VMs | `sudo virsh list --all` |
| VM info | `sudo virsh dominfo opendesk-test` |
