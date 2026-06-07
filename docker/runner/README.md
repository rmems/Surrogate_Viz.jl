# Docker GPU Self-Hosted GitHub Actions Runner

This directory provides a containerized, GPU-enabled self-hosted runner for the `cuda-visuals` job in `.github/workflows/julia.yml`.

**Why Docker?**
- Reproducible environment with exact Julia 1.12 + CUDA toolkit.
- Easy GPU passthrough via NVIDIA Container Toolkit.
- Isolation from host (avoids polluting the dev machine with runner artifacts).
- Matches the requirements for sm_120 (RTX 5080 / Blackwell) jobs.

**Grok Build 0.1 model**: This setup was created to help the local hosted runner (Surrogate-Viz-sm120-GPU) reliably pick up and execute the Julia CUDA visual kernel tests and optional plot regeneration.

## Prerequisites (on the host)

1. NVIDIA drivers installed and working (`nvidia-smi` succeeds).
2. [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) installed and configured (enables `--gpus all` / `deploy.resources.devices`).
3. Docker and Docker Compose.
4. A GitHub token:
   - Preferred: Fine-grained Personal Access Token (PAT) scoped to this repository with **Actions: Read and write** (for self-hosted runners) + **Contents: Read**.
   - Or a short-lived registration token from the repo's Actions > Runners page.

## Quick Start

```bash
cd docker/runner

# 1. Copy and edit secrets
cp runner.env.example runner.env
# Edit runner.env and put your GITHUB_TOKEN

# 2. Build the image
docker compose build

# 3. Start the runner (detached)
docker compose up -d

# 4. Watch logs
docker compose logs -f

# To stop
docker compose down
```

The container will:
- Register (or re-register with `--replace`) using the token and the labels `self-hosted,gpu,sm120,julia-cuda`.
- Start listening for jobs.

## Manual `docker run` (alternative to compose)

```bash
docker build -t surrogate-viz-gpu-runner .

docker run -d --name surrogate-viz-sm120-gpu \
  --gpus all \
  -e GITHUB_URL=https://github.com/rmems/Surrogate_Viz.jl \
  -e RUNNER_NAME=Surrogate-Viz-sm120-GPU-docker \
  -e RUNNER_LABELS=self-hosted,gpu,sm120,julia-cuda \
  --env-file runner.env \
  surrogate-viz-gpu-runner
```

## Verifying It Works

1. In GitHub UI, go to **Actions** tab for this repo.
2. Look for a "Julia CI" run (triggered by push to your feature branch or the PR).
3. The `cuda-visuals` job should be assigned to your runner (it will show the container name or "Surrogate-Viz-sm120-GPU-docker" in the job log header).
4. Inside the job logs you should see:
   - `CUDA.jl version info:`
   - Device name with `cap=8.9` or `sm_120` equivalent.
   - The synthetic kernel test passing.
   - (Optional) the plot regeneration step.

## Labels

The runner registers with exactly these labels (must match the `runs-on` in the workflow):
`self-hosted,gpu,sm120,julia-cuda`

If you change the name or labels, update both the env vars and the workflow if necessary.

## Security Notes (Grok Build 0.1 model)

- The original workflow already has the `if: github.event.pull_request.head.repo.full_name == github.repository` guard.
- Never commit real tokens. Use `runner.env` (gitignored) or Docker secrets / env injection.
- The container runs as a non-root `runner` user.
- Consider mounting a read-only secrets volume only if needed for other tools inside jobs.

## Troubleshooting

- **No GPU inside container**: Ensure NVIDIA Container Toolkit is installed and `docker run --gpus all nvidia/cuda:12.8.1-base-ubuntu22.04 nvidia-smi` works on the host.
- **Runner stays idle**: Check `docker compose logs`, ensure labels match, restart the container (`docker compose restart`), and look at the job in the Actions UI (it may be "queued" waiting for a matching runner).
- **Julia/CUDA not found**: The image pre-installs Julia 1.12 and uses the CUDA devel toolkit. `Pkg.instantiate()` inside jobs will pull `CUDA.jl`.
- **Permission issues**: The entrypoint runs config as the `runner` user. Rebuild if you change the Dockerfile.

## Stopping / Updating

```bash
docker compose down
# edit files
docker compose build
docker compose up -d
```

For a full re-registration, delete the `.runner` file inside the container (or use `--replace` which the entrypoint already does on every start if token is provided).

## Related

- Workflow: `.github/workflows/julia.yml` (cuda-visuals job)
- Original manual setup was in `~/actions-runner` (still usable in parallel).
- All changes follow the "Grok Build 0.1 model" practices used throughout this PR (citations, minimal changes, security-first if-guards, pure Julia CUDA, etc.).

This should finally let your local hosted runner pick up and successfully run the GPU jobs.
