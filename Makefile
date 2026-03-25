.PHONY: install uninstall update bootstrap-local status help

INSTALL_DIR   := /usr/local/bin
BOOTSTRAP_DIR := $(HOME)/.claude-vm

install: ## Install claude-run to /usr/local/bin and bootstrap script to ~/.claude-vm
	@echo "==> Installing claude-run to $(INSTALL_DIR)..."
	@chmod +x claude-run
	@sudo cp claude-run $(INSTALL_DIR)/claude-run
	@echo "==> Copying vm-bootstrap.sh to $(BOOTSTRAP_DIR)..."
	@mkdir -p $(BOOTSTRAP_DIR)
	@cp vm-bootstrap.sh $(BOOTSTRAP_DIR)/vm-bootstrap.sh
	@echo " ✓  Done. Run 'claude-run' from any project directory."

uninstall: ## Remove claude-run from /usr/local/bin
	@sudo rm -f $(INSTALL_DIR)/claude-run
	@echo " ✓  claude-run removed."
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
