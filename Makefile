.PHONY: install uninstall update bootstrap-local status help

INSTALL_DIR   := /usr/local/bin
BOOTSTRAP_DIR := $(HOME)/.claude-vm

install: ## Install claude-run and claude-docker to /usr/local/bin
	@echo "==> Installing claude-run to $(INSTALL_DIR)..."
	@chmod +x claude-run
	@sudo cp claude-run $(INSTALL_DIR)/claude-run
	@echo "==> Installing claude-docker to $(INSTALL_DIR)..."
	@chmod +x claude-docker
	@sudo cp claude-docker $(INSTALL_DIR)/claude-docker
	@echo "==> Copying support files to $(BOOTSTRAP_DIR)..."
	@mkdir -p $(BOOTSTRAP_DIR)
	@cp vm-bootstrap.sh $(BOOTSTRAP_DIR)/vm-bootstrap.sh
	@cp Dockerfile.claude $(BOOTSTRAP_DIR)/Dockerfile.claude
	@echo " ✓  Done. Run 'claude-run' or 'claude-docker' from any project directory."

uninstall: ## Remove claude-run and claude-docker from /usr/local/bin
	@sudo rm -f $(INSTALL_DIR)/claude-run
	@sudo rm -f $(INSTALL_DIR)/claude-docker
	@echo " ✓  claude-run and claude-docker removed."
	@echo "    VM still exists. To fully remove it:"
	@echo "    multipass delete claude-sandbox --purge"

update: ## Re-install after pulling latest changes
	@$(MAKE) install
	@echo " ✓  claude-run updated."

bootstrap-local: ## Update the local bootstrap script cache
	@mkdir -p $(BOOTSTRAP_DIR)
	@cp vm-bootstrap.sh $(BOOTSTRAP_DIR)/vm-bootstrap.sh
	@echo " ✓  Bootstrap script updated at $(BOOTSTRAP_DIR)/vm-bootstrap.sh"

status: ## Show VM status (requires claude-run to be installed)
	@claude-run status

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' Makefile \
	  | awk 'BEGIN {FS = ":.*##"}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
