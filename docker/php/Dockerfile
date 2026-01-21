# Многостадийная сборка для оптимизации
FROM php:8.3-fpm-alpine AS builder

# Устанавливаем системные зависимости
RUN apk add --no-cache \
    git \
    curl \
    libzip-dev \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    icu-dev \
    oniguruma-dev \
    postgresql-dev \
    libxml2-dev \
    libxslt-dev \
    unzip \
    openssl-dev \
    g++ \
    make \
    autoconf

# Устанавливаем расширения PHP
RUN docker-php-ext-configure gd --with-freetype --with-jpeg && \
    docker-php-ext-configure intl && \
    docker-php-ext-install \
        pdo_mysql \
        pdo_pgsql \
        mysqli \
        zip \
        gd \
        intl \
        mbstring \
        exif \
        pcntl \
        bcmath \
        soap \
        sockets \
        opcache \
        xsl

# Устанавливаем Redis и другие PECL расширения
RUN pecl install redis && \
    pecl install apcu && \
    pecl install igbinary && \
    docker-php-ext-enable redis apcu igbinary

# Устанавливаем Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Финальный образ
FROM php:8.3-fpm-alpine

# Копируем установленные расширения из builder
COPY --from=builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/
COPY --from=builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/

# Устанавливаем системные зависимости для продакшена
RUN apk add --no-cache \
    libzip \
    libpng \
    libjpeg-turbo \
    freetype \
    icu \
    oniguruma \
    postgresql-libs \
    libxml2 \
    libxslt \
    tzdata \
    supervisor

# Настройка PHP-FPM для высоких нагрузок
RUN echo "pm = dynamic" >> /usr/local/etc/php-fpm.d/zz-docker.conf && \
    echo "pm.max_children = 50" >> /usr/local/etc/php-fpm.d/zz-docker.conf && \
    echo "pm.start_servers = 5" >> /usr/local/etc/php-fpm.d/zz-docker.conf && \
    echo "pm.min_spare_servers = 5" >> /usr/local/etc/php-fpm.d/zz-docker.conf && \
    echo "pm.max_spare_servers = 35" >> /usr/local/etc/php-fpm.d/zz-docker.conf && \
    echo "pm.max_requests = 500" >> /usr/local/etc/php-fpm.d/zz-docker.conf

# Создаем пользователя приложения
RUN addgroup -g 1000 www && \
    adduser -u 1000 -G www -s /bin/sh -D www

# Настраиваем права
RUN mkdir -p /var/www/html && \
    chown -R www:www /var/www && \
    chmod -R 755 /var/www

# Копируем конфигурационные файлы
COPY php.ini /usr/local/etc/php/php.ini
COPY opcache.ini /usr/local/etc/php/conf.d/opcache.ini

# Переключаемся на пользователя приложения
USER www

# Рабочая директория
WORKDIR /var/www/html

# Открываем порт PHP-FPM
EXPOSE 9000

# Запускаем PHP-FPM
CMD ["php-fpm", "-F"]