# Многоступенчатая сборка для уменьшения итогового размера образа
# Этап 1: Сборка зависимостей и компиляция расширений
FROM php:8.2-fpm-alpine AS builder

# Устанавливаем системные зависимости, необходимые для сборки PHP-расширений
# Добавляем --no-cache для уменьшения размера слоя
RUN apk add --no-cache \
    # Для gd, imagick, iconv \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    # Для zip расширения \
    libzip-dev \
    # Для intl расширения \
    icu-dev \
    # Для PostgreSQL \
    postgresql-dev \
    # Для Redis \
    redis \
    # Для компиляции \
    $PHPIZE_DEPS \
    # Для Composer \
    git \
    unzip

# Устанавливаем и настраиваем PHP расширения
# Используем docker-php-ext-install для стандартных расширений
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install \
        gd \
        pdo_mysql \
        pdo_pgsql \
        intl \
        zip \
        opcache \
        bcmath \
        sockets \
        exif

# Устанавливаем PECL расширения
RUN pecl install \
        redis \
        apcu \
        xdebug \
    && docker-php-ext-enable \
        redis \
        apcu

# Копируем специфические конфигурации PHP
COPY docker/php/conf.d/ /usr/local/etc/php/conf.d/

# Устанавливаем Composer глобально
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Устанавливаем рабочий каталог
WORKDIR /var/www

# Копируем только файлы, необходимые для установки зависимостей
COPY composer.json composer.lock ./

# Устанавливаем зависимости без dev-зависимостей для production
# Используем флаги для оптимизации и безопасности
RUN composer install \
    --no-dev \
    --prefer-dist \
    --no-autoloader \
    --no-scripts \
    --no-progress \
    --optimize-autoloader \
    --ignore-platform-reqs

# Этап 2: Production образ
FROM php:8.2-fpm-alpine

# Метаданные образа
LABEL maintainer="your-team@example.com" \
      version="1.0" \
      description="Production PHP-FPM image"

# Создаем не-root пользователя для безопасности
#RUN addgroup -g 1000 appuser && \
#    adduser -u 1000 -G appuser -s /bin/sh -D appuser

# Устанавливаем только runtime зависимости (без dev пакетов)
RUN apk add --no-cache \
    # Runtime зависимости для PHP расширений \
    libpng \
    libjpeg-turbo \
    freetype \
    libzip \
    icu \
    postgresql-libs \
    # Системные утилиты \
    supervisor \
    tzdata \
    # Для healthcheck \
    curl \
    # Для отладки (можно удалить в production) \
    busybox-extras

# Копируем скомпилированные расширения из builder stage
COPY --from=builder /usr/local/etc/php /usr/local/etc/php
COPY --from=builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/

# Настраиваем PHP-FPM пулы
COPY docker/php-fpm.d/www.conf /usr/local/etc/php-fpm.d/www.conf

# Копируем супервизор для управления процессами
COPY docker/supervisor/supervisord.conf /etc/supervisor/supervisord.conf
COPY docker/supervisor/conf.d/ /etc/supervisor/conf.d/

# Устанавливаем корректные права
RUN chown -R appuser:appuser /var/www && \
    chmod 755 /var/www

# Копируем установленные зависимости из builder stage
COPY --from=builder /var/www/vendor /var/www/vendor

# Копируем исходный код приложения
COPY --chown=appuser:appuser . /var/www

# Копируем autoload файлы
COPY --from=builder /var/www/composer.* /var/www/

# Генерируем оптимизированный автозагрузчик
RUN composer dump-autoload --optimize --no-dev

# Переключаемся на не-root пользователя
USER appuser

# Настраиваем рабочую директорию
WORKDIR /var/www

# Настройка здоровья контейнера
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:9000/status || exit 1

# Оптимизация PHP для production
# Копируем production конфигурации
COPY docker/php/prod.ini /usr/local/etc/php/conf.d/prod.ini

# Создаем volume для сессий и кэша
VOLUME ["/var/www/storage", "/var/www/bootstrap/cache"]

# Указываем порт (для PHP-FPM это не обязательно, но полезно для документации)
EXPOSE 9000

# Указываем entrypoint и команду
ENTRYPOINT ["/usr/bin/supervisord"]
CMD ["-c", "/etc/supervisor/supervisord.conf"]