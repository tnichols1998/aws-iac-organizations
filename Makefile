# AWS IAC Organizations - Generalized Multi-Environment Deployment
# Usage: make deploy ENV=dev ORG_CONFIG=example TARGET=localstack

# Default values
ENV ?= dev
TARGET ?= aws  
ORG_CONFIG ?= example
AWS_PROFILE ?= 
LOCALSTACK_ENDPOINT ?= http://localhost:4566
VAULT ?= AWS
USE_1PASSWORD ?= true

# Colors for output
COLOR_GREEN = \033[0;32m
COLOR_YELLOW = \033[0;33m
COLOR_RED = \033[0;31m
COLOR_RESET = \033[0m

.PHONY: help validate plan deploy destroy clean test localstack-start localstack-stop setup-env

help: ## Show this help message
	@echo "$(COLOR_GREEN)AWS IAC Organizations - Multi-Environment Deployment$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_YELLOW)Usage:$(COLOR_RESET)"
	@echo "  make deploy ENV=dev ORG_CONFIG=example TARGET=localstack"
	@echo "  make deploy ENV=prod ORG_CONFIG=my-org TARGET=aws AWS_PROFILE=my-profile"
	@echo ""
	@echo "$(COLOR_YELLOW)Available commands:$(COLOR_RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(COLOR_GREEN)%-20s$(COLOR_RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(COLOR_YELLOW)Variables:$(COLOR_RESET)"
	@echo "  ENV        - Environment (dev, qa, prod) [default: dev]"
	@echo "  TARGET     - Deployment target (aws, localstack) [default: aws]"  
	@echo "  ORG_CONFIG - Organization config name [default: example]"
	@echo "  AWS_PROFILE - AWS profile to use (for TARGET=aws)"
	@echo "  VAULT      - 1Password vault name [default: AWS]"
	@echo "  USE_1PASSWORD - Use 1Password for credentials (true/false) [default: true]"

validate: ## Validate organization configuration
	@echo "$(COLOR_YELLOW)Validating configuration: $(ORG_CONFIG)$(COLOR_RESET)"
	@python3 scripts/validate-config.py config/organizations/$(ORG_CONFIG).yaml
	@echo "$(COLOR_GREEN)✓ Configuration validated successfully$(COLOR_RESET)"

plan: validate ## Plan deployment changes
	@echo "$(COLOR_YELLOW)Planning deployment for $(ENV) environment using $(ORG_CONFIG) config$(COLOR_RESET)"
	@cd environments/$(ENV) && \
		$(call set_terraform_vars) \
		tofu init -backend-config="backend-$(ENV).conf" && \
		tofu plan -var="organization_config=../../config/organizations/$(ORG_CONFIG).yaml"

deploy: validate ## Deploy infrastructure  
	@echo "$(COLOR_YELLOW)Deploying to $(ENV) environment using $(ORG_CONFIG) config$(COLOR_RESET)"
	@cd environments/$(ENV) && \
		$(call set_terraform_vars) \
		tofu init -backend-config="backend-$(ENV).conf" && \
		tofu plan -var="organization_config=../../config/organizations/$(ORG_CONFIG).yaml" && \
		tofu apply -var="organization_config=../../config/organizations/$(ORG_CONFIG).yaml" -auto-approve
	@echo "$(COLOR_GREEN)✓ Deployment completed successfully$(COLOR_RESET)"

destroy: ## Destroy infrastructure
	@echo "$(COLOR_RED)WARNING: This will destroy all resources for $(ENV) environment$(COLOR_RESET)"
	@read -p "Are you sure? (y/N): " confirm && [ "$$confirm" = "y" ]
	@cd environments/$(ENV) && \
		$(call set_terraform_vars) \
		tofu destroy -var="organization_config=../../config/organizations/$(ORG_CONFIG).yaml" -auto-approve

clean: ## Clean terraform state and cache
	@echo "$(COLOR_YELLOW)Cleaning terraform cache for $(ENV)$(COLOR_RESET)"
	@cd environments/$(ENV) && rm -rf .terraform terraform.tfstate* .terraform.lock.hcl

test: ## Run tests for configuration
	@echo "$(COLOR_YELLOW)Running tests for $(ORG_CONFIG)$(COLOR_RESET)"
	@python3 -m pytest tests/ -v --org-config=$(ORG_CONFIG) --env=$(ENV)

# LocalStack specific targets
localstack-start: ## Start LocalStack for development
	@echo "$(COLOR_YELLOW)Starting LocalStack...$(COLOR_RESET)"
	@scripts/localstack-setup.sh start
	@echo "$(COLOR_GREEN)✓ LocalStack started$(COLOR_RESET)"

localstack-stop: ## Stop LocalStack
	@echo "$(COLOR_YELLOW)Stopping LocalStack...$(COLOR_RESET)"
	@scripts/localstack-setup.sh stop

localstack-inspect: ## Inspect LocalStack resources
	@echo "$(COLOR_YELLOW)Inspecting LocalStack resources...$(COLOR_RESET)"
	@scripts/localstack-setup.sh inspect

# Environment setup
setup-dev: ## Setup development environment
	@echo "$(COLOR_YELLOW)Setting up development environment...$(COLOR_RESET)"
	@pip install -r requirements-dev.txt
	@pre-commit install
	@echo "$(COLOR_GREEN)✓ Development environment ready$(COLOR_RESET)"

setup-env: ## Set up environment with 1Password credentials (usage: make setup-env ENV=qa ORG_CONFIG=my-org)
	@echo "$(COLOR_YELLOW)Setting up environment credentials...$(COLOR_RESET)"
	@echo "Run the following command to load credentials:"
	if [ "$(ENV)" = "dev" ] && [ "$(TARGET)" != "aws" ]; then \
		echo "$(COLOR_GREEN)source scripts/aws-env.sh $(ENV) $(ORG_CONFIG)$(COLOR_RESET)"; \
	else \
		echo "$(COLOR_GREEN)source scripts/aws-env.sh $(ENV) $(ORG_CONFIG) --vault $(VAULT)$(COLOR_RESET)"; \
	fi

load-env: ## Load environment credentials in current shell (must be sourced)
	ifeq ($(USE_1PASSWORD),true)
		$(call load_1password_env)
	else
		$(call set_terraform_vars)
	endif

# Configuration management  
list-configs: ## List available organization configurations
	@echo "$(COLOR_YELLOW)Available organization configurations:$(COLOR_RESET)"
	@ls -1 config/organizations/*.yaml | sed 's/config\/organizations\///g' | sed 's/\.yaml//g' | sed 's/^/  - /'

copy-config: ## Copy example config (usage: make copy-config NEW_CONFIG=my-org)
ifndef NEW_CONFIG
	@echo "$(COLOR_RED)Error: NEW_CONFIG parameter required$(COLOR_RESET)"
	@echo "Usage: make copy-config NEW_CONFIG=my-org"
	@exit 1
endif
	@cp config/organizations/example.yaml config/organizations/$(NEW_CONFIG).yaml
	@echo "$(COLOR_GREEN)✓ Configuration copied to $(NEW_CONFIG).yaml$(COLOR_RESET)"

# Import existing resources
import: ## Import existing AWS resources
ifndef RESOURCE_TYPE
	@echo "$(COLOR_RED)Error: RESOURCE_TYPE parameter required$(COLOR_RESET)"
	@exit 1
endif
ifndef RESOURCE_ID  
	@echo "$(COLOR_RED)Error: RESOURCE_ID parameter required$(COLOR_RESET)"
	@exit 1
endif
	@cd environments/$(ENV) && \
		$(call set_terraform_vars) \
		tofu import $(RESOURCE_TYPE).$(RESOURCE_ID) $(RESOURCE_ID)

# Helper function to set terraform variables based on target
define set_terraform_vars
	export TF_VAR_organization_config="../../config/organizations/$(ORG_CONFIG).yaml"; \
	export TF_VAR_environment="$(ENV)"; \
	if [ "$(TARGET)" = "localstack" ]; then \
		export AWS_ENDPOINT_URL="$(LOCALSTACK_ENDPOINT)"; \
		export AWS_ACCESS_KEY_ID="test"; \
		export AWS_SECRET_ACCESS_KEY="test"; \
		export TF_VAR_localstack_endpoint="$(LOCALSTACK_ENDPOINT)"; \
	elif [ "$(TARGET)" = "aws" ] && [ -n "$(AWS_PROFILE)" ]; then \
		export AWS_PROFILE="$(AWS_PROFILE)"; \
	fi;
endef

# Helper function to load 1Password credentials
define load_1password_env
	if [ "$(ENV)" = "dev" ] && [ "$(TARGET)" != "aws" ]; then \
		source scripts/aws-env.sh $(ENV) $(ORG_CONFIG) --target localstack; \
	else \
		source scripts/aws-env.sh $(ENV) $(ORG_CONFIG) --vault $(VAULT); \
	fi;
endef

# Generate terraform vars from YAML config
generate-tfvars: ## Generate terraform.tfvars from YAML config
	@echo "$(COLOR_YELLOW)Generating terraform vars for $(ORG_CONFIG)$(COLOR_RESET)"  
	@python3 scripts/yaml-to-tfvars.py config/organizations/$(ORG_CONFIG).yaml > config/organizations/$(ORG_CONFIG).tfvars
	@echo "$(COLOR_GREEN)✓ Generated $(ORG_CONFIG).tfvars$(COLOR_RESET)"

# Environment-specific commands
plan-qa: ## Plan deployment for QA environment
	@make plan ENV=qa ORG_CONFIG=petunka-holdings

plan-prod: ## Plan deployment for production environment  
	@make plan ENV=prod ORG_CONFIG=petunka-holdings

deploy-qa: ## Deploy to QA environment
	@make deploy ENV=qa ORG_CONFIG=petunka-holdings

deploy-prod: ## Deploy to production environment
	@make deploy ENV=prod ORG_CONFIG=petunka-holdings

# Show email templating preview
preview-emails: ## Preview how emails will be templated for each environment
	@echo "$(COLOR_YELLOW)Email templating preview:$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_GREEN)QA Environment:$(COLOR_RESET)"
	@echo "  aws-root+qa@petunkaholdings.com"
	@echo "  aws-root+qa-marketing@petunkaholdings.com"
	@echo "  aws-root+qa-img@petunkaholdings.com"
	@echo "  aws-root+qa@sixfigurecoachsecrets.com"
	@echo ""
	@echo "$(COLOR_GREEN)Production Environment:$(COLOR_RESET)"
	@echo "  aws-root+prod@petunkaholdings.com"
	@echo "  aws-root+prod-marketing@petunkaholdings.com" 
	@echo "  aws-root+prod-img@petunkaholdings.com"
	@echo "  aws-root+prod@sixfigurecoachsecrets.com"
