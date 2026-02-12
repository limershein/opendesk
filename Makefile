.PHONY: help build build-nextcloud build-qcow2 deploy deploy-prod setup-storage clean logs status vm-create vm-start vm-stop vm-clean

IMAGE_NAME := opendesk-minimal
IMAGE_TAG := latest
NEXTCLOUD_IMAGE := opendesk-nextcloud
NEXTCLOUD_TAG := latest
QCOW2_OUTPUT := output
VM_NAME := opendesk-test
VM_MEMORY := 4096
VM_CPUS := 2

help: ## Show this help message
	@echo "OpenDesk RHEL Image Mode Deployment"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

setup-registry: ## Setup Red Hat registry authentication
	@echo "Setting up Red Hat registry authentication..."
	./setup-registry-auth.sh

build-nextcloud: ## Build UBI9-based Nextcloud container image
	@echo "Building UBI9 Nextcloud image: $(NEXTCLOUD_IMAGE):$(NEXTCLOUD_TAG)"
	podman build -f containers/nextcloud/Containerfile -t $(NEXTCLOUD_IMAGE):$(NEXTCLOUD_TAG) .

pull-images: build-nextcloud ## Pull and save container images for bootc image
	@echo "Pulling container images..."
	@if [ ! -f bootc/registry-auth.json ]; then \
		echo ""; \
		echo "❌ Error: bootc/registry-auth.json not found"; \
		echo ""; \
		echo "You need to set up Red Hat registry authentication first."; \
		echo "Run: make setup-registry"; \
		echo ""; \
		exit 1; \
	fi
	@# Temporarily use the auth file for pulling
	@echo "Pulling PostgreSQL 15..."
	@REGISTRY_AUTH_FILE=bootc/registry-auth.json podman pull registry.redhat.io/rhel9/postgresql-15:latest
	@echo "Pulling Redis 7..."
	@REGISTRY_AUTH_FILE=bootc/registry-auth.json podman pull registry.redhat.io/rhel9/redis-7:latest
	@echo "Pulling MinIO..."
	@REGISTRY_AUTH_FILE=bootc/registry-auth.json podman pull quay.io/minio/minio:latest
	@echo ""
	@echo "Saving images to separate tar files..."
	@rm -f bootc/postgres.tar bootc/redis.tar bootc/minio.tar bootc/nextcloud.tar
	@echo "  Saving PostgreSQL..."
	@podman save registry.redhat.io/rhel9/postgresql-15:latest -o bootc/postgres.tar
	@echo "  Saving Redis..."
	@podman save registry.redhat.io/rhel9/redis-7:latest -o bootc/redis.tar
	@echo "  Saving MinIO..."
	@podman save quay.io/minio/minio:latest -o bootc/minio.tar
	@echo "  Saving Nextcloud (UBI9)..."
	@podman save localhost/$(NEXTCLOUD_IMAGE):$(NEXTCLOUD_TAG) -o bootc/nextcloud.tar
	@echo "✓ Images saved to separate tar files"
	@ls -lh bootc/*.tar

build: pull-images ## Build the bootc container image
	@echo "Building bootc image: $(IMAGE_NAME):$(IMAGE_TAG)"
	@if [ ! -f bootc/postgres.tar ] || [ ! -f bootc/redis.tar ] || [ ! -f bootc/minio.tar ] || [ ! -f bootc/nextcloud.tar ]; then \
		echo ""; \
		echo "❌ Error: Image tar files not found"; \
		echo ""; \
		echo "Run: make pull-images"; \
		echo ""; \
		exit 1; \
	fi
	podman build -f bootc/Containerfile -t $(IMAGE_NAME):$(IMAGE_TAG) .

build-qcow2: build ## Build bootable qcow2 disk image
	@echo "Building qcow2 disk image from $(IMAGE_NAME):$(IMAGE_TAG)..."
	@echo "This will use bootc-image-builder container"
	@echo ""
	@echo "Step 1: Ensuring latest image is available to root's podman..."
	@# Always update the image in root storage to ensure we use the latest build
	@echo "Saving image from user storage..."
	@rm -f /tmp/$(IMAGE_NAME).tar
	@podman image save localhost/$(IMAGE_NAME):$(IMAGE_TAG) -o /tmp/$(IMAGE_NAME).tar
	@echo "Loading image into root storage..."
	@sudo podman load -i /tmp/$(IMAGE_NAME).tar
	@rm -f /tmp/$(IMAGE_NAME).tar
	@echo "✓ Latest image loaded into root storage"
	@echo ""
	@echo "Step 2: Building bootable disk image..."
	@echo "Cleaning old output..."
	@sudo rm -rf $(QCOW2_OUTPUT)
	mkdir -p $(QCOW2_OUTPUT)
	sudo podman run --rm -it --privileged \
		--pull=newer \
		--security-opt label=type:unconfined_t \
		-v $(PWD)/$(QCOW2_OUTPUT):/output \
		-v /var/lib/containers/storage:/var/lib/containers/storage \
		registry.redhat.io/rhel9/bootc-image-builder:latest \
		--type qcow2 \
		localhost/$(IMAGE_NAME):$(IMAGE_TAG)
	@echo ""
	@echo "✓ qcow2 image built successfully!"
	@echo "  Output directory: $(QCOW2_OUTPUT)/"
	@ls -lh $(QCOW2_OUTPUT)/qcow2/disk.qcow2 || ls -lh $(QCOW2_OUTPUT)/

vm-create: ## Create and start KVM VM from qcow2 image
	@echo "Creating KVM VM: $(VM_NAME)"
	@# Copy the qcow2 to libvirt images directory
	@QCOW2_FILE=$$(find $(QCOW2_OUTPUT) -name "disk.qcow2" -o -name "*.qcow2" | head -1); \
	if [ -z "$$QCOW2_FILE" ]; then \
		echo ""; \
		echo "❌ Error: No qcow2 file found in $(QCOW2_OUTPUT)/"; \
		echo ""; \
		echo "Build the qcow2 first: make build-qcow2"; \
		echo ""; \
		exit 1; \
	fi; \
	echo "Found qcow2: $$QCOW2_FILE"; \
	sudo mkdir -p /var/lib/libvirt/images; \
	sudo cp "$$QCOW2_FILE" /var/lib/libvirt/images/$(VM_NAME).qcow2; \
	echo "Starting libvirtd..."; \
	sudo systemctl start libvirtd; \
	echo "Creating VM..."; \
	sudo virt-install \
		--name $(VM_NAME) \
		--memory $(VM_MEMORY) \
		--vcpus $(VM_CPUS) \
		--disk /var/lib/libvirt/images/$(VM_NAME).qcow2,bus=virtio \
		--import \
		--os-variant rhel9-unknown \
		--network network=default,model=virtio \
		--graphics none \
		--console pty,target_type=serial \
		--noautoconsole
	@echo ""
	@echo "✓ VM created and started!"
	@echo "  Name: $(VM_NAME)"
	@echo "  Memory: $(VM_MEMORY) MB"
	@echo "  CPUs: $(VM_CPUS)"
	@echo ""
	@echo "Connect to console: make vm-console"
	@echo "Check status: make vm-status"
	@echo "Get IP address: make vm-ip"

vm-start: ## Start the VM
	@echo "Starting VM: $(VM_NAME)"
	sudo virsh start $(VM_NAME)

vm-stop: ## Stop the VM
	@echo "Stopping VM: $(VM_NAME)"
	sudo virsh shutdown $(VM_NAME)

vm-status: ## Show VM status
	@echo "VM Status:"
	@sudo virsh list --all | grep $(VM_NAME) || echo "VM not found"
	@echo ""
	@echo "VM Info:"
	@sudo virsh dominfo $(VM_NAME) 2>/dev/null || echo "VM not running"

vm-console: ## Connect to VM serial console
	@echo "Connecting to VM console (Ctrl+] to exit)..."
	sudo virsh console $(VM_NAME)

vm-ip: ## Get VM IP address
	@echo "VM IP Address:"
	@sudo virsh domifaddr $(VM_NAME) || echo "Cannot determine IP (VM may not be running or DHCP not assigned yet)"

vm-test: ## Test VM services (run from host)
	@echo "Testing OpenDesk services in VM..."
	@VM_IP=$$(sudo virsh domifaddr $(VM_NAME) | grep -oP '(\d+\.){3}\d+' | head -1); \
	if [ -z "$$VM_IP" ]; then \
		echo "❌ Cannot determine VM IP address"; \
		exit 1; \
	fi; \
	echo "VM IP: $$VM_IP"; \
	echo ""; \
	echo "Testing Nextcloud (port 8080):"; \
	curl -I -m 5 http://$$VM_IP:8080 2>/dev/null && echo "✓ Nextcloud responding" || echo "✗ Nextcloud not reachable"; \
	echo ""; \
	echo "Open in browser:"; \
	echo "  Nextcloud: http://$$VM_IP:8080"; \
	echo ""; \
	echo "Note: PostgreSQL, Redis, and MinIO are internal services (not exposed to host)"

vm-clean: ## Destroy and remove VM
	@echo "Cleaning up VM: $(VM_NAME)"
	@read -p "This will destroy the VM and remove the disk. Continue? (yes/no): " confirm; \
	if [ "$$confirm" != "yes" ]; then \
		echo "Clean cancelled."; \
		exit 1; \
	fi
	-sudo virsh destroy $(VM_NAME)
	-sudo virsh undefine $(VM_NAME)
	-sudo rm -f /var/lib/libvirt/images/$(VM_NAME).qcow2
	@echo "✓ VM cleaned up"

setup-storage: ## Set up storage directories with SELinux contexts
	@echo "Setting up storage directories..."
	sudo bash bootc/setup-storage.sh

deploy: setup-storage ## Deploy OpenDesk (development/evaluation mode)
	@echo "Deploying OpenDesk in development mode..."
	sudo mkdir -p /etc/opendesk/manifests
	sudo mkdir -p /etc/containers/systemd
	sudo cp manifests-minimal/opendesk-minimal.yaml /etc/opendesk/manifests/
	sudo cp quadlets/opendesk-minimal.kube /etc/containers/systemd/
	sudo systemctl daemon-reload
	sudo systemctl start opendesk-minimal.service || true
	@# Note: Quadlets are automatically enabled by their presence in /etc/containers/systemd/
	@# No need to run 'systemctl enable' - the service will start on boot automatically
	@echo ""
	@echo "✓ OpenDesk deployed successfully!"
	@echo "  Access Nextcloud at: http://localhost:8080"
	@echo "  MinIO Console at: http://localhost:9001"
	@echo ""
	@echo "View status with: make status"
	@echo "View logs with: make logs"

deploy-prod: ## Deploy OpenDesk (production mode with external services)
	@echo "Deploying OpenDesk in production mode..."
	@echo ""
	@echo "⚠️  Before proceeding:"
	@echo "  1. Edit manifests-minimal/opendesk-minimal-production.yaml"
	@echo "  2. Replace all EXTERNAL_* placeholders with actual values"
	@echo "  3. Set up external PostgreSQL, Redis, and S3 services"
	@echo ""
	@read -p "Have you configured the production manifest? (yes/no): " confirm; \
	if [ "$$confirm" != "yes" ]; then \
		echo "Deployment cancelled. Please configure the manifest first."; \
		exit 1; \
	fi
	sudo mkdir -p /etc/opendesk/manifests /var/opendesk/nextcloud
	sudo cp manifests-minimal/opendesk-minimal-production.yaml /etc/opendesk/manifests/
	sudo cp quadlets/opendesk-minimal.kube /etc/containers/systemd/opendesk-production.kube
	sudo sed -i 's|opendesk-minimal|opendesk-production|g' /etc/containers/systemd/opendesk-production.kube
	sudo sed -i 's|opendesk-minimal.yaml|opendesk-minimal-production.yaml|' /etc/containers/systemd/opendesk-production.kube
	sudo chcon -R -t container_file_t /var/opendesk/nextcloud
	sudo chmod -R 755 /var/opendesk/nextcloud
	sudo systemctl daemon-reload
	sudo systemctl start opendesk-production.service || true
	@# Note: Quadlets are automatically enabled by their presence in /etc/containers/systemd/
	@echo ""
	@echo "✓ OpenDesk production deployment started!"

status: ## Show service status
	@echo "OpenDesk Service Status:"
	@echo "======================="
	@sudo systemctl status opendesk-minimal.service --no-pager || true
	@echo ""
	@echo "Pod Status:"
	@echo "==========="
	@podman pod ps || true
	@echo ""
	@echo "Container Status:"
	@echo "================"
	@podman ps -a --filter label=app=opendesk || true

logs: ## Show service logs (follow mode)
	@echo "Following OpenDesk logs (Ctrl+C to exit)..."
	sudo journalctl -u opendesk-minimal.service -f

logs-tail: ## Show last 100 lines of logs
	@echo "OpenDesk Logs (last 100 lines):"
	@echo "=============================="
	sudo journalctl -u opendesk-minimal.service -n 100 --no-pager

stop: ## Stop OpenDesk service
	@echo "Stopping OpenDesk..."
	sudo systemctl stop opendesk-minimal.service
	@echo "✓ OpenDesk stopped"

start: ## Start OpenDesk service
	@echo "Starting OpenDesk..."
	sudo systemctl start opendesk-minimal.service
	@echo "✓ OpenDesk started"

restart: ## Restart OpenDesk service
	@echo "Restarting OpenDesk..."
	sudo systemctl restart opendesk-minimal.service
	@echo "✓ OpenDesk restarted"

clean: ## Stop and remove OpenDesk deployment
	@echo "Cleaning up OpenDesk deployment..."
	@read -p "This will stop and remove the OpenDesk service. Continue? (yes/no): " confirm; \
	if [ "$$confirm" != "yes" ]; then \
		echo "Clean cancelled."; \
		exit 1; \
	fi
	-sudo systemctl stop opendesk-minimal.service
	-sudo rm /etc/containers/systemd/opendesk-minimal.kube
	-sudo rm -rf /etc/opendesk/
	sudo systemctl daemon-reload
	-podman pod rm -f opendesk-minimal
	@# Note: No need to 'disable' quadlet services - removing the .kube file disables them
	@echo ""
	@echo "✓ OpenDesk deployment cleaned"
	@echo "  Note: Data in /var/opendesk/ was preserved"
	@echo "  To remove data: sudo rm -rf /var/opendesk/"

clean-all: clean ## Remove everything including data
	@echo "Removing all data..."
	@read -p "⚠️  This will DELETE ALL DATA in /var/opendesk/. Continue? (yes/no): " confirm; \
	if [ "$$confirm" != "yes" ]; then \
		echo "Data removal cancelled."; \
		exit 1; \
	fi
	sudo rm -rf /var/opendesk/
	@echo "✓ All data removed"

backup: ## Create a backup of OpenDesk data
	@echo "Creating backup..."
	mkdir -p backups
	sudo tar -czf backups/opendesk-backup-$$(date +%Y%m%d-%H%M%S).tar.gz \
		/var/opendesk/ \
		/etc/opendesk/ \
		/etc/containers/systemd/opendesk-minimal.kube
	@echo "✓ Backup created in backups/"

update-images: build-nextcloud ## Pull latest container images and rebuild Nextcloud
	@echo "Pulling latest container images..."
	podman pull registry.redhat.io/rhel9/postgresql-15:latest
	podman pull registry.redhat.io/rhel9/redis-7:latest
	podman pull quay.io/minio/minio:latest
	@echo "✓ Images updated (Nextcloud UBI9 rebuilt, others pulled)"
	@echo ""
	@echo "Restart the service to use new images: make restart"

test: ## Run basic connectivity tests
	@echo "Running connectivity tests..."
	@echo ""
	@echo "Testing Nextcloud (HTTP):"
	@curl -I http://localhost:8080 || echo "✗ Nextcloud not reachable"
	@echo ""
	@echo "Testing MinIO Console:"
	@curl -I http://localhost:9001 || echo "✗ MinIO Console not reachable"
	@echo ""
	@echo "Testing PostgreSQL (from container):"
	@podman exec opendesk-minimal-postgresql psql -U opendesk -c "SELECT 1;" || echo "✗ PostgreSQL not accessible"
	@echo ""
	@echo "Testing Redis (from container):"
	@podman exec opendesk-minimal-redis redis-cli ping || echo "✗ Redis not accessible"

inspect: ## Inspect OpenDesk pod configuration
	@echo "OpenDesk Pod Inspection:"
	@echo "======================="
	@podman pod inspect opendesk-minimal 2>/dev/null || echo "Pod not running"
	@echo ""
	@echo "Container Inspection:"
	@echo "===================="
	@podman ps -a --filter label=app=opendesk --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

selinux-status: ## Check SELinux status and contexts
	@echo "SELinux Status:"
	@echo "=============="
	@echo "Mode: $$(getenforce)"
	@echo ""
	@echo "Storage Contexts:"
	@echo "================"
	@ls -ldZ /var/opendesk/* 2>/dev/null || echo "Storage not set up"
	@echo ""
	@echo "Recent denials:"
	@echo "==============="
	@sudo ausearch -m avc -ts recent 2>/dev/null | tail -5 || echo "No recent denials"
