#!/bin/bash
# OpenDesk Storage Setup Script
# Configures persistent storage directories with proper SELinux contexts

set -euo pipefail

# Storage directories
STORAGE_ROOT="/var/opendesk"
DIRECTORIES=(
    "postgres"
    "redis"
    "minio"
    "nextcloud"
)

echo "Setting up OpenDesk storage directories..."

# Create directories if they don't exist
for dir in "${DIRECTORIES[@]}"; do
    DIR_PATH="${STORAGE_ROOT}/${dir}"
    if [ ! -d "$DIR_PATH" ]; then
        echo "Creating directory: $DIR_PATH"
        mkdir -p "$DIR_PATH"
    fi
done

# Set proper permissions
echo "Setting permissions..."
chmod -R 755 "$STORAGE_ROOT"

# Set SELinux contexts
# Use :Z flag for private volume (exclusive to one container)
# Use :z flag for shared volume (shared among multiple containers)
if command -v chcon &> /dev/null; then
    echo "Configuring SELinux contexts..."

    # Set container_file_t for all storage directories
    chcon -R -t container_file_t "$STORAGE_ROOT" || {
        echo "Warning: Failed to set SELinux context. SELinux might be disabled."
    }

    # Verify contexts
    echo "Current SELinux contexts:"
    ls -ldZ "$STORAGE_ROOT"/*
else
    echo "chcon not found. Skipping SELinux configuration."
fi

echo "Storage setup complete!"

# Display summary
echo ""
echo "Storage directories created:"
for dir in "${DIRECTORIES[@]}"; do
    echo "  - ${STORAGE_ROOT}/${dir}"
done

echo ""
echo "To mount these with proper SELinux labels in podman, use:"
echo "  -v /var/opendesk/postgres:/var/lib/pgsql/data:Z"
echo ""
echo "Note: The :Z flag relabels content to be private to the container"
echo "      The :z flag relabels content to be shareable among containers"
