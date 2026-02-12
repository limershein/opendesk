# Podman Quadlets Explained

## What are Quadlets?

Podman quadlets are systemd unit files that automatically generate container services. They simplify container management by integrating containers with systemd.

## How Quadlets Work

### Traditional systemd Service

With a regular systemd service:
1. Create `/etc/systemd/system/myservice.service`
2. Run `systemctl daemon-reload`
3. Run `systemctl enable myservice.service` (creates symlink)
4. Run `systemctl start myservice.service`

### Podman Quadlet

With podman quadlets:
1. Create `/etc/containers/systemd/myservice.kube` (or `.container`, `.pod`, etc.)
2. Run `systemctl daemon-reload`
3. **Quadlet is automatically "enabled"** - no `systemctl enable` needed!
4. Run `systemctl start myservice.service`

## Key Differences

### Location

- **Quadlet files:** `/etc/containers/systemd/*.kube`
- **Generated services:** `/run/systemd/generator/*.service` (transient)

### Enablement

**Quadlets are enabled by their mere presence** in `/etc/containers/systemd/`.

```bash
# ❌ WRONG - This fails!
sudo systemctl enable opendesk-minimal.service
# Error: Unit /run/systemd/generator/opendesk-minimal.service is transient or generated

# ✅ RIGHT - Just start it!
sudo systemctl daemon-reload
sudo systemctl start opendesk-minimal.service
```

### Auto-start on Boot

The quadlet file in `/etc/containers/systemd/` ensures the service starts on boot.

**To enable:** Place `.kube` file in `/etc/containers/systemd/`
**To disable:** Remove the `.kube` file and `systemctl daemon-reload`

## OpenDesk Quadlet

### File: `/etc/containers/systemd/opendesk-minimal.kube`

```ini
[Unit]
Description=OpenDesk Minimal Deployment
Documentation=https://docs.opendesk.eu/
After=network-online.target
Wants=network-online.target

[Kube]
Yaml=/etc/opendesk/manifests/opendesk-minimal.yaml
AutoUpdate=registry
ExitCodePropagation=all
PublishPort=8080:80

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
```

### What This Does

1. **systemd-generator** reads the `.kube` file during `daemon-reload`
2. Generates a transient systemd service: `opendesk-minimal.service`
3. The `[Install]` section is honored for boot-time startup
4. The service runs `podman kube play` with the specified YAML

### Generated Service

After `systemctl daemon-reload`, systemd creates a generated service:

```bash
# View the generated service
systemctl cat opendesk-minimal.service
```

This is located in `/run/systemd/generator/` and is **transient** (recreated on each daemon-reload).

## Common Operations

### Deploy

```bash
# Copy quadlet file
sudo cp quadlets/opendesk-minimal.kube /etc/containers/systemd/

# Copy manifest
sudo cp manifests-minimal/opendesk-minimal.yaml /etc/opendesk/manifests/

# Generate the service
sudo systemctl daemon-reload

# Start it
sudo systemctl start opendesk-minimal.service

# ✅ It will now start automatically on boot!
```

### Check Status

```bash
# Check if running
systemctl status opendesk-minimal.service

# View logs
journalctl -u opendesk-minimal.service -f

# Check the pod
podman pod ps
podman ps -a
```

### Stop and Disable

```bash
# Stop the service
sudo systemctl stop opendesk-minimal.service

# Disable (remove quadlet file)
sudo rm /etc/containers/systemd/opendesk-minimal.kube
sudo systemctl daemon-reload

# ✅ Service is now gone and won't start on boot
```

### Restart After Changes

If you modify the manifest or quadlet:

```bash
# Restart the service
sudo systemctl restart opendesk-minimal.service

# Or reload quadlet and restart
sudo systemctl daemon-reload
sudo systemctl restart opendesk-minimal.service
```

## Troubleshooting

### "Unit is transient or generated" Error

**Problem:**
```bash
$ sudo systemctl enable opendesk-minimal.service
Failed to enable unit: Unit ... is transient or generated
```

**Solution:**
Don't use `systemctl enable` for quadlets! They're enabled automatically.

### Service Not Found

**Problem:**
```bash
$ systemctl status opendesk-minimal.service
Unit opendesk-minimal.service could not be found.
```

**Check:**
1. Is the `.kube` file in `/etc/containers/systemd/`?
2. Did you run `systemctl daemon-reload`?

```bash
# Verify quadlet file exists
ls -l /etc/containers/systemd/opendesk-minimal.kube

# Reload systemd
sudo systemctl daemon-reload

# Check if generated
systemctl list-units | grep opendesk
```

### Service Won't Start on Boot

**Check the [Install] section:**

```ini
[Install]
WantedBy=multi-user.target
```

This must be present in the quadlet file.

### Update Not Taking Effect

After modifying the quadlet or manifest:

```bash
# Always reload and restart
sudo systemctl daemon-reload
sudo systemctl restart opendesk-minimal.service
```

## Quadlet Types

Podman supports several quadlet types:

- **`.container`** - Single container
- **`.kube`** - Kubernetes YAML (pod with multiple containers)
- **`.pod`** - Podman pod
- **`.volume`** - Podman volume
- **`.network`** - Podman network

OpenDesk uses **`.kube`** for multi-container pod deployment.

## Benefits of Quadlets

1. **Systemd Integration** - Full systemd features (dependencies, restart policies, etc.)
2. **Automatic Enablement** - No separate enable step
3. **Declarative** - Define once, systemd manages lifecycle
4. **Boot Integration** - Starts automatically on boot
5. **Logging** - Uses journalctl for consistent logging
6. **Resource Control** - Can use systemd resource limits

## References

- [Podman Quadlet Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [Red Hat Quadlet Guide](https://www.redhat.com/sysadmin/quadlet-podman)
- [systemd.unit Man Page](https://www.freedesktop.org/software/systemd/man/systemd.unit.html)

## Quick Reference

| Task | Command |
|------|---------|
| Install quadlet | Copy `.kube` to `/etc/containers/systemd/` |
| Generate service | `systemctl daemon-reload` |
| Start service | `systemctl start <name>.service` |
| Enable on boot | Automatic (quadlet file presence) |
| Disable | Remove `.kube` + `daemon-reload` |
| Check status | `systemctl status <name>.service` |
| View logs | `journalctl -u <name>.service` |
| Restart | `systemctl restart <name>.service` |
| View generated | `systemctl cat <name>.service` |
