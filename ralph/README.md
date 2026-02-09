## Dockerfiles

- `Dockerfile.dotnet` remains the .NET image and includes the required certificate install RUN block.
- `Dockerfile.template` is a generalized template: supply `BASE_IMAGE` (e.g., `python:3.11-slim`, `node:20-bullseye`, `mcr.microsoft.com/dotnet/sdk:8.0`). The RUN block is identical to `Dockerfile.dotnet` for certificate install and OpenCode/bootstrap steps.

Example builds:

```bash
# .NET (default)

# Custom base image using the template
docker build -f ralph/Dockerfile.template --build-arg BASE_IMAGE=python:3.11-slim -t ralph-python .
docker build -f ralph/Dockerfile.template --build-arg BASE_IMAGE=node:20-bullseye -t ralph-node .
```
