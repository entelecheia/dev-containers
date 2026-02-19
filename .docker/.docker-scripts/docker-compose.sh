#!/bin/bash
# Docker compose orchestration script
USAGE="
$0 COMMAND [OPTIONS]

Arguments:
COMMAND                The operation to be performed. Must be one of: [build|config|push|login|up|down|run]

Options:
-v, --variant IMAGE_VARIANT     Specify a variant for the Docker image.
-p, --pid PROJECT_ID            Specify a project ID for the container instance.
-r, --run RUN_COMMAND           Specify a command to run when using the 'run' command. Default: bash
-h, --help                      Display this help message.

Additional arguments can be provided after the options, and they will be passed directly to the Docker Compose command.

Example:
$0 build -v ubuntu-22.04
"

# declare arguments
PROJECT_ID=${DOCKER_PROJECT_ID:-"default"}
COMMAND="build"
VARIANT=${IMAGE_VARIANT:-"ubuntu-22.04"}
RUN_COMMAND="bash"
ADDITIONAL_ARGS=()

set +u
# first argument is the command
COMMAND="$1"
shift

# parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
    -v | --variant)     VARIANT="$2"; shift ;;
    --variant=*)        VARIANT="${1#*=}" ;;
    -p | --pid)         PROJECT_ID="$2"; shift ;;
    --pid=*)            PROJECT_ID="${1#*=}" ;;
    -r | --run)         RUN_COMMAND="$2"; shift ;;
    --run=*)            RUN_COMMAND="${1#*=}" ;;
    -h | --help | -h*)  echo "Usage: $0 $USAGE" >&2; exit 0 ;;
    *)                  ADDITIONAL_ARGS+=("$1") ;;
    esac
    shift
done
set -u

# validate command
case "${COMMAND}" in
    build|config|push|login|up|down|run)
        echo "${COMMAND^}ing docker for variant: ${VARIANT}, project: ${PROJECT_ID}"
        ;;
    *)
        echo "Invalid command: $COMMAND" >&2
        echo "Usage: $0 $USAGE" >&2
        exit 1
        ;;
esac
echo "---"

# Export host user UID/GID so containers match host permissions
# Named projects (.ids/*.env) can override these if needed
export USER_UID=${USER_UID:-$(id -u)}
export USER_GID=${USER_GID:-$(id -g)}

# --- Load environment variables (order matters: later sources override earlier) ---
set -a

# 1. Secret environment variables
DOCKER_SECRET_ENV_FILENAME=${DOCKER_SECRET_ENV_FILENAME:-".env.secret"}
if [ -e "${DOCKER_SECRET_ENV_FILENAME}" ]; then
    echo "Loading secret env from ${DOCKER_SECRET_ENV_FILENAME}"
    # shellcheck disable=SC1091,SC1090
    source "${DOCKER_SECRET_ENV_FILENAME}"
fi

# 2. Global docker environment (shared across repos)
DOCKER_GLOBAL_ENV_FILENAME=${DOCKER_GLOBAL_ENV_FILENAME:-".env.docker"}
if [ -e "${DOCKER_GLOBAL_ENV_FILENAME}" ]; then
    echo "Loading global env from ${DOCKER_GLOBAL_ENV_FILENAME}"
    # shellcheck disable=SC1091,SC1090
    source "${DOCKER_GLOBAL_ENV_FILENAME}"
fi

# 3. Version file
# shellcheck disable=SC1091
source .docker/docker.version
IMAGE_VARIANT="${VARIANT}"

# 4. Common configuration (sets defaults for all variables)
if [ -e .docker/docker.common.env ]; then
    echo "Loading common env from .docker/docker.common.env"
    # shellcheck disable=SC1091
    source .docker/docker.common.env
fi

# 5. Variant-specific configuration (BUILD_FROM, VARIANT_TYPE)
VARIANT_ENV_FILE=".docker/variants/${VARIANT}.env"
if [ -e "${VARIANT_ENV_FILE}" ]; then
    echo "Loading variant env from ${VARIANT_ENV_FILE}"
    # shellcheck disable=SC1091,SC1090
    source "${VARIANT_ENV_FILE}"
else
    echo "Warning: variant env file not found: ${VARIANT_ENV_FILE}" >&2
fi

# 6. Project-specific overrides (loaded LAST for highest priority)
PROJECT_ID_ENV_FILE=".docker/.ids/${PROJECT_ID}.env"
if [ -e "${PROJECT_ID_ENV_FILE}" ]; then
    echo "Loading project env from ${PROJECT_ID_ENV_FILE}"
    # shellcheck disable=SC1091,SC1090
    source "${PROJECT_ID_ENV_FILE}"
fi

# Re-compute derived values after all overrides
# Project env may override USER_UID/USER_GID, DEVCON_* variables
CONTAINER_USER_UID=${USER_UID:-"9001"}
CONTAINER_USER_GID=${USER_GID:-"9001"}
CONTAINER_CUDA_DEVICE_ID=${DEVCON_CUDA_DEVICE_ID:-${CONTAINER_CUDA_DEVICE_ID:-"all"}}
HOST_SSH_PORT=${DEVCON_HOST_SSH_PORT:-${HOST_SSH_PORT:-"2929"}}
HOST_JUPYTER_PORT=${DEVCON_HOST_JUPYTER_PORT:-${HOST_JUPYTER_PORT:-"18998"}}
CONTAINER_JUPYTER_TOKEN=${DEVCON_JUPYTER_TOKEN:-${CONTAINER_JUPYTER_TOKEN:-"__juypter_token_(change_me)__"}}
HOST_WEB_SVC_PORT=${DEVCON_HOST_WEB_SVC_PORT:-${HOST_WEB_SVC_PORT:-"19090"}}
IMAGE_VARIANT="${VARIANT}"
IMAGE_TAG="${IMAGE_VERSION}-${IMAGE_VARIANT}"
IMAGE_NAME="${CONTAINER_REGISTRY}/${DOCKER_USERNAME}/${DOCKER_PROJECT_NAME}"
CONTAINER_PROJECT_NAME="${DOCKER_PROJECT_NAME}-${DOCKER_PROJECT_ID}"
CONTAINER_HOSTNAME="${DOCKER_PROJECT_NAME}-${DOCKER_PROJECT_ID}"

set +a

# --- Prepare docker network ---
CONTAINER_NETWORK_NAME=${CONTAINER_NETWORK_NAME:-""}
if [[ -n "${CONTAINER_NETWORK_NAME}" ]] && ! docker network ls | grep -q "${CONTAINER_NETWORK_NAME}"; then
    echo "Creating network ${CONTAINER_NETWORK_NAME}"
    docker network create "${CONTAINER_NETWORK_NAME}"
else
    echo "Network ${CONTAINER_NETWORK_NAME} already exists."
fi

# --- Prepare local workspace directories ---
echo "Preparing local workspace directories"
for dir in HOST_WORKSPACE_ROOT HOST_SSH_DIR HOST_CACHE_DIR HOST_HF_HOME HOST_GH_CONFIG_DIR HOST_PASSAGE_DIR; do
    val="${!dir:-}"
    [ -n "$val" ] && [ ! -d "$val" ] && mkdir -p "$val"
done
# Copy scripts if directory doesn't exist yet
HOST_SCRIPTS_DIR="${HOST_SCRIPTS_DIR:-}"
[ -n "${HOST_SCRIPTS_DIR}" ] && [ ! -d "${HOST_SCRIPTS_DIR}" ] && cp -r "$PWD/.docker/scripts" "${HOST_SCRIPTS_DIR}"

# --- Determine compose file from VARIANT_TYPE ---
VARIANT_TYPE=${VARIANT_TYPE:-"ubuntu"}
COMPOSE_FILE=".docker/docker-compose.${VARIANT_TYPE}.yaml"

# --- Execute docker compose command ---
if [ "${COMMAND}" == "push" ]; then
    docker push "${CONTAINER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
elif [ "${COMMAND}" == "login" ]; then
    echo "GITHUB_CR_PAT: $GITHUB_CR_PAT"
    docker login ghcr.io -u "$GITHUB_USERNAME"
elif [ "${COMMAND}" == "run" ]; then
    docker compose --project-directory . \
        -f "${COMPOSE_FILE}" \
        run workspace "${RUN_COMMAND}" "${ADDITIONAL_ARGS[@]}"
else
    docker compose --project-directory . \
        -f "${COMPOSE_FILE}" \
        -p "${CONTAINER_PROJECT_NAME}" \
        "${COMMAND}" "${ADDITIONAL_ARGS[@]}"
fi
