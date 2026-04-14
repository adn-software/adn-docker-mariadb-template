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

# Copiar scripts
log "Copiando scripts al contenedor..."
docker cp scripts/backup-notify.sh "${CONTAINER_NAME}:/usr/local/bin/" || {
    error "Error al copiar backup-notify.sh"
    exit 1
}
docker cp scripts/health-check-notify.sh "${CONTAINER_NAME}:/usr/local/bin/" || {
    error "Error al copiar health-check-notify.sh"
    exit 1
}
log "✓ Scripts copiados"

# Dar permisos de ejecución
log "Configurando permisos de ejecución..."
docker exec "$CONTAINER_NAME" chmod +x /usr/local/bin/backup-notify.sh
docker exec "$CONTAINER_NAME" chmod +x /usr/local/bin/health-check-notify.sh
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

# Verificar si ya existe configuración
if docker exec "$CONTAINER_NAME" test -f /etc/monitor.env; then
    warning "Ya existe un archivo de configuración en /etc/monitor.env"
    info "Se mantendrá la configuración existente"
else
    log "Creando archivo de configuración de ejemplo..."
    docker exec "$CONTAINER_NAME" bash -c 'cat > /etc/monitor.env << EOF
# Configuración del Sistema de Monitoreo ADN
MONITOR_API_URL=https://api.adnsistemas.com/api/v1
MONITOR_API_KEY=CAMBIAR_POR_TU_API_KEY
MONITOR_SERVER_ID=CAMBIAR_POR_TU_SERVER_UUID
MONITOR_DATABASE_ID=CAMBIAR_POR_TU_DATABASE_UUID

# Configuración de Backups
BACKUP_DIR=/backups
BACKUP_RETENTION_DAYS=7

# Configuración de MariaDB
DB_HOST=localhost
DB_PORT=3306

# NOTA: MYSQL_ROOT_PASSWORD debe estar ya configurado en el contenedor
EOF'
    log "✓ Archivo de configuración creado en /etc/monitor.env"
    warning "⚠ IMPORTANTE: Debes editar /etc/monitor.env con tus credenciales"
fi

# Configurar carga automática de variables
log "Configurando carga automática de variables..."
docker exec "$CONTAINER_NAME" bash -c 'grep -q "source /etc/monitor.env" /root/.bashrc || echo "source /etc/monitor.env" >> /root/.bashrc'
log "✓ Variables se cargarán automáticamente"

log "════════════════════════════════════════════════"
log "✓ INSTALACIÓN COMPLETADA"
log "════════════════════════════════════════════════"
echo ""
info "Próximos pasos:"
echo ""
echo "1. Editar configuración:"
echo "   docker exec -it $CONTAINER_NAME nano /etc/monitor.env"
echo ""
echo "2. Probar backup manualmente:"
echo "   docker exec -it $CONTAINER_NAME bash"
echo "   source /etc/monitor.env"
echo "   /usr/local/bin/backup-notify.sh <nombre_base_datos>"
echo ""
echo "3. Probar health check manualmente:"
echo "   docker exec -it $CONTAINER_NAME bash"
echo "   source /etc/monitor.env"
echo "   /usr/local/bin/health-check-notify.sh <nombre_base_datos>"
echo ""
echo "4. Configurar cron (después de probar):"
echo "   Ver instrucciones en INSTALACION.md"
echo ""
warning "⚠ RECUERDA: Edita /etc/monitor.env con tus credenciales antes de ejecutar los scripts"
echo ""
