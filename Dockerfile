# fetch the Composer image, image page: <https://hub.docker.com/_/composer>
FROM composer:2.3.5 as composer

# build application backend-api, image page: <https://hub.docker.com/_/php>
FROM php:8.1.3-fpm-alpine3.15 as backend-laravel-api

# install composer, image page: <https://hub.docker.com/_/composer>
COPY --from=composer /usr/bin/composer /usr/bin/composer

ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_HOME=/composer

ENV TZ="Europe/Rome"

ARG SUPERCRONIC="https://github.com/aptible/supercronic/releases/download/v0.2.1/supercronic-linux-amd64"

# create unprivileged user
RUN mkdir -p /tmp/appuser \
    && adduser --disabled-password --shell "/sbin/nologin" --home "/tmp/appuser" --no-create-home --uid "10001" --gecos "" "appuser" \
    # install necessary alpine packages
    && apk update && apk add --no-cache \
    nginx \
    git \
    openssh \
    tzdata \
    curl \
    zip \
    unzip \
    supervisor \
    libpng-dev \
    libpq-dev \
    libwebp-dev \
    libzip-dev \
    freetype-dev \
    $PHPIZE_DEPS \
    libjpeg-turbo-dev \
    # libmcrypt-dev \
    # compile native PHP packages
    && docker-php-ext-install \
    -j$(nproc) gd \
    exif \
    sockets \
    pcntl \
    bcmath \
    mysqli \
    pdo_mysql \
    pgsql \
    pdo_pgsql \
    # install supercronic (for laravel task scheduling), project page: <https://github.com/aptible/supercronic>
    && wget -q ${SUPERCRONIC} \
    -O /usr/bin/supercronic \
    && chmod +x /usr/bin/supercronic \
    && mkdir /etc/supercronic \
    && echo '' > /etc/supercronic/laravel


# configure packages
RUN docker-php-ext-configure gd --with-jpeg --with-freetype --with-webp \
    # install additional packages from PECL
    && pecl install zip && docker-php-ext-enable zip \
    # && pecl install mcrypt-1.0.4 && docker-php-ext-enable mcrypt \
    && pecl install igbinary && docker-php-ext-enable igbinary \
    && yes | pecl install redis && docker-php-ext-enable redis

#RUN apk add --update npm nodejs 

# copy nginx configuration
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/default.conf /etc/nginx/conf.d/default.conf

## Configure PHP-FPM
COPY config/php-fpm.conf /etc/php8/php-fpm.d/www.conf
COPY config/php.ini /usr/local/etc/php/conf.d/custom.ini

# copy supervisor configuration
COPY config/supervisord.conf /etc/supervisord.conf

# TODO start
# BEFORE composer install, use image composer to install into api the laravel project
# docker compose run composer create-project --prefer-dist laravel/laravel
# TODO end

# install application dependencies
WORKDIR /var/www/html

COPY ./api/composer.json ./api/composer.lock* ./

RUN composer install --no-scripts --no-autoloader --ansi --no-interaction \
    && composer dump-autoload --no-scripts --no-dev --optimize

# install composer dependencies
RUN chown -R appuser:appuser /tmp/appuser \
    && chown -R appuser:appuser /run \
    && chown -R appuser:appuser /var/lib/nginx \
    && chown -R appuser:appuser /var/log/nginx \
    # Update memory limit
    && echo -en '\n\n' >> /usr/local/etc/php/conf.d/custom.ini \
    && echo 'memory_limit=-1' >> /usr/local/etc/php/conf.d/custom.ini \
    && echo 'max_execution_time=-1' >> /usr/local/etc/php/conf.d/custom.ini

# use an unprivileged user by default
USER appuser

EXPOSE 8080

# run supervisor and nginx
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisord.conf"]