.PHONY: install uninstall update help

INSTALL_DIR   := /usr/local/bin
BOOTSTRAP_DIR := $(HOME)/.claude-vm

install: ## Install claude-docker to /usr/local/bin
	@echo "==> Installing claude-docker to $(INSTALL_DIR)..."
	@chmod +x claude-docker
	@sudo cp claude-docker $(INSTALL_DIR)/claude-docker
	@echo "==> Copying support files to $(BOOTSTRAP_DIR)..."
	@mkdir -p $(BOOTSTRAP_DIR)
	@cp Dockerfile.claude $(BOOTSTRAP_DIR)/Dockerfile.claude
	@echo " ✓  Done. Run 'claude-docker' from any project directory."

uninstall: ## Remove claude-docker from /usr/local/bin
	@sudo rm -f $(INSTALL_DIR)/claude-docker
	@echo " ✓  claude-docker removed."

update: ## Re-install after pulling latest changes
	@$(MAKE) install
	@echo " ✓  claude-docker updated."

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' Makefile \
	  | awk 'BEGIN {FS = ":.*##"}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
