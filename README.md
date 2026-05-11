# Hoist Dockerfile: xh-nginx

[Hoist React](https://github.com/xh/hoist-react/) apps can be deployed via Docker containers running Tomcat (for Hoist's
Grails based back-end) and nginx (to serve compiled client JS/CSS and other assets).

This repo contains a minimal Dockerfile to build the base nginx container, which can be used by app-specific Docker
deployments with additional configurations. A `-brotli` variant is also published, built on `fholzer/nginx-brotli` to
enable Brotli compression alongside gzip.

## nginx version, variants, and Docker tags

Images are published to Docker Hub as [`xhio/xh-nginx`](https://hub.docker.com/r/xhio/xh-nginx), producing the variants
below. In the table and prose, `<nginx-patch>` is the pinned upstream nginx patch version and `<xh-release>` is the
xh-nginx semver release from `CHANGELOG.md`.

| Variant        | Base image                            | Docker tag(s)                          |
|----------------|---------------------------------------|----------------------------------------|
| next           | `nginx:1.30`                          | `next`                                 |
| next-brotli    | `fholzer/nginx-brotli:v1.30`          | `next-brotli`                          |
| release        | `nginx:<nginx-patch>`                 | `latest`, `<xh-release>`               |
| release-brotli | `fholzer/nginx-brotli:v<nginx-patch>` | `latest-brotli`, `<xh-release>-brotli` |

`next` / `next-brotli` tags are fully mutable. Both are rebuilt on every commit to `develop` and on a weekly schedule
(Wednesday ~20:00 ET) so they pick up upstream patches to the floating major.minor base image tags. They are intended
for testing and snapshot-style deployments.

`release` / `release-brotli` builds publish two tags per variant: an immutable `<xh-release><suffix>` tag pinned to a
specific xh-nginx semver release (recorded in `CHANGELOG.md`) and a mutable `latest<suffix>` tag that floats to the most
recent release of that variant.

## Branches and CI

This repo uses a single `develop` branch (and a `master` branch tracking the most recent release). The brotli variant
previously lived on its own `brotli` branch with a separate `1.x-brotli` version line; that branch was merged into
`develop` for the `3.0.0` release. Both variants now build from `develop` via dedicated Dockerfiles
([`Dockerfile`](./Dockerfile) and [`Dockerfile-brotli`](./Dockerfile-brotli)) and share the unified xh-nginx version.

GitHub Actions workflows live in [`.github/workflows/`](./.github/workflows):

- **`buildNext.yml`** — runs on every push to `develop`, on a weekly schedule, and on manual dispatch. Builds and
  pushes both `next` variants in parallel via a matrix.
- **`buildRelease.yml`** — manual dispatch from `master` only. Takes a semver release version as input. The locked
  nginx patch version is pinned in the workflow's build matrix (with the [`Dockerfile`](./Dockerfile) and
  [`Dockerfile-brotli`](./Dockerfile-brotli) `NGINX_VERSION` ARG defaults kept in sync for local builds). Builds and
  pushes the `release` variants with both `latest<suffix>` and `<xh-release><suffix>` tags, then creates the
  corresponding git tag and GitHub release. To release with a newer nginx patch, bump the matrix entries (and the
  Dockerfile defaults) and update `CHANGELOG.md` in a normal PR before dispatching the workflow.

----

📫☎️🌎 info@xh.io | <https://xh.io/contact>

Copyright © 2026 Extremely Heavy Industries Inc.
