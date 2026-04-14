#!/bin/bash

# Script de backup para MariaDB con notificación al sistema de monitoreo
# Uso: ./backup-notify.sh [nombre_base_datos]

# Configuración
BACKUP_DIR="${BACKUP_DIR:-/backups}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="root"
DB_PASSWORD="${MYSQL_ROOT_PASSWORD}"
DB_NAME="${1}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"

# Configuración del sistema de monitoreo
MONITOR_API_URL="${MONITOR_API_URL}"
MONITOR_API_KEY="${MONITOR_API_KEY}"
MONITOR_SERVER_ID="${MONITOR_SERVER_ID}"
MONITOR_DATABASE_ID="${MONITOR_DATABASE_ID}"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para logging
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR $(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Función para enviar notificación al sistema
send_notification() {
    local payload="$1"
    
    if [ -z "$MONITOR_API_URL" ] || [ -z "$MONITOR_API_KEY" ]; then
        warning "Sistema de monitoreo no configurado (MONITOR_API_URL o MONITOR_API_KEY faltantes)"
        warning "El backup se completó pero no se notificó al sistema"
        return 0
    fi
    
    info "Enviando notificación al sistema de monitoreo..."
    
    local response
    local http_code
    
    response=$(curl -s -w "\n%{http_code}" -X POST "${MONITOR_API_URL}/backup-logs" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: ${MONITOR_API_KEY}" \
        -d "$payload" \
        --max-time 30 \
        --retry 3 \
        --retry-delay 5 2>&1)
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
        log "✓ Notificación enviada exitosamente al sistema (HTTP $http_code)"
        return 0
    else
        error "✗ Error al enviar notificación (HTTP $http_code)"
        error "Response: $body"
        return 1
    fi
}

# Validar que se proporcionó el nombre de la base de datos
if [ -z "$DB_NAME" ]; then
    error "Debe proporcionar el nombre de la base de datos"
    error "Uso: $0 <nombre_base_datos>"
    exit 1
fi

# Crear directorio de backups si no existe
mkdir -p "$BACKUP_DIR"

# Generar timestamp y nombre de archivo
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/backup_${DB_NAME}_${DATE}.sql"
START_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
START_TIMESTAMP=$(date +%s)

log "════════════════════════════════════════════════"
log "INICIANDO BACKUP DE BASE DE DATOS"
log "════════════════════════════════════════════════"
log "Base de datos: $DB_NAME"
log "Archivo: $BACKUP_FILE"
log "Hora inicio: $START_TIME"
log "════════════════════════════════════════════════"

# Realizar backup
log "Ejecutando mysqldump..."
if mysqldump \
    -h "$DB_HOST" \
    -P "$DB_PORT" \
    -u "$DB_USER" \
    -p"${DB_PASSWORD}" \
    --single-transaction \
    --routines \
    --triggers \
    --events \
    "$DB_NAME" > "$BACKUP_FILE" 2>/dev/null; then
    
    # Backup exitoso
    END_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    END_TIMESTAMP=$(date +%s)
    DURATION=$((END_TIMESTAMP - START_TIMESTAMP))
    
    log "✓ Dump SQL completado exitosamente"
    
    # Obtener tamaño del archivo sin comprimir
    UNCOMPRESSED_SIZE=$(stat -c%s "$BACKUP_FILE" 2>/dev/null || stat -f%z "$BACKUP_FILE" 2>/dev/null)
    UNCOMPRESSED_SIZE_MB=$(echo "scale=2; $UNCOMPRESSED_SIZE / 1024 / 1024" | bc)
    info "Tamaño sin comprimir: ${UNCOMPRESSED_SIZE_MB} MB"
    
    # Comprimir backup
    log "Comprimiendo backup..."
    gzip "$BACKUP_FILE"
    BACKUP_FILE_GZ="${BACKUP_FILE}.gz"
    
    # Obtener tamaño del archivo comprimido
    BACKUP_SIZE=$(stat -c%s "$BACKUP_FILE_GZ" 2>/dev/null || stat -f%z "$BACKUP_FILE_GZ" 2>/dev/null)
    BACKUP_SIZE_MB=$(echo "scale=2; $BACKUP_SIZE / 1024 / 1024" | bc)
    
    # Calcular ratio de compresión
    COMPRESSION_RATIO=$(echo "scale=4; $BACKUP_SIZE / $UNCOMPRESSED_SIZE" | bc)
    COMPRESSION_PERCENT=$(echo "scale=1; (1 - $COMPRESSION_RATIO) * 100" | bc)
    
    log "✓ Backup comprimido exitosamente"
    info "Tamaño comprimido: ${BACKUP_SIZE_MB} MB"
    info "Ratio de compresión: ${COMPRESSION_RATIO} (${COMPRESSION_PERCENT}% reducción)"
    info "Duración: ${DURATION} segundos"
    
    # Obtener información adicional
    HOSTNAME=$(hostname)
    MARIADB_VERSION=$(mysql -V | awk '{print $5}' | sed 's/,//')
    
    # Preparar payload para el sistema de monitoreo
    PAYLOAD=$(cat <<EOF
{
  "databaseId": "${MONITOR_DATABASE_ID}",
  "serverId": "${MONITOR_SERVER_ID}",
  "backupType": "full",
  "status": "success",
  "startedAt": "${START_TIME}",
  "completedAt": "${END_TIME}",
  "duration": ${DURATION},
  "backupSize": ${BACKUP_SIZE},
  "backupPath": "${BACKUP_FILE_GZ}",
  "compressionRatio": ${COMPRESSION_RATIO},
  "source": "container",
  "metadata": {
    "hostname": "${HOSTNAME}",
    "mariadbVersion": "${MARIADB_VERSION}",
    "databaseName": "${DB_NAME}",
    "uncompressedSize": ${UNCOMPRESSED_SIZE}
  }
}
EOF
)
    
    # Enviar notificación al sistema
    send_notification "$PAYLOAD"
    
    # Eliminar backups antiguos
    log "Limpiando backups antiguos (más de $RETENTION_DAYS días)..."
    DELETED_COUNT=$(find "$BACKUP_DIR" -name "backup_*.sql.gz" -mtime +"$RETENTION_DAYS" -print -delete 2>/dev/null | wc -l)
    if [ "$DELETED_COUNT" -gt 0 ]; then
        log "✓ Eliminados $DELETED_COUNT backups antiguos"
    else
        info "No hay backups antiguos para eliminar"
    fi
    
    # Contar backups restantes
    BACKUP_COUNT=$(find "$BACKUP_DIR" -name "backup_*.sql.gz" 2>/dev/null | wc -l)
    
    log "════════════════════════════════════════════════"
    log "✓ BACKUP COMPLETADO EXITOSAMENTE"
    log "════════════════════════════════════════════════"
    log "Archivo: $BACKUP_FILE_GZ"
    log "Tamaño: ${BACKUP_SIZE_MB} MB"
    log "Duración: ${DURATION}s"
    log "Backups totales en disco: $BACKUP_COUNT"
    log "════════════════════════════════════════════════"
    
    exit 0
    
else
    # Backup fallido
    END_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    END_TIMESTAMP=$(date +%s)
    DURATION=$((END_TIMESTAMP - START_TIMESTAMP))
    
    # Capturar mensaje de error
    ERROR_MSG=$(mysqldump \
        -h "$DB_HOST" \
        -P "$DB_PORT" \
        -u "$DB_USER" \
        -p"${DB_PASSWORD}" \
        "$DB_NAME" 2>&1 | tail -5)
    
    error "✗ Falló el backup de la base de datos"
    error "Error: $ERROR_MSG"
    
    # Limpiar archivo parcial si existe
    rm -f "$BACKUP_FILE" 2>/dev/null || true
    
    # Preparar payload de error para el sistema de monitoreo
    HOSTNAME=$(hostname)
    PAYLOAD=$(cat <<EOF
{
  "databaseId": "${MONITOR_DATABASE_ID}",
  "serverId": "${MONITOR_SERVER_ID}",
  "backupType": "full",
  "status": "failed",
  "startedAt": "${START_TIME}",
  "completedAt": "${END_TIME}",
  "duration": ${DURATION},
  "source": "container",
  "errorMessage": "Backup failed",
  "errorDetails": {
    "error": "${ERROR_MSG}",
    "hostname": "${HOSTNAME}",
    "databaseName": "${DB_NAME}"
  },
  "metadata": {
    "hostname": "${HOSTNAME}",
    "databaseName": "${DB_NAME}"
  }
}
EOF
)
    
    # Enviar notificación de fallo
    send_notification "$PAYLOAD"
    
    log "════════════════════════════════════════════════"
    error "✗ BACKUP FALLIDO"
    log "════════════════════════════════════════════════"
    
    exit 1
fi
