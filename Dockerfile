FROM fholzer/nginx-brotli:v1.26.2

# Path to host app-specific configs + our general xh.conf. All configs copied in here are included
# by the standard $XH_NGINX_CONFIG_FILE (above) or could be selectively included by a custom file.
ENV XH_NGINX_CONFIG_PATH=/etc/nginx/conf.d

# Path to host include partials.
ENV XH_NGINX_CONFIG_INCL_PATH=/etc/nginx/includes

# Path to host the static JS/CSS/HTML content itself, copied from the client-side build.
ENV XH_NGINX_CONTENT_PATH=/usr/share/nginx/html

# Clear out default nginx config and welcome page
RUN rm $XH_NGINX_CONFIG_PATH/default.conf && rm $XH_NGINX_CONTENT_PATH/*

# Copy in overridden nginx.conf, xh.conf, and includes.
COPY nginx.conf xh.conf $XH_NGINX_CONFIG_PATH/
COPY includes $XH_NGINX_CONFIG_INCL_PATH/
