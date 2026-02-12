#!/bin/bash
# Fix: Load the opendesk-minimal image into root's podman storage
# so bootc-image-builder can find it

set -e

echo "Loading opendesk-minimal:latest into root's podman storage..."

# Load the saved image as root
sudo podman load -i /tmp/opendesk-minimal.tar

echo "Verifying image in root storage..."
sudo podman images | grep opendesk-minimal

echo ""
echo "✓ Image loaded successfully!"
echo "You can now run: make build-qcow2"
