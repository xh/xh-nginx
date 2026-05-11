# Changelog

Note that the `next` and `next-brotli` tags are mutable and are rebuilt regularly with any updates
to this project and on a weekly schedule (to pick up ongoing updates to the upstream `nginx` and
`fholzer/nginx-brotli` source images).

Versioned builds are immutable and have locked in a given set of defaults from this project as well
as the latest nginx version at the time of the build (recorded in the log entries below).

The `*-brotli` tags publish a variant built on `fholzer/nginx-brotli` to enable Brotli compression
alongside gzip. Prior to the unification on `develop`, this variant lived on its own `brotli` branch
with a separate `1.x-brotli` version line — see entries below.

## next - under development

* nginx `1.30` (latest 1.30 patch at build time)

## 3.0.0 / latest + 3.0.0-brotli / latest-brotli - 2026-05-11

* nginx `1.30.0` (both variants).
* First release on the unified version line. The brotli variant is now built from `develop` alongside the default
  image; both share this xh-nginx version.
* Updated cache control header value for `$expires` var to `no-cache, no-store, must-revalidate` when serving HTML
  content (notably `index.html` app entry-points). Behavior should be same as prior use of `epoch`, although potentially
  more reliable with this syntax.
* Raised `gzip_comp_level` from 2 to 4, for enhanced compression of larger JSON payloads.

### 💥 Breaking Changes
* The brotli variant is no longer published from a separate `brotli` branch with its own `1.x-brotli` version line. The
  brotli image is now built from `develop` alongside the default image and shares the unified xh-nginx version. Apps
  pulling `1.1.0-brotli` should switch to `3.0.0-brotli` (or stay on `latest-brotli`, which now floats to the unified
  release line). Legacy `1.x-brotli` tags remain on Docker Hub but will no longer be updated.
* Released images are now pinned to a specific upstream nginx patch (`1.30.0` for 3.0.0) instead of tracking
  `nginx:latest`. Apps that want floating-latest behavior should switch from `latest` to `next`.

## 1.1.0-brotli / latest-brotli - 2026-05-07

* nginx `1.30.0`
* Final release on the legacy `1.x-brotli` line. Superseded by `3.0.0-brotli`.

## 2.4.0 / latest - 2024-10-14

* nginx `1.27.2`
* Set `client_max_body_size 100m` - match increased cap on client POST sizes from `xh-tomcat`.

## 1.0.0-brotli - 2024-10-14

* Initial versioned release of the Brotli-enabled image.
* nginx `1.26.2`

## 2.3.0 - 2023-06-16

* nginx `1.24.0`
* Remove install of dnsutils, procps, and vim. These packages increased the size of the image and can introduce security
  vulnerabilities, and it is unclear if they were ever useful in an interactive shell session. Please let XH know if you
  were relying on these for any purpose.

## 2.2.0 - 2023-05-23

* nginx `1.23.4`

## v2.1.0 - 2022-01-14

* Ensure UTF8 charset spec'd in header, including for CSS files.
  See [xh-nginx/9](https://github.com/xh/xh-nginx/issues/9) - intermittent rendering issue with
  icons.
* nginx `1.21.5`

## v2.0.0

* Generate and pass through to proxied calls a `Jespa-Connection-Id` header, based on the source IP
  address. This is required for apps using the Jespa library for NTLMv2 SSO to properly track
  per-client state across a multistep auth handshake.
* Increase proxy timeouts to five minutes to support longer-running calls to back-end APIs.
* Increase `client_max_body_size` to `20m` to support larger POSTs, notably big grid exports.
* Add basic useragent parsing to set `$is_mobile` and `$is_desktop` variables for use within
  app-level directives (e.g. redirecting from / to the correct platform-specific entry URI).
* Set `proxy_cookie_path` directive to `Secure` but also allow cross-site access.
* nginx `1.21.0`

## v1.0.0

* Initial versioned release of the base image.
* nginx `1.19.5`
