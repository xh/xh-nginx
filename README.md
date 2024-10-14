# Hoist Dockerfile: xh-nginx

This branch of the `xh-nginx` project is based on an alternate nginx image - `fholzer/nginx-brotli` - to enable the 
use of the Brotli compression algorithm. Due to the alternate base image, this branch maintains its own set of tags
and versioning, separate from the main `xh-nginx` project.

## Nginx version and Docker tags

| Branch | nginx Version | Docker Tag(s)                   |
|--------|:-------------:|---------------------------------|
| brotli |    1.26.2     | `1.0.0-brotli`, `latest-brotli` |

This image is
[available on Docker Hub](https://hub.docker.com/r/xhio/xh-nginx/).

----

📫☎️🌎 info@xh.io | <https://xh.io/contact>

Copyright © 2024 Extremely Heavy Industries Inc.
