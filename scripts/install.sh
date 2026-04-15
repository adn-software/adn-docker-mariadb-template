#!/bin/bash

# Script de instalación automatizada para scripts de backup y health check
# Uso: ./install.sh <nombre_contenedor>

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Verificar argumentos
if [ -z "$1" ]; then
    error "Debe proporcionar el nombre del contenedor"
    echo "Uso: $0 <nombre_contenedor>"
    echo ""
    echo "Ejemplo: $0 mariadb-3330-jccrp"
    exit 1
fi

CONTAINER_NAME="$1"

log "════════════════════════════════════════════════"
log "INSTALACIÓN DE SCRIPTS DE BACKUP Y HEALTH CHECK"
log "════════════════════════════════════════════════"
log "Contenedor: $CONTAINER_NAME"
log "════════════════════════════════════════════════"

# Verificar que el contenedor existe
log "Verificando que el contenedor existe..."
if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    error "El contenedor '$CONTAINER_NAME' no existe"
    echo ""
    echo "Contenedores disponibles:"
    docker ps -a --format "  - {{.Names}}"
    exit 1
fi
log "✓ Contenedor encontrado"

# Verificar que el contenedor está corriendo
log "Verificando que el contenedor está corriendo..."
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    error "El contenedor '$CONTAINER_NAME' no está corriendo"
    echo ""
    echo "Iniciando contenedor..."
    docker start "$CONTAINER_NAME"
    sleep 3
fi
log "✓ Contenedor está corriendo"

# Copiar scripts esenciales
log "Copiando scripts al contenedor..."
docker cp scripts/backup-complete.sh "${CONTAINER_NAME}:/usr/local/bin/" || {
    error "Error al copiar backup-complete.sh"
    exit 1
}
docker cp scripts/health-check-complete.sh "${CONTAINER_NAME}:/usr/local/bin/" || {
    error "Error al copiar health-check-complete.sh"
    exit 1
}
docker cp scripts/wasabi-upload.sh "${CONTAINER_NAME}:/usr/local/bin/" || {
    error "Error al copiar wasabi-upload.sh"
    exit 1
}
log "✓ Scripts copiados (3 archivos)"

# Dar permisos de ejecución
log "Configurando permisos de ejecución..."
docker exec "$CONTAINER_NAME" chmod +x /usr/local/bin/backup-complete.sh
docker exec "$CONTAINER_NAME" chmod +x /usr/local/bin/health-check-complete.sh
docker exec "$CONTAINER_NAME" chmod +x /usr/local/bin/wasabi-upload.sh
log "✓ Permisos configurados"

# Crear directorio de backups
log "Creando directorio de backups..."
docker exec "$CONTAINER_NAME" mkdir -p /backups
docker exec "$CONTAINER_NAME" chmod 755 /backups
log "✓ Directorio de backups creado"

# Crear directorio de logs
log "Creando directorio de logs..."
docker exec "$CONTAINER_NAME" mkdir -p /var/log
docker exec "$CONTAINER_NAME" touch /var/log/backup.log
docker exec "$CONTAINER_NAME" touch /var/log/health.log
log "✓ Directorio de logs creado"

log "════════════════════════════════════════════════"
log "✓ INSTALACIÓN COMPLETADA"
log "════════════════════════════════════════════════"
echo ""
info "Próximos pasos:"
echo ""
echo "1. Verificar variables de entorno en docker-compose.yml:"
echo "   - MONITOR_API_KEY"
echo "   - MONITOR_SERVER_ID"
echo "   - MONITOR_DATABASE_ID"
echo ""
echo "2. Probar backup manualmente:"
echo "   docker exec -it $CONTAINER_NAME /usr/local/bin/backup-complete.sh"
echo ""
echo "3. Probar health check manualmente:"
echo "   docker exec -it $CONTAINER_NAME /usr/local/bin/health-check-complete.sh"
echo ""
echo "4. Configurar cron (opcional, si no usas entrypoint automático):"
echo "   ./scripts/configure-cron.sh <nombre_bd>"
echo ""
