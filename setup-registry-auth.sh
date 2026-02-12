#!/bin/bash
# Setup Red Hat registry authentication for bootc image build

set -e

echo "=== OpenDesk Registry Authentication Setup ==="
echo ""
echo "This script will set up Red Hat registry authentication for the bootc image build."
echo ""

# Check if already logged in as root
if sudo podman login registry.redhat.io --get-login &>/dev/null; then
    USERNAME=$(sudo podman login registry.redhat.io --get-login)
    echo "✓ Already logged in to registry.redhat.io as: $USERNAME"
    echo ""
else
    echo "You need to log in to registry.redhat.io with your Red Hat Customer Portal credentials."
    echo ""

    # Login
    sudo podman login registry.redhat.io

    if [ $? -ne 0 ]; then
        echo ""
        echo "❌ Login failed. Please check your credentials and try again."
        exit 1
    fi

    echo ""
    echo "✓ Successfully logged in to registry.redhat.io"
    echo ""
fi

# Find the auth file - check multiple possible locations
AUTH_FILE=""
POSSIBLE_LOCATIONS=(
    "/root/.config/containers/auth.json"
    "/run/containers/0/auth.json"
    "/run/user/0/containers/auth.json"
    "$HOME/.config/containers/auth.json"
)

echo "Searching for auth.json file..."
for location in "${POSSIBLE_LOCATIONS[@]}"; do
    echo "  Checking: $location"
    if sudo test -f "$location"; then
        AUTH_FILE="$location"
        echo "  ✓ Found!"
        break
    fi
done

if [ -z "$AUTH_FILE" ]; then
    echo ""
    echo "❌ Could not find auth.json file"
    echo ""
    echo "Searched locations:"
    for location in "${POSSIBLE_LOCATIONS[@]}"; do
        echo "  - $location"
    done
    echo ""
    echo "This may indicate the login didn't complete successfully."
    echo "Try manually running: sudo podman login registry.redhat.io"
    exit 1
fi

echo ""
echo "Found auth file: $AUTH_FILE"

# Copy to bootc directory
echo "Copying auth file to bootc/registry-auth.json..."
sudo cp "$AUTH_FILE" bootc/registry-auth.json

# Make it readable for build
sudo chmod 644 bootc/registry-auth.json

# Verify
if grep -q "registry.redhat.io" bootc/registry-auth.json; then
    echo ""
    echo "✓ Success! Registry authentication is configured."
    echo ""
    echo "The auth file has been copied to: bootc/registry-auth.json"
    echo ""
    echo "You can now build the image with: make build"
else
    echo ""
    echo "❌ Warning: auth file doesn't contain registry.redhat.io credentials"
    echo "The file was copied but may not work correctly."
fi

echo ""
echo "Note: This auth file will be embedded in the bootc image."
echo "For production, consider using a Red Hat service account instead of personal credentials."
echo "Create one at: https://access.redhat.com/terms-based-registry/"
