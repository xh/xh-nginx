FROM nginx:latest

# Default top-level config file (from official nginx image) - will include all sub-configs in $XH_NGINX_CONFIG_PATH.
ENV XH_NGINX_CONFIG_FILE=/etc/nginx/nginx.conf
# Directory to host app-specific configs, as well as our general xh.conf, and have them included by default.
ENV XH_NGINX_CONFIG_PATH=/etc/nginx/conf.d
# Directory to host include partials.
ENV XH_NGINX_CONFIG_INCL_PATH=/etc/nginx/includes
# Directory to host the static JS/CSS/HTML content itself, copied from the client-side build.
ENV XH_NGINX_CONTENT_PATH=/usr/share/nginx/html

# Install some useful basic utilities
RUN apt-get update && apt-get install -y nano vim procps htop dnsutils

# Clear out default nginx config and welcome page
RUN rm $XH_NGINX_CONFIG_PATH/default.conf && rm $XH_NGINX_CONTENT_PATH/*

# Copy in custom config / partials
COPY xh.conf $XH_NGINX_CONFIG_PATH/
COPY includes $XH_NGINX_CONFIG_INCL_PATH/
