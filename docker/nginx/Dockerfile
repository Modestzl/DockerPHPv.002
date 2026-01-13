# Используем alpine для минимального размера
FROM nginx:1.24-alpine

# Устанавливаем необходимые инструменты
RUN apk add --no-cache \
    curl \
    tzdata \
    openssl

# Копируем конфигурационные файлы
COPY nginx.conf /etc/nginx/nginx.conf
COPY conf.d/ /etc/nginx/conf.d/

# Создаем директории для логов и SSL
RUN mkdir -p /var/log/nginx && \
    mkdir -p /etc/nginx/ssl

# Открываем порт
EXPOSE 8080

# Запускаем Nginx в foreground режиме
CMD ["nginx", "-g", "daemon off;"]