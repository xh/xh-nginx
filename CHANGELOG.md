# Changelog

Note that the `next` tag is mutable and is rebuilt regularly with any updates to this project and 
on a weekly schedule (to pick up ongoing updates to the official `nginx:latest` source image).

Versioned builds are immutable and have locked in a given set of defaults from this project as well
as the latest nginx version at the time of the build (recorded in the log entries below).

## next - under development

* nginx `latest` (version dependent on build time)

## v2.2.0 / latest - 2023-05-23

* nginx `v1.23.4`

## v2.1.0 - 2022-01-14

* Ensure UTF8 charset spec'd in header, including for CSS files.
  See [xh-nginx/9](https://github.com/xh/xh-nginx/issues/9) - intermittent rendering issue with
  icons.
* nginx `v1.21.5`

## v2.0.0

* Generate and pass through to proxied calls a `Jespa-Connection-Id` header, based on the source IP
  address. This is required for apps using the Jespa library for NTLMv2 SSO to properly track
  per-client state across a multistep auth handshake.
* Increase proxy timeouts to five minutes to support longer-running calls to back-end APIs.
* Increase `client_max_body_size` to `20m` to support larger POSTs, notably big grid exports.
* Add basic useragent parsing to set `$is_mobile` and `$is_desktop` variables for use within
  app-level directives (e.g. redirecting from / to the correct platform-specific entry URI).
* Set `proxy_cookie_path` directive to `Secure` but also allow cross-site access.
* nginx `v1.21.0`

## v1.0.0

* Initial versioned release of the base image.
* nginx `v1.19.5`
