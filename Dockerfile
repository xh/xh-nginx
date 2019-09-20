FROM nginx

# Top-level config file, defaulted to the one shipped by the official nginx image. That default
# config will include all sub-configs in $XH_NGINX_CONFIG_PATH. Apps can use this default file and
# copy their own app-specific partial configs into $XH_NGINX_CONFIG_PATH (most common), or they can
# replace it completely for more control (e.g. to switch between different configs at runtime).
# NOTE - apps that do replace should ensure they continue to import $XH_NGINX_CONFIG_PATH/xh.conf.
ENV XH_NGINX_CONFIG_FILE=/etc/nginx/nginx.conf

# Path to host app-specific configs + our general xh.conf. All configs copied in here are included
# by the standard $XH_NGINX_CONFIG_FILE (above) or could be selectively included by a custom file.
ENV XH_NGINX_CONFIG_PATH=/etc/nginx/conf.d

# Path to host include partials.
ENV XH_NGINX_CONFIG_INCL_PATH=/etc/nginx/includes

# Path to host the static JS/CSS/HTML content itself, copied from the client-side build.
ENV XH_NGINX_CONTENT_PATH=/usr/share/nginx/html

# Install some useful basic utilities
RUN apt-get update && apt-get install -y nano vim procps htop dnsutils

# Clear out default nginx config and welcome page
RUN rm $XH_NGINX_CONFIG_PATH/default.conf && rm $XH_NGINX_CONTENT_PATH/*

# Copy in custom config / partials
COPY xh.conf $XH_NGINX_CONFIG_PATH/
COPY includes $XH_NGINX_CONFIG_INCL_PATH/

# Custom run command to point nginx at our $XH_NGINX_CONFIG_FILE variable for its config file.
# Note this is run in a shell to ensure the environment variable is expanded at runtime.
CMD ["sh", "-c", "nginx -g 'daemon off;' -c $XH_NGINX_CONFIG_FILE"]
