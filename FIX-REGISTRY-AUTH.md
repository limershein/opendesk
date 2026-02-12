# Fix Red Hat Registry Authentication for Systemd Services

## Problem

The OpenDesk quadlet service fails with:
```
Error: unauthorized: Please login to the Red Hat Registry using your Customer Portal credentials
```

Even though you're logged in as a user, the systemd service runs as **root** and needs separate authentication.

## Solution

Log in to the Red Hat registry as root:

```bash
# Log in as root with your Red Hat Customer Portal credentials
sudo podman login registry.redhat.io
```

**Enter:**
- Username: Your Red Hat Customer Portal username
- Password: Your Red Hat Customer Portal password

## Why This Is Needed

1. **User login:** `~/.config/containers/auth.json` or `/run/user/UID/containers/auth.json`
2. **Root login:** `/root/.config/containers/auth.json` or `/run/containers/0/auth.json`

Systemd services run as root, so they use root's authentication.

## Verify

After logging in as root:

```bash
# Check root is logged in
sudo podman login registry.redhat.io --get-login

# Should show your username
```

## Restart OpenDesk Service

```bash
# Restart the service
sudo systemctl restart opendesk-minimal.service

# Check status
sudo systemctl status opendesk-minimal.service

# Watch logs
sudo journalctl -u opendesk-minimal.service -f
```

## Alternative: Use Shared Auth

If you want to avoid duplicate logins, you can use a shared auth file:

```bash
# Create shared auth location
sudo mkdir -p /etc/containers

# Copy your auth to system location
sudo cp /run/user/$(id -u)/containers/auth.json /etc/containers/auth.json

# Set permissions
sudo chmod 600 /etc/containers/auth.json
```

Then configure podman to use it system-wide in `/etc/containers/registries.conf`.

## Quick Fix

Just run this command now:

```bash
sudo podman login registry.redhat.io
```

Then restart the service:

```bash
sudo systemctl restart opendesk-minimal.service
```

That should fix it! ✅
