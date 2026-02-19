# Development Containers

[![version-image]][release-url]
[![release-date-image]][release-url]
[![license-image]][license-url]

Docker containers specifically configured to provide fully featured development environments with GPU support.

- GitHub: [https://github.com/entelecheia/dev-containers][repo-url]

## Prerequisites

- Docker
- Docker Compose v2+
- NVIDIA Docker runtime (for GPU support)

## Quick Start

```bash
# Build the default image (ubuntu-22.04)
make docker-build

# Start the container
make docker-up

# Start in detached mode
make docker-up-detach

# Stop the container
make docker-down

# View the resolved configuration
make docker-config
```

## Variants

Two Dockerfile types serve all variants via `BUILD_FROM` parameterization:

| Variant | Base Image | Type | Features |
|---------|-----------|------|----------|
| `ubuntu-22.04` | `library/ubuntu:22.04` | ubuntu | Jupyter, SSH, Web, dotfiles, entrypoint |
| `ubuntu-20.04` | `library/ubuntu:20.04` | ubuntu | Jupyter, SSH, Web, dotfiles, entrypoint |
| `cuda-12.1.0-ubuntu22.04` | `nvidia/cuda:12.1.0-devel-ubuntu22.04` | cuda | SSH, GPU, 32GB shm |
| `cuda-12.8.0-ubuntu22.04` | `nvidia/cuda:12.8.0-devel-ubuntu22.04` | cuda | SSH, GPU, 32GB shm |

Specify a variant with `IMAGE_VARIANT`:

```bash
IMAGE_VARIANT=cuda-12.8.0-ubuntu22.04 make docker-build
IMAGE_VARIANT=cuda-12.8.0-ubuntu22.04 make docker-up-detach
```

### Adding a New Variant

Create a single file in `.docker/variants/`:

```bash
# .docker/variants/cuda-13.0.0-ubuntu24.04.env
BUILD_FROM="nvcr.io/nvidia/cuda:13.0.0-devel-ubuntu24.04"
VARIANT_TYPE="cuda"
```

That's it. No other files need to be created or modified.

## Projects

Projects provide per-deployment overrides (UID, GPU device, SSH port, workspace path). Configured in `.docker/.ids/`:

| Project | UID | GPU | SSH Port | Workspace |
|---------|-----|-----|----------|-----------|
| `default` | host UID | all | 2929 | `./workspace/default/` |
| `kmu` | 1111 | 7 | 2229 | `/raid/data/devcon/kmu/data` |
| `est` | 1111 | 5 | 3889 | `/raid/data/devcon/est/data` |
| `pulse9` | 1111 | 7 | 2332 | `./workspace/pulse9/data` |

Specify a project with `DOCKER_PROJECT_ID`:

```bash
IMAGE_VARIANT=cuda-12.1.0-ubuntu22.04 DOCKER_PROJECT_ID=kmu make docker-up-detach
IMAGE_VARIANT=cuda-12.8.0-ubuntu22.04 DOCKER_PROJECT_ID=pulse9 make docker-up-detach
```

### Adding a New Project

Create a file in `.docker/.ids/`:

```bash
# .docker/.ids/myproject.env
DOCKER_PROJECT_ID="myproject"
HOST_WORKSPACE_ROOT="/path/to/data"
CONTAINER_WORKSPACE_ROOT="/data"
CONTAINER_USERNAME="myuser"
USER_UID="1111"
USER_GID="1111"
DEVCON_HOST_SSH_PORT="2233"
DEVCON_CUDA_DEVICE_ID="0"
```

Set `HOST_SCRIPTS_DIR=""`, `HOST_SSH_DIR=""`, etc. to disable volume mounts not needed for the project.

## Configuration

### File Structure

```
.docker/
  Dockerfile.ubuntu              # Parameterized Ubuntu Dockerfile (ARG BUILD_FROM)
  Dockerfile.cuda                # Parameterized CUDA Dockerfile (ARG BUILD_FROM)
  docker-compose.ubuntu.yaml     # Ubuntu service (Jupyter+SSH+Web, 7 volumes)
  docker-compose.cuda.yaml       # CUDA service (SSH only, 1 volume, 32GB shm)
  docker.common.env              # All shared configuration
  docker.version                 # Semantic version
  variants/                      # Variant definitions (2-3 lines each)
    ubuntu-22.04.env
    cuda-12.8.0-ubuntu22.04.env
    ...
  .ids/                          # Project-specific overrides
    default.env
    kmu.env
    pulse9.env
    ...
  scripts/
    entrypoint.sh                # User/permission setup (Ubuntu only)
    launch.sh                    # Jupyter/SSH startup (Ubuntu only)
  .docker-scripts/
    docker-compose.sh            # Orchestration script
```

### Environment Loading Order

The `docker-compose.sh` script loads environment files in this order (later overrides earlier):

1. `.env.secret` — secrets (not committed)
2. `.env.docker` — global shared env (symlinked from `~/.local/share/dockerfiles/`)
3. `.docker/docker.version` — image version
4. `.docker/docker.common.env` — all defaults and shared config
5. `.docker/variants/<variant>.env` — `BUILD_FROM` and `VARIANT_TYPE`
6. `.docker/.ids/<project>.env` — project overrides (highest priority)

After loading, derived values (`IMAGE_TAG`, `IMAGE_NAME`, `CONTAINER_USER_UID`, `HOST_SSH_PORT`, etc.) are re-computed to reflect all overrides.

### Key Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `IMAGE_VARIANT` | `ubuntu-22.04` | Docker image variant |
| `DOCKER_PROJECT_ID` | `default` | Project identifier |
| `BUILD_FROM` | (from variant) | Base Docker image |
| `VARIANT_TYPE` | (from variant) | `ubuntu` or `cuda` |
| `DEVCON_CUDA_DEVICE_ID` | `all` | GPU device(s) to reserve |
| `DEVCON_HOST_SSH_PORT` | `2929` | Host SSH port mapping |
| `USER_UID` / `USER_GID` | host UID | Container user UID/GID |

## Testing

### Validate Configuration

```bash
# Check resolved config for a variant + project combination
IMAGE_VARIANT=ubuntu-22.04 make docker-config
IMAGE_VARIANT=cuda-12.1.0-ubuntu22.04 DOCKER_PROJECT_ID=kmu make docker-config
```

### Build and Run

```bash
# Build and start
IMAGE_VARIANT=cuda-12.1.0-ubuntu22.04 DOCKER_PROJECT_ID=kmu make docker-build
IMAGE_VARIANT=cuda-12.1.0-ubuntu22.04 DOCKER_PROJECT_ID=kmu make docker-up-detach

# Verify container
docker ps --filter "name=devcon-kmu"
docker exec devcon-kmu-workspace-1 nvidia-smi

# Stop
IMAGE_VARIANT=cuda-12.1.0-ubuntu22.04 DOCKER_PROJECT_ID=kmu make docker-down
```

### SSH Access

```bash
ssh -p 2229 kmu@localhost   # kmu project
ssh -p 2332 dev@localhost   # pulse9 project
ssh -p 2929 dev@localhost   # default project
```

## CI/CD

- **`deploy-image.yaml`** — Matrix-based workflow that builds and pushes Docker images to GHCR. Triggered on `docker*` branch pushes or via `workflow_dispatch`.
- **`release.yaml`** — Semantic release workflow using UV and `python-semantic-release`.

## Troubleshooting

- Ensure Docker Compose v2+ is installed (`docker compose version`).
- Ensure NVIDIA Container Toolkit is installed for GPU variants.
- Run `make docker-config` to inspect the fully resolved configuration.
- Check `docker logs devcon-<project>-workspace-1` for container startup issues.

## Changelog

See the [CHANGELOG] for more information.

## Contributing

Contributions are welcome! Please see the [contributing guidelines] for more information.

## License

This project is released under the [MIT License][license-url].

<!-- Links: -->
[license-image]: https://img.shields.io/github/license/entelecheia/dev-containers
[license-url]: https://github.com/entelecheia/dev-containers/blob/main/LICENSE
[version-image]: https://img.shields.io/github/v/release/entelecheia/dev-containers?sort=semver
[release-date-image]: https://img.shields.io/github/release-date/entelecheia/dev-containers
[release-url]: https://github.com/entelecheia/dev-containers/releases
[repo-url]: https://github.com/entelecheia/dev-containers
[changelog]: https://github.com/entelecheia/dev-containers/blob/main/CHANGELOG.md
[contributing guidelines]: https://github.com/entelecheia/dev-containers/blob/main/CONTRIBUTING.md
<!-- Links: -->
