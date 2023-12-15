FROM httpd:2.4-bookworm as apache-base

# /usr/local/apache2 is the base dir for Apache2 in this image

# Remove default config
RUN sed -i '/^DocumentRoot/d' /usr/local/apache2/conf/httpd.conf

# Make it easier for us to configure our extras
RUN mkdir -p "$HTTPD_PREFIX/conf/optional" \
    && mkdir -p "$HTTPD_PREFIX/conf/mods" \
    && echo 'IncludeOptional conf/mods/*.conf' >> "$HTTPD_PREFIX/conf/httpd.conf" \
    && echo 'IncludeOptional conf/optional/*.conf' >> "$HTTPD_PREFIX/conf/httpd.conf" \
    && echo 'IncludeOptional conf/sites/*.conf' >> "$HTTPD_PREFIX/conf/httpd.conf"

# Enable apache mods
RUN echo 'LoadModule rewrite_module modules/mod_rewrite.so' >> "$HTTPD_PREFIX/conf/mods/rewrite.conf" \
    && echo 'LoadModule headers_module modules/mod_headers.so' >> "$HTTPD_PREFIX/conf/mods/headers.conf" \
    && echo 'LoadModule remoteip_module modules/mod_remoteip.so' >> "$HTTPD_PREFIX/conf/mods/remoteip.conf" \
    && echo 'LoadModule expires_module modules/mod_expires.so' >> "$HTTPD_PREFIX/conf/mods/expires.conf" \
    && echo 'LoadModule proxy_module modules/mod_proxy.so' >> "$HTTPD_PREFIX/conf/mods/proxy.conf" \
    && echo 'LoadModule proxy_fcgi_module modules/mod_proxy_fcgi.so' >> "$HTTPD_PREFIX/conf/mods/proxy_fcgi.conf"

RUN groupadd -g 11002 developers

# Add extra conf for apache
# @TODO fix apachelogging PHP params into PHP image
RUN mkdir -p /var/log/apache2/ && chown www-data:www-data /var/log/apache2/
COPY apachelogging.conf /usr/local/apache2/conf/optional/logging.conf
COPY apachecaching.conf /usr/local/apache2/conf/optional/caching.conf
COPY apacheremoteip.conf /usr/local/apache2/conf/optional/remoteip.conf

# Make sure we use %a in our logformat lines, it'll get the client IP instead of reverse proxy because we are using remoteip
RUN sed -i '/LogFormat/s/%h/%a/' /usr/local/apache2/conf/httpd.conf \
    # Ensure we pickup the provided hostname in logs instead of ip:80 from the config \
    # @TODO check if the below line is doing anything \
    && sed -i '/LogFormat/s/%v:%p/%V/' /usr/local/apache2/conf/httpd.conf

# Switch to port 8080 as default so we don't need to run as root (make sure VirtualHost lines set this to 8080 too then)
RUN sed -i 's/Listen 80$/Listen 8080/' /usr/local/apache2/conf/httpd.conf

# Make sure when running as www-data things work
RUN chown www-data:www-data -R /usr/local/apache2/logs/

# Copy our config over
COPY 1-app.conf /usr/local/apache2/conf/sites/

USER www-data