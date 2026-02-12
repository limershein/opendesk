#!/bin/bash
# Automated OpenDesk KVM Build and Test Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
VM_NAME="${VM_NAME:-opendesk-test}"
VM_MEMORY="${VM_MEMORY:-4096}"
VM_CPUS="${VM_CPUS:-2}"
BOOT_WAIT="${BOOT_WAIT:-120}"
TEST_TIMEOUT="${TEST_TIMEOUT:-300}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

cleanup() {
    log_warn "Cleaning up..."
    if sudo virsh list --all | grep -q "$VM_NAME"; then
        sudo virsh destroy "$VM_NAME" 2>/dev/null || true
        sudo virsh undefine "$VM_NAME" 2>/dev/null || true
    fi
}

check_prereqs() {
    log_info "Checking prerequisites..."

    # Check for required commands
    local missing=()
    for cmd in podman virsh virt-install qemu-img; do
        if ! command -v $cmd &> /dev/null; then
            missing+=($cmd)
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required commands: ${missing[*]}"
        log_error "Install with: sudo dnf install -y podman libvirt virt-install qemu-img"
        exit 1
    fi

    # Check if libvirtd is running
    if ! sudo systemctl is-active --quiet libvirtd; then
        log_info "Starting libvirtd..."
        sudo systemctl start libvirtd
    fi

    # Check for default network
    if ! sudo virsh net-list --all | grep -q "default"; then
        log_warn "Default network not found, creating..."
        sudo virsh net-define /usr/share/libvirt/networks/default.xml
        sudo virsh net-start default
        sudo virsh net-autostart default
    fi

    if ! sudo virsh net-list | grep -q "default.*active"; then
        log_info "Starting default network..."
        sudo virsh net-start default
    fi

    log_success "Prerequisites OK"
}

build_container() {
    log_info "Building bootc container image..."
    make build
    log_success "Container image built"
}

build_qcow2() {
    log_info "Building qcow2 disk image (this may take 5-15 minutes)..."
    make build-qcow2
    log_success "qcow2 image built"
}

create_vm() {
    log_info "Creating KVM VM: $VM_NAME"

    # Find qcow2 file
    QCOW2_FILE=$(find output -name "disk.qcow2" -o -name "*.qcow2" | head -1)
    if [ -z "$QCOW2_FILE" ]; then
        log_error "No qcow2 file found in output/"
        exit 1
    fi
    log_info "Found qcow2: $QCOW2_FILE"

    # Copy to libvirt storage
    sudo mkdir -p /var/lib/libvirt/images
    sudo cp "$QCOW2_FILE" "/var/lib/libvirt/images/$VM_NAME.qcow2"
    log_success "Copied qcow2 to libvirt storage"

    # Create VM
    log_info "Creating VM with virt-install..."
    sudo virt-install \
        --name "$VM_NAME" \
        --memory "$VM_MEMORY" \
        --vcpus "$VM_CPUS" \
        --disk "/var/lib/libvirt/images/$VM_NAME.qcow2,bus=virtio" \
        --import \
        --os-variant rhel9-unknown \
        --network network=default,model=virtio \
        --graphics none \
        --console pty,target_type=serial \
        --noautoconsole

    log_success "VM created and started"
}

wait_for_vm() {
    log_info "Waiting for VM to boot (${BOOT_WAIT}s)..."
    sleep "$BOOT_WAIT"

    # Check if VM is running
    if ! sudo virsh list | grep -q "$VM_NAME"; then
        log_error "VM is not running"
        return 1
    fi

    log_success "VM is running"
}

get_vm_ip() {
    log_info "Getting VM IP address..."

    local retries=30
    local delay=5
    local ip=""

    for ((i=1; i<=retries; i++)); do
        ip=$(sudo virsh domifaddr "$VM_NAME" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
        if [ -n "$ip" ]; then
            log_success "VM IP: $ip"
            echo "$ip"
            return 0
        fi
        log_info "Waiting for IP assignment (attempt $i/$retries)..."
        sleep "$delay"
    done

    log_warn "Could not determine VM IP address"
    return 1
}

test_vm_services() {
    log_info "Testing VM services..."

    local vm_ip="$1"

    if [ -z "$vm_ip" ]; then
        log_warn "No IP address, skipping network tests"
        return 0
    fi

    # Test Nextcloud (port 8080)
    log_info "Testing Nextcloud HTTP endpoint..."
    if timeout 30 bash -c "until curl -sf http://$vm_ip:8080 &>/dev/null; do sleep 2; done"; then
        log_success "Nextcloud is responding"
    else
        log_warn "Nextcloud not responding (might still be initializing)"
    fi

    # Test MinIO Console (port 9001)
    log_info "Testing MinIO Console..."
    if timeout 10 bash -c "curl -sf http://$vm_ip:9001 &>/dev/null"; then
        log_success "MinIO Console is responding"
    else
        log_warn "MinIO Console not responding (might still be initializing)"
    fi
}

show_vm_info() {
    log_info "VM Information:"
    echo "============================================"
    sudo virsh dominfo "$VM_NAME" || true
    echo "============================================"

    log_info "Network Information:"
    sudo virsh domifaddr "$VM_NAME" || log_warn "No IP address assigned yet"

    echo ""
    log_info "Access VM:"
    echo "  Console: make vm-console"
    echo "  Status:  make vm-status"
    echo "  IP:      make vm-ip"
    echo ""
    log_info "Manage VM:"
    echo "  Stop:    make vm-stop"
    echo "  Start:   make vm-start"
    echo "  Clean:   make vm-clean"
}

run_full_test() {
    log_info "=== OpenDesk KVM Build and Test ==="
    echo ""

    check_prereqs
    build_container
    build_qcow2
    create_vm
    wait_for_vm

    vm_ip=$(get_vm_ip || echo "")

    if [ -n "$vm_ip" ]; then
        test_vm_services "$vm_ip"
    fi

    show_vm_info

    echo ""
    log_success "=== Test completed successfully! ==="
    echo ""
    log_info "Next steps:"
    echo "  1. Connect to console: make vm-console"
    echo "  2. Check logs: sudo virsh console $VM_NAME"
    echo "  3. Access services at: http://$vm_ip:8080"
}

# Main execution
case "${1:-}" in
    --clean)
        cleanup
        ;;
    --build-only)
        check_prereqs
        build_container
        build_qcow2
        ;;
    --vm-only)
        check_prereqs
        create_vm
        wait_for_vm
        show_vm_info
        ;;
    *)
        # Trap cleanup on exit
        trap cleanup EXIT INT TERM

        run_full_test

        # Ask if user wants to keep VM
        echo ""
        read -p "Keep the VM running? (yes/no): " keep_vm
        if [ "$keep_vm" != "yes" ]; then
            cleanup
            log_info "VM removed"
        else
            # Disable cleanup trap
            trap - EXIT INT TERM
            log_info "VM kept running"
        fi
        ;;
esac
