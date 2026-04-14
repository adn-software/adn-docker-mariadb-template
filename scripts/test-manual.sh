#!/bin/bash

# Script de prueba manual para verificar backup y health check
# Uso: ./test-manual.sh <nombre_contenedor> <nombre_base_datos>

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
if [ -z "$1" ] || [ -z "$2" ]; then
    error "Debe proporcionar el nombre del contenedor y la base de datos"
    echo "Uso: $0 <nombre_contenedor> <nombre_base_datos>"
    echo ""
    echo "Ejemplo: $0 mariadb-3330-jccrp sistemasadn"
    exit 1
fi

CONTAINER_NAME="$1"
DATABASE_NAME="$2"

log "════════════════════════════════════════════════"
log "PRUEBA MANUAL DE BACKUP Y HEALTH CHECK"
log "════════════════════════════════════════════════"
log "Contenedor: $CONTAINER_NAME"
log "Base de datos: $DATABASE_NAME"
log "════════════════════════════════════════════════"
echo ""

# Verificar que el contenedor existe y está corriendo
log "Verificando contenedor..."
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    error "El contenedor '$CONTAINER_NAME' no está corriendo"
    exit 1
fi
log "✓ Contenedor corriendo"
echo ""

# Verificar que los scripts están instalados
log "Verificando scripts instalados..."
if ! docker exec "$CONTAINER_NAME" test -f /usr/local/bin/backup-notify.sh; then
    error "Script backup-notify.sh no encontrado"
    echo ""
    info "Ejecuta primero: ./install.sh $CONTAINER_NAME"
    exit 1
fi
if ! docker exec "$CONTAINER_NAME" test -f /usr/local/bin/health-check-notify.sh; then
    error "Script health-check-notify.sh no encontrado"
    exit 1
fi
log "✓ Scripts instalados"
echo ""

# Verificar configuración
log "Verificando configuración..."
if ! docker exec "$CONTAINER_NAME" test -f /etc/monitor.env; then
    error "Archivo de configuración /etc/monitor.env no encontrado"
    echo ""
    info "Ejecuta primero: ./install.sh $CONTAINER_NAME"
    exit 1
fi

# Mostrar configuración (sin mostrar la API Key completa)
info "Configuración actual:"
docker exec "$CONTAINER_NAME" bash -c 'source /etc/monitor.env && cat << EOF
  API URL: $MONITOR_API_URL
  API Key: ${MONITOR_API_KEY:0:15}...
  Server ID: $MONITOR_SERVER_ID
  Database ID: $MONITOR_DATABASE_ID
  Backup Dir: $BACKUP_DIR
  Retention: $BACKUP_RETENTION_DAYS días
EOF'
echo ""

# Verificar si la configuración está completa
CONFIG_OK=true
docker exec "$CONTAINER_NAME" bash -c 'source /etc/monitor.env && [ "$MONITOR_API_KEY" = "CAMBIAR_POR_TU_API_KEY" ]' && {
    warning "⚠ MONITOR_API_KEY no está configurado"
    CONFIG_OK=false
}
docker exec "$CONTAINER_NAME" bash -c 'source /etc/monitor.env && [ "$MONITOR_SERVER_ID" = "CAMBIAR_POR_TU_SERVER_UUID" ]' && {
    warning "⚠ MONITOR_SERVER_ID no está configurado"
    CONFIG_OK=false
}
docker exec "$CONTAINER_NAME" bash -c 'source /etc/monitor.env && [ "$MONITOR_DATABASE_ID" = "CAMBIAR_POR_TU_DATABASE_UUID" ]' && {
    warning "⚠ MONITOR_DATABASE_ID no está configurado"
    CONFIG_OK=false
}

if [ "$CONFIG_OK" = false ]; then
    echo ""
    warning "La configuración no está completa. Los scripts funcionarán pero NO notificarán al sistema."
    echo ""
    read -p "¿Deseas continuar de todas formas? (s/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        info "Edita la configuración con:"
        echo "  docker exec -it $CONTAINER_NAME nano /etc/monitor.env"
        exit 0
    fi
fi
echo ""

# Verificar que la base de datos existe
log "Verificando que la base de datos existe..."
if ! docker exec "$CONTAINER_NAME" bash -c "mysql -u root -p\"\${MYSQL_ROOT_PASSWORD}\" -e 'USE $DATABASE_NAME;' 2>/dev/null"; then
    error "La base de datos '$DATABASE_NAME' no existe o no se puede acceder"
    echo ""
    info "Bases de datos disponibles:"
    docker exec "$CONTAINER_NAME" bash -c "mysql -u root -p\"\${MYSQL_ROOT_PASSWORD}\" -e 'SHOW DATABASES;' 2>/dev/null" | tail -n +2 | while read db; do
        echo "  - $db"
    done
    exit 1
fi
log "✓ Base de datos accesible"
echo ""

# Menú de opciones
echo ""
log "════════════════════════════════════════════════"
log "OPCIONES DE PRUEBA"
log "════════════════════════════════════════════════"
echo "1. Ejecutar BACKUP"
echo "2. Ejecutar HEALTH CHECK"
echo "3. Ejecutar AMBOS (backup + health check)"
echo "4. Ver logs de backup"
echo "5. Ver logs de health check"
echo "6. Listar backups existentes"
echo "7. Salir"
echo ""
read -p "Selecciona una opción (1-7): " -n 1 -r
echo
echo ""

case $REPLY in
    1)
        log "════════════════════════════════════════════════"
        log "EJECUTANDO BACKUP"
        log "════════════════════════════════════════════════"
        echo ""
        docker exec -it "$CONTAINER_NAME" bash -c "source /etc/monitor.env && /usr/local/bin/backup-notify.sh $DATABASE_NAME"
        ;;
    2)
        log "════════════════════════════════════════════════"
        log "EJECUTANDO HEALTH CHECK"
        log "════════════════════════════════════════════════"
        echo ""
        docker exec -it "$CONTAINER_NAME" bash -c "source /etc/monitor.env && /usr/local/bin/health-check-notify.sh $DATABASE_NAME"
        ;;
    3)
        log "════════════════════════════════════════════════"
        log "EJECUTANDO BACKUP"
        log "════════════════════════════════════════════════"
        echo ""
        docker exec -it "$CONTAINER_NAME" bash -c "source /etc/monitor.env && /usr/local/bin/backup-notify.sh $DATABASE_NAME"
        echo ""
        echo ""
        log "════════════════════════════════════════════════"
        log "EJECUTANDO HEALTH CHECK"
        log "════════════════════════════════════════════════"
        echo ""
        docker exec -it "$CONTAINER_NAME" bash -c "source /etc/monitor.env && /usr/local/bin/health-check-notify.sh $DATABASE_NAME"
        ;;
    4)
        log "Mostrando logs de backup..."
        echo ""
        docker exec "$CONTAINER_NAME" tail -50 /var/log/backup.log 2>/dev/null || echo "No hay logs de backup aún"
        ;;
    5)
        log "Mostrando logs de health check..."
        echo ""
        docker exec "$CONTAINER_NAME" tail -50 /var/log/health.log 2>/dev/null || echo "No hay logs de health check aún"
        ;;
    6)
        log "Listando backups existentes..."
        echo ""
        docker exec "$CONTAINER_NAME" bash -c 'ls -lh /backups/*.gz 2>/dev/null || echo "No hay backups aún"'
        echo ""
        docker exec "$CONTAINER_NAME" bash -c 'du -sh /backups 2>/dev/null'
        ;;
    7)
        log "Saliendo..."
        exit 0
        ;;
    *)
        error "Opción inválida"
        exit 1
        ;;
esac

echo ""
log "════════════════════════════════════════════════"
log "PRUEBA COMPLETADA"
log "════════════════════════════════════════════════"
echo ""
info "Próximos pasos:"
echo "  - Verificar en el sistema de monitoreo que se recibieron las notificaciones"
echo "  - Si todo funciona bien, configurar cron para ejecución automática"
echo "  - Ver INSTALACION.md para más detalles"
echo ""
