#!/bin/bash

# Скрипт деплоя для высоконагруженного приложения

set -e  # Выход при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Начало деплоя высоконагруженного PHP приложения${NC}"

# Проверка переменных окружения
if [ ! -f .env ]; then
    echo -e "${YELLOW}Файл .env не найден. Создаем из примера...${NC}"
    cp .env.example .env
    echo -e "${RED}Пожалуйста, настройте файл .env перед продолжением${NC}"
    exit 1
fi

# Загрузка переменных окружения
source .env

# Функция для логирования
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# Функция для обработки ошибок
error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ОШИБКА: $1${NC}"
    exit 1
}

# Проверка зависимостей
check_dependencies() {
    log "Проверка зависимостей..."

    # Проверка Docker
    if ! command -v docker &> /dev/null; then
        error "Docker не установлен"
    fi

    # Проверка Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose не установлен"
    fi

    # Проверка дискового пространства
    FREE_SPACE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$FREE_SPACE" -lt 10 ]; then
        error "Недостаточно свободного места на диске (нужно минимум 10GB)"
    fi
}

# Сборка образов
build_images() {
    log "Сборка Docker образов..."

    # Сборка PHP образа с кэшированием
    docker build -t highload-php:latest \
        --build-arg PHP_ENV=production \
        --build-arg COMPOSER_NO_DEV=1 \
        ./php || error "Ошибка сборки PHP образа"

    # Сборка Nginx образа
    docker build -t highload-nginx:latest \
        ./nginx || error "Ошибка сборки Nginx образа"
}

# Запуск сервисов
start_services() {
    log "Запуск основных сервисов..."

    # Запуск базы данных и Redis
    docker-compose up -d mysql redis || error "Ошибка запуска базовых сервисов"

    # Ожидание готовности MySQL
    log "Ожидание готовности MySQL..."
    for i in {1..30}; do
        if docker-compose exec mysql mysqladmin ping -h localhost -u${DB_USER} -p${DB_PASSWORD} --silent; then
            log "MySQL готов"
            break
        fi
        sleep 2
    done

    # Запуск PHP и Nginx
    docker-compose up -d php nginx || error "Ошибка запуска PHP/Nginx"

    # Ожидание готовности PHP-FPM
    log "Ожидание готовности PHP-FPM..."
    for i in {1..30}; do
        if docker-compose exec php php-fpm -t; then
            log "PHP-FPM готов"
            break
        fi
        sleep 2
    done
}

# Оптимизация базы данных
optimize_database() {
    log "Оптимизация базы данных..."

    # Создание пользователя для мониторинга
    docker-compose exec mysql mysql -u root -p${DB_ROOT_PASSWORD} -e "
        CREATE USER IF NOT EXISTS 'monitor'@'%' IDENTIFIED BY '${DB_MONITOR_PASSWORD}';
        GRANT PROCESS, REPLICATION CLIENT ON *.* TO 'monitor'@'%';
        FLUSH PRIVILEGES;
    " || error "Ошибка создания пользователя мониторинга"

    # Настройка индексов
    docker-compose exec mysql mysql -u root -p${DB_ROOT_PASSWORD} ${DB_NAME} -e "
        SET GLOBAL innodb_buffer_pool_size = 2147483648;
        SET GLOBAL innodb_log_file_size = 268435456;
        SET GLOBAL max_connections = 1000;
    " || error "Ошибка оптимизации базы данных"
}

# Настройка мониторинга
setup_monitoring() {
    log "Настройка мониторинга..."

    # Запуск сервисов мониторинга
    docker-compose -f docker-compose.monitoring.yml up -d || error "Ошибка запуска мониторинга"

    # Импорт дашбордов в Grafana
    sleep 10  # Ожидаем запуск Grafana

    # Создание источника данных Prometheus
    curl -X POST "http://admin:${GRAFANA_PASSWORD}@localhost:3000/api/datasources" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "Prometheus",
            "type": "prometheus",
            "url": "http://prometheus:9090",
            "access": "proxy"
        }' || log "Предупреждение: не удалось создать источник данных Grafana"
}

# Health check
health_check() {
    log "Проверка здоровья приложения..."

    # Проверка Nginx
    if ! curl -f http://localhost/health > /dev/null 2>&1; then
        error "Nginx не отвечает"
    fi

    # Проверка PHP-FPM
    if ! docker-compose exec php php-fpm -t > /dev/null 2>&1; then
        error "PHP-FPM не отвечает"
    fi

    # Проверка Redis
    if ! docker-compose exec redis redis-cli -a ${REDIS_PASSWORD} ping > /dev/null 2>&1; then
        error "Redis не отвечает"
    fi

    log "Все сервисы работают корректно"
}

# Основной процесс деплоя
main() {
    log "Начало процесса деплоя"

    # 1. Проверка зависимостей
    check_dependencies

    # 2. Сборка образов
    build_images

    # 3. Остановка старых сервисов
    log "Остановка старых сервисов..."
    docker-compose down --remove-orphans

    # 4. Запуск сервисов
    start_services

    # 5. Оптимизация базы данных
    optimize_database

    # 6. Настройка мониторинга
    if [ "$ENABLE_MONITORING" = "true" ]; then
        setup_monitoring
    fi

    # 7. Health check
    health_check

    # 8. Запуск балансировщика
    log "Запуск HAProxy..."
    docker-compose up -d haproxy

    log "Деплой успешно завершен!"
    echo ""
    echo "Доступные сервисы:"
    echo "- Приложение: http://localhost"
    echo "- Grafana: http://localhost:3000 (admin:${GRAFANA_PASSWORD})"
    echo "- Prometheus: http://localhost:9090"
    echo ""
    echo "Статус сервисов:"
    docker-compose ps
}

# Запуск основного процесса
main