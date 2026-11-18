# Hoist Dockerfile: xh-nginx

[Hoist React](https://github.com/xh/hoist-react/) apps can be deployed via Docker containers running Tomcat (for Hoist's
Grails based back-end) and nginx (to serve compiled client JS/CSS and other assets).

This repo contains a minimal Dockerfile to build the base nginx container, which can be used by app-specific Docker
deployments with additional configurations. A `-brotli` variant is also published, built on `fholzer/nginx-brotli` to
enable Brotli compression alongside gzip.

## nginx version, variants, and Docker tags

Images are published to Docker Hub as [`xhio/xh-nginx`](https://hub.docker.com/r/xhio/xh-nginx), producing the variants
below.

| Variant        | Base image                            | Docker tag(s)                          |
|----------------|---------------------------------------|----------------------------------------|
| next           | `nginx:<major.minor>`                 | `next`                                 |
| next-brotli    | `fholzer/nginx-brotli:v<major.minor>` | `next-brotli`                          |
| release        | `nginx:<pinned>`                      | `latest`, `<xh-release>`               |
| release-brotli | `fholzer/nginx-brotli:v<pinned>`      | `latest-brotli`, `<xh-release>-brotli` |

The pinned nginx version is the `NGINX_VERSION` default at the top of the [`Dockerfile`](./Dockerfile). It is the
only place to bump nginx. `next` builds use its major.minor. [`CHANGELOG.md`](./CHANGELOG.md) records the nginx version
in each release.

`next` / `next-brotli` tags are fully mutable. Every variant is rebuilt on every commit to `develop` and on a weekly schedule
(Wednesday ~20:00 ET) so they pick up upstream patches to the floating major.minor base image tags. They are intended
for testing and snapshot-style deployments.

`release` / `release-brotli` builds publish two tags per variant: an immutable tag (the xh-nginx semver release
recorded in `CHANGELOG.md`), and a mutable `latest` (or `latest-brotli`) tag that floats to the most recent release of
that variant. Docker Hub enforces the immutable tags: any tag matching `^[0-9]+\.[0-9]+\.[0-9]+(-brotli)?$` cannot be
overwritten or deleted.

Every published image carries an SBOM (the packages it contains) and build provenance (its exact base image and build
inputs) as attestations. Docker Scout reads these, and anyone can view them:

```sh
docker buildx imagetools inspect xhio/xh-nginx:latest --format '{{json .SBOM}}'
docker buildx imagetools inspect xhio/xh-nginx:latest --format '{{json .Provenance}}'
```

## Support policy

- Only the most recent release gets updates. Older release tags stay on Docker Hub but are not patched.
- We cut a new release promptly when nginx ships a security fix on the line we track, or when the upstream base
  images fix critical or high CVEs. Each release records its nginx version in [`CHANGELOG.md`](./CHANGELOG.md).
- For production, use `latest` / `latest-brotli`, or pin an exact release tag and move to each new release as it ships.
  A pinned tag never changes, so it never picks up security fixes on its own.
- `next` / `next-brotli` are for testing only.
- Tags from before the 3.x line (`2.x`, `v`-prefixed, `brotli`, and `1.x-brotli`) are unsupported and will not be
  updated.

## Branches and CI

This repo uses a single `develop` branch (and a `master` branch tracking the most recent release). Both variants build
from `develop` via a single [`Dockerfile`](./Dockerfile) with one build target per variant, and share the unified
xh-nginx version and docker tag version. To build locally:

```sh
docker build -t xh-nginx-local .                                  # standard (default target)
docker build --target brotli -t xh-nginx-local:brotli .           # brotli
docker build --build-arg NGINX_VERSION=1.31 -t xh-nginx-local .   # float on a major.minor, as `next` does
```

GitHub Actions workflows live in [`.github/workflows/`](./.github/workflows):

- **`buildNext.yml`** - runs on every push to `develop`, on a weekly schedule, and on manual dispatch. Builds and
  pushes both `next` variants in parallel via a matrix, on the major.minor of the pinned nginx version.
- **`buildRelease.yml`** - manual dispatch from `master` only. Takes a semver release version as input. Builds and
  pushes the `release` variants on the pinned nginx version, then creates the corresponding git tag and GitHub release.
  To release with a newer nginx patch, bump `NGINX_VERSION` in the `Dockerfile` and update `CHANGELOG.md` in a normal
  PR before dispatching the workflow.
- **`checkNginx.yml`** - runs daily and on manual dispatch, via [`check-nginx.sh`](./.github/scripts/check-nginx.sh).
  When both base images publish a newer nginx patch on the pinned line, it opens a PR to `develop` that bumps
  `NGINX_VERSION` and adds a `CHANGELOG.md` line. PRs come from the org's XH Build Bot GitHub App. A manual run with
  "dry run" checked logs what would happen and confirms the bot can push, without changing anything. It opens an issue when a newer nginx major.minor line is available,
  and another when `develop` has gone 45 days without a commit. GitHub disables scheduled workflows in public repos
  after 60 days without activity, so that issue is the cue to merge something before `next` stops rebuilding.

----

📫☎️🌎 info@xh.io | <https://xh.io/contact>

Copyright © 2026 Extremely Heavy Industries Inc.
