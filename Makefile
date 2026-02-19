# To do stuff with make, you type `make` in a directory that has a file called
# "Makefile".  You can also type `make -f <makefile>` to use a different filename.
#
# A Makefile is a collection of rules. Each rule is a recipe to do a specific
# thing, sort of like a grunt task or an npm package.json script.
#
# A rule looks like this:
#
# <target>: <prerequisites...>
# 	<commands>
#
# The "target" is required. The prerequisites are optional, and the commands
# are also optional, but you have to have one or the other.
#
# Type `make` to show the available targets and a description of each.
#
.DEFAULT_GOAL := help
.PHONY: help
help:  ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Utilities

large-files: ## show the 20 largest files in the repo
	@find . -printf '%s %p\n'| sort -nr | head -20

disk-usage: ## show the disk usage of the repo
	@du -h -d 2 .

git-sizer: ## run git-sizer
	@git-sizer --verbose

gc-prune: ## garbage collect and prune
	@git gc --prune=now

##@ Setup

install-pipx: ## install pipx (pre-requisite for external tools)
	@command -v pipx &> /dev/null || pip install --user pipx || true

install-uv: ## install uv package manager
	@command -v uv &> /dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh || true

install-node: ## install node
	@export NVM_DIR="$${HOME}/.nvm"; \
	[ -s "$${NVM_DIR}/nvm.sh" ] && . "$${NVM_DIR}/nvm.sh"; \
	nvm install --lts

nvm-ls: ## list node versions
	@export NVM_DIR="$${HOME}/.nvm"; \
	[ -s "$${NVM_DIR}/nvm.sh" ] && . "$${NVM_DIR}/nvm.sh"; \
	nvm ls

set-default-node: ## set default node
	@export NVM_DIR="$${HOME}/.nvm"; \
	[ -s "$${NVM_DIR}/nvm.sh" ] && . "$${NVM_DIR}/nvm.sh"; \
	nvm alias default node

install-commitizen: install-pipx ## install commitizen (pre-requisite for commit)
	@command -v cz &> /dev/null || pipx install commitizen || true

install-precommit: install-pipx ## install pre-commit
	@command -v pre-commit &> /dev/null || pipx install pre-commit || true

install-precommit-hooks: install-precommit ## install pre-commit hooks
	@pre-commit install

initialize: install-uv install-pipx install-commitizen install-precommit ## initialize the project environment
	@pre-commit install

##@ Dependencies

install: ## install dependencies (production only)
	@uv sync --no-dev

install-dev: ## install dependencies (including dev)
	@uv sync

update: ## update all dependencies
	@uv lock --upgrade

lock: ## lock dependencies without upgrading
	@uv lock

##@ Release

version: ## print current version
	@uv run semantic-release print-version --current

next-version: ## print next version
	@uv run semantic-release print-version --next

changelog: ## print changelog for current version
	@uv run semantic-release changelog --released

next-changelog: ## print changelog for next version
	@uv run semantic-release changelog --unreleased

release-noop: ## dry-run of the release process
	@uv run semantic-release publish --noop -v DEBUG

release-ci: ## run the release process in CI
	@uv run semantic-release publish -v DEBUG -D commit_author='github-actions <action@github.com>'

prerelease-noop: ## dry-run of the prerelease process
	@uv run semantic-release publish --noop -v DEBUG --prerelease

##@ Docker

symlink-global-docker-env: ## symlink global docker env file for local development
	@DOCKERFILES_SHARE_DIR="$HOME/.local/share/dockerfiles" \
	DOCKER_GLOBAL_ENV_FILENAME=".env.docker" \
	DOCKER_GLOBAL_ENV_FILE="$${DOCKERFILES_SHARE_DIR}/$${DOCKER_GLOBAL_ENV_FILENAME}" \
	[ -f "$${DOCKER_GLOBAL_ENV_FILE}" ] && ln -sf "$${DOCKER_GLOBAL_ENV_FILE}" .env.docker || echo "Global docker env file not found"

docker-login: ## login to docker
	@bash .docker/.docker-scripts/docker-compose.sh login

docker-build: ## build the docker app image
	@IMAGE_VARIANT=$${IMAGE_VARIANT:-"ubuntu-22.04"} \
	DOCKER_PROJECT_ID=$${DOCKER_PROJECT_ID:-"default"} \
	bash .docker/.docker-scripts/docker-compose.sh build

docker-config: ## show the docker app config
	@IMAGE_VARIANT=$${IMAGE_VARIANT:-"ubuntu-22.04"} \
	DOCKER_PROJECT_ID=$${DOCKER_PROJECT_ID:-"default"} \
	bash .docker/.docker-scripts/docker-compose.sh config

docker-push: ## push the docker app image
	@IMAGE_VARIANT=$${IMAGE_VARIANT:-"ubuntu-22.04"} \
	DOCKER_PROJECT_ID=$${DOCKER_PROJECT_ID:-"default"} \
	bash .docker/.docker-scripts/docker-compose.sh push

docker-run: ## run the docker base image
	@IMAGE_VARIANT=$${IMAGE_VARIANT:-"ubuntu-22.04"} \
	DOCKER_PROJECT_ID=$${DOCKER_PROJECT_ID:-"default"} \
	bash .docker/.docker-scripts/docker-compose.sh run

docker-up: ## launch the docker app image
	@IMAGE_VARIANT=$${IMAGE_VARIANT:-"ubuntu-22.04"} \
	DOCKER_PROJECT_ID=$${DOCKER_PROJECT_ID:-"default"} \
	bash .docker/.docker-scripts/docker-compose.sh up

docker-up-detach: ## launch the docker app image in detached mode
	@IMAGE_VARIANT=$${IMAGE_VARIANT:-"ubuntu-22.04"} \
	DOCKER_PROJECT_ID=$${DOCKER_PROJECT_ID:-"default"} \
	bash .docker/.docker-scripts/docker-compose.sh up --detach
