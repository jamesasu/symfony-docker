FROM php:8.2-fpm-bookworm as php-base

# Set default env vars that we can override in a running image
ENV APP_ENV=dev
# Set NODE_MAJOR to latest LTS version
ENV NODE_MAJOR=18

# Install NodeJS REPO
ADD nodesource.gpg /etc/apt/keyrings/nodesource.gpg
RUN echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" > /etc/apt/sources.list.d/nodesource.list

# Install required packages for PHP/Node etc
# default-mysql-client needed for DB upgrade scripts
# libjpeg62-turbo # Needed for wkhtmltopdf
# xfonts-base, xfonts-75dpi # needed for wkhtmltopdf
RUN apt-get update && apt-get install -y --no-install-recommends \
        busybox-static \
        default-mysql-client \
        git \
        gsfonts \
        libcurl4-openssl-dev \
        libfreetype6-dev \
        libjpeg-dev \
        libjpeg62-turbo \
        libmagickwand-dev \
        libpng-dev \
        libxml2 \
        libxml2-dev \
        libzip-dev \
        msmtp \
        msmtp-mta \
        nodejs \
        unzip \
        wget \
        xfonts-75dpi \
        xfonts-base \
        zlib1g-dev \
        && rm -rf /var/lib/apt/lists/*

# Install required PHP modules
RUN docker-php-ext-install pdo pdo_mysql zip bcmath intl soap curl bcmath
RUN docker-php-ext-configure pdo_mysql  \
    && docker-php-ext-enable pdo_mysql  \
    && docker-php-ext-configure zip \
    && docker-php-ext-configure gd --with-freetype --with-jpeg

RUN docker-php-ext-install -j$(nproc) gd
# Uopz needed for CI, but our Composer requires it so we need it here, but disable it anyway
RUN pecl install imagick uopz && docker-php-ext-enable imagick uopz

# Install wkhtmltopdf binary
RUN cd /tmp && \
    wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_amd64.deb \
    && dpkg -i ./wkhtmltox_0.12.6.1-3.bookworm_amd64.deb \
    && rm /tmp/wkhtmltox_0.12.6.1-3.bookworm_amd64.deb

# Install composer from upstream image
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Install Symfony CLI:
RUN curl -1sLf 'https://dl.cloudsmith.io/public/symfony/stable/setup.deb.sh' | bash \
    && apt install symfony-cli

# Use the default production configuration
RUN cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" && cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php-cli.ini"

RUN echo 'memory_limit = 1024M ' >> "$PHP_INI_DIR/php-cli.ini" \
    && echo 'memory_limit = 512M' >> "$PHP_INI_DIR/php.ini" \
    && echo 'upload_max_filesize = 50M' >> "$PHP_INI_DIR/php.ini" \
    && echo 'post_max_size = 52M' >> "$PHP_INI_DIR/php.ini" \
    && echo 'max_execution_time = 120' >>  "$PHP_INI_DIR/php.ini" \
    && echo 'date.timezone = Australia/Brisbane' >> $PHP_INI_DIR/conf.d/timezone.ini \
    && echo 'session.use_strict_mode=On' >> $PHP_INI_DIR/conf.d/session.ini \
    && echo 'session.sid_bits_per_character = 6' >> $PHP_INI_DIR/conf.d/session.ini \
    && echo 'session.cookie_httponly=On' >> $PHP_INI_DIR/conf.d/session.ini \
    && echo 'session.cookie_secure=On' >> $PHP_INI_DIR/conf.d/session.ini \
    && echo 'session.cookie_samesite=Strict' >> $PHP_INI_DIR/conf.d/session.ini \
    && echo 'session.save_path=/var/lib/php/sessions' >> $PHP_INI_DIR/conf.d/session.ini \
    # Set PHP session cleanup to 4 hours, this will log you out after 4 hours of inactivity \
    && echo 'session.gc_maxlifetime = 14400'  >>  "$PHP_INI_DIR/php.ini" \
    && mkdir -p /var/lib/php/sessions \
    && chown www-data:www-data /var/lib/php/sessions \
    && chmod 700 /var/lib/php/sessions


# Disable uopz as it's only needed for CI Test
RUN echo 'uopz.disable = 1' >> $PHP_INI_DIR/conf.d/disable_uopz.ini  \
    && echo 'uopz.exit = 1' >> $PHP_INI_DIR/conf.d/disable_uopz.ini

RUN groupadd -g 11002 developers
RUN mkdir -p var/sessions \
    && mkdir -p var/logs  \
    && mkdir -p var/cache \
    && chmod -R 777 var

# @TODO add this to startup script as well? Or at least creating the file?
RUN mkdir /var/log/app \
    && touch /var/log/app/app.json.log \
    && chown www-data /var/log/app/app.json.log

# Ensure npm and composer have the right directories in www-data homedir for what is needed
RUN mkdir /var/www/.composer \
    && mkdir /var/www/.npm \
    && chown www-data:www-data -R /var/www

# Setup MSMTP for cron
COPY msmtprc /etc/msmtprc
COPY aliases /etc/aliases
RUN chmod 644 /etc/msmtprc
RUN touch /var/log/app/msmtp.log && chown -R www-data /var/log/app/msmtp.log

# Setup dir for crontabs
RUN mkdir -p /var/spool/cron/crontabs

WORKDIR /var/www/app

# Trust all docker proxies
ENV TRUSTED_PROXIES=172.16.0.0/12

# Run as a safe user instead of root
USER www-data
