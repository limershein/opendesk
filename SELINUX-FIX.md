# SELinux Policy Fix for OpenDesk

## The Problem

When running podman containers via systemd quadlets on RHEL 10, SELinux blocks:

1. **BPF Program Execution**: systemd (init_t) cannot run BPF programs needed by podman for networking and cgroup management
2. **Container /proc Access**: Containers cannot associate with the proc filesystem

### Specific Denials

```
avc: denied { prog_run } for pid=1 comm="systemd"
  scontext=system_u:system_r:init_t:s0
  tcontext=system_u:system_r:container_runtime_t:s0
  tclass=bpf permissive=0
```

```
avc: denied { associate } for pid=63714 comm="apache2"
  scontext=system_u:object_r:container_t:s0:c352,c647
  tcontext=system_u:object_r:proc_t:s0
  tclass=filesystem permissive=0
```

## The Solution

Created a custom SELinux policy module: **opendesk-selinux**

### Policy Rules

**File: `bootc/opendesk-selinux.te`**

1. **Allow systemd BPF operations**:
   - `prog_run` - Run BPF programs
   - `map_create` - Create BPF maps
   - `map_read/write` - Read/write BPF maps
   - `prog_load` - Load BPF programs

2. **Allow container proc access**:
   - `associate` - Containers can access /proc filesystem

### How It's Applied

The SELinux policy is compiled and installed **during image build**:

1. **Copy** the `.te` (type enforcement) source file
2. **Compile** with `checkmodule` to create `.mod` file
3. **Package** with `semodule_package` to create `.pp` file
4. **Install** with `semodule -i` into the image
5. **Cleanup** temporary files

This ensures the policy is present when the VM boots.

## Files Modified

1. **`bootc/opendesk-selinux.te`** - SELinux policy source (NEW)
2. **`bootc/Containerfile`** - Added policy compilation and installation

## Verification

After rebuilding and booting the VM:

```bash
# Check policy is installed
sudo semodule -l | grep opendesk

# Verify SELinux is enforcing
getenforce

# No denials should appear
sudo dmesg | grep -i "avc.*denied"

# Containers should start successfully
sudo systemctl status opendesk-minimal.service
sudo podman ps
```

## Technical Details

### Why BPF is Needed

Modern container runtimes use BPF for:
- **Network filtering** - CNI plugins use BPF for networking
- **Cgroup management** - Resource limiting via BPF programs
- **Observability** - Container metrics collection

### Why This is Safe

The policy only allows:
- systemd (trusted init process) to manage BPF programs
- Only for container_runtime_t context (podman)
- Containers to access standard /proc filesystem

This follows the principle of least privilege - only the specific access needed for containers to function.

## Alternative: Permissive Mode (NOT RECOMMENDED)

If you want to temporarily bypass SELinux (testing only):

```bash
# TEMPORARY - Does not persist
sudo setenforce 0

# Check
getenforce  # Shows: Permissive
```

**Never use permissive mode in production!**

## Testing the Fix

After rebuild:

```bash
# On host
make vm-clean
make build
make build-qcow2
make vm-create

# Wait for boot, then connect
make vm-console
# Login: admin / opendesk

# Inside VM - verify
getenforce  # Should be: Enforcing
sudo semodule -l | grep opendesk  # Should show: opendesk-selinux
sudo systemctl status opendesk-minimal.service  # Should be: active
sudo podman ps  # Should show 4 containers running
```

## Troubleshooting

### If containers still fail with SELinux enforcing:

```bash
# Check for new denials
sudo dmesg | grep -i "avc.*denied" | tail -20

# If you see denials, update the policy:
# 1. Note the denial details
# 2. Add rules to opendesk-selinux.te
# 3. Rebuild the image
```

### If policy doesn't install:

```bash
# Check build logs for errors
# The Containerfile runs:
checkmodule -M -m -o opendesk-selinux.mod opendesk-selinux.te
semodule_package -o opendesk-selinux.pp -m opendesk-selinux.mod
semodule -i opendesk-selinux.pp

# Any errors will appear during image build
```

## References

- [SELinux BPF Support](https://access.redhat.com/articles/6988842)
- [Podman SELinux](https://github.com/containers/podman/blob/main/troubleshooting.md#26-running-containers-with-selinux-enforcing)
- [Writing SELinux Policy](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/using_selinux/writing-a-custom-selinux-policy_using-selinux)
