FROM nginx:latest

ENV XH_NGINX_CONFIG_PATH=/etc/nginx/conf.d
ENV XH_NGINX_CONFIG_INCL_PATH=/etc/nginx/includes
ENV XH_NGINX_CONTENT_PATH=/usr/share/nginx/html

# Install some useful basic utilities
RUN apt-get update && apt-get install -y nano vim procps htop dnsutils

# Clear out default nginx config and welcome page
RUN rm $XH_NGINX_CONFIG_PATH/default.conf && rm $XH_NGINX_CONTENT_PATH/*

# Copy in custom config / partials
COPY xh.conf $XH_NGINX_CONFIG_PATH/
COPY includes $XH_NGINX_CONFIG_INCL_PATH/
