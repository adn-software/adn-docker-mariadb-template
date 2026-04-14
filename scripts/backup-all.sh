#!/bin/bash

# Script de backup automático para todas las bases de datos MariaDB
# Uso: ./backup-all.sh (backups de todas las BDs de usuario)
#      ./backup-all.sh [nombre_bd] (backup de una BD específica)

# NO usamos set -e porque queremos que continúe con todas las BDs aunque una falle

# Configuración
BACKUP_DIR="${BACKUP_DIR:-/backups}"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"

# Credenciales - usar root para operaciones administrativas
DB_USER="root"
DB_PASSWORD="${MYSQL_ROOT_PASSWORD}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"

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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Crear directorio de backups si no existe
mkdir -p "$BACKUP_DIR"

# Configuración del formato de nombre de backup
SERVER_NAME="${SERVER_NAME:-servidor}"
CLIENT_NAME="${CLIENT_NAME:-cliente}"
MYSQL_PORT_EXT="${MYSQL_PORT_EXT:-3306}"

# Función para hacer backup de una base de datos específica
backup_database() {
    local DB_NAME="$1"
    local BACKUP_FILE="$BACKUP_DIR/backup_${DB_NAME}_${DATE}.sql"

    log "Iniciando backup de: $DB_NAME"

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

        # Comprimir backup
        gzip "$BACKUP_FILE"
        local BACKUP_SIZE=$(du -h "${BACKUP_FILE}.gz" | cut -f1)
        log "Backup creado: ${DB_NAME} -> ${BACKUP_FILE}.gz (${BACKUP_SIZE})"

        # Subir a Wasabi S3 con el nuevo formato de nombre
        upload_to_wasabi "${BACKUP_FILE}.gz" "$DB_NAME"

        return 0
    else
        error "Falló el backup de: $DB_NAME"
        rm -f "$BACKUP_FILE" 2>/dev/null || true
        return 1
    fi
}

# Función para subir backup a Wasabi
upload_to_wasabi() {
    local BACKUP_FILE="$1"
    local DB_NAME="$2"

    if [ -x /usr/local/bin/wasabi-upload.sh ]; then
        info "Subiendo backup a Wasabi..."
        if /usr/local/bin/wasabi-upload.sh "$BACKUP_FILE" "$DB_NAME"; then
            log "Backup subido exitosamente a Wasabi"
        else
            warning "No se pudo subir el backup a Wasabi, pero se mantiene el archivo local"
        fi
    else
        warning "Script de upload a Wasabi no encontrado, omitiendo..."
    fi
}

# Obtener lista de bases de datos (excluyendo las del sistema)
get_user_databases() {
    mysql \
        -h "$DB_HOST" \
        -P "$DB_PORT" \
        -u "$DB_USER" \
        -p"${DB_PASSWORD}" \
        -e "SHOW DATABASES WHERE \`Database\` NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys');" \
        2>/dev/null | tail -n +2
}

# Main
main() {
    log "========================================"
    log "INICIANDO PROCESO DE BACKUP"
    log "Directorio: $BACKUP_DIR"
    log "Retención: $RETENTION_DAYS días"
    log "========================================"

    local SPECIFIC_DB="${1:-}"
    local FAILED_BACKUPS=0
    local SUCCESSFUL_BACKUPS=0

    if [ -n "$SPECIFIC_DB" ]; then
        # Backup de una BD específica
        info "Modo: Backup específico de '$SPECIFIC_DB'"
        if backup_database "$SPECIFIC_DB"; then
            ((SUCCESSFUL_BACKUPS++))
        else
            ((FAILED_BACKUPS++))
        fi
    else
        # Backup de todas las BDs de usuario
        info "Modo: Backup automático de todas las bases de datos de usuario"

        local DATABASES
        DATABASES=$(get_user_databases)

        if [ -z "$DATABASES" ]; then
            warning "No se encontraron bases de datos de usuario para respaldar"
            exit 0
        fi

        info "Bases de datos encontradas:"
        echo "$DATABASES" | while read -r db; do
            info "  - $db"
        done

        log "Iniciando backups..."

        # Procesar cada base de datos
        for DB_NAME in $DATABASES; do
            if [ -n "$DB_NAME" ]; then
                if backup_database "$DB_NAME"; then
                    ((SUCCESSFUL_BACKUPS++))
                else
                    ((FAILED_BACKUPS++))
                fi
            fi
        done
    fi

    # Eliminar backups antiguos
    log "Limpiando backups antiguos (más de $RETENTION_DAYS días)..."
    local DELETED_COUNT
    DELETED_COUNT=$(find "$BACKUP_DIR" -name "backup_*.sql.gz" -mtime +"$RETENTION_DAYS" -print -delete | wc -l)
    log "Backups eliminados: $DELETED_COUNT"

    # Resumen
    local TOTAL_BACKUPS
    TOTAL_BACKUPS=$(find "$BACKUP_DIR" -name "backup_*.sql.gz" | wc -l)

    log "========================================"
    log "RESUMEN DEL BACKUP"
    log "Exitosos: $SUCCESSFUL_BACKUPS"
    log "Fallidos: $FAILED_BACKUPS"
    log "Total backups en disco: $TOTAL_BACKUPS"
    log "========================================"

    if [ $FAILED_BACKUPS -gt 0 ]; then
        exit 1
    fi

    log "Proceso completado exitosamente"
    exit 0
}

main "$@"
