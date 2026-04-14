#!/bin/bash

# Script de restauración para MariaDB Docker
# Uso: ./restore.sh <archivo_backup.sql.gz>

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Verificar argumentos
if [ $# -eq 0 ]; then
    error "Uso: $0 <archivo_backup.sql.gz>"
    echo "Ejemplo: $0 backups/backup_client_database_20250128_120000.sql.gz"
    exit 1
fi

BACKUP_FILE="$1"
CONTAINER_NAME="${CONTAINER_NAME:-mariadb-client}"
DB_NAME="${MYSQL_DATABASE}"

# Verificar que el archivo existe
if [ ! -f "$BACKUP_FILE" ]; then
    error "El archivo de backup no existe: $BACKUP_FILE"
    exit 1
fi

# Verificar que el contenedor está corriendo
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    error "El contenedor $CONTAINER_NAME no está corriendo"
    exit 1
fi

# Advertencia
warning "⚠️  ADVERTENCIA: Esta operación sobrescribirá la base de datos actual"
warning "Base de datos: $DB_NAME"
warning "Archivo: $BACKUP_FILE"
echo ""
read -p "¿Estás seguro de continuar? (escribe 'SI' para confirmar): " CONFIRM

if [ "$CONFIRM" != "SI" ]; then
    log "Operación cancelada por el usuario"
    exit 0
fi

log "Iniciando restauración de la base de datos: $DB_NAME"

# Descomprimir si es necesario
if [[ "$BACKUP_FILE" == *.gz ]]; then
    log "Descomprimiendo archivo..."
    TEMP_FILE=$(mktemp)
    gunzip -c "$BACKUP_FILE" > "$TEMP_FILE"
    SQL_FILE="$TEMP_FILE"
else
    SQL_FILE="$BACKUP_FILE"
fi

# Restaurar backup
log "Restaurando backup..."
if docker exec -i "$CONTAINER_NAME" mysql \
    -u root \
    -p"${MYSQL_ROOT_PASSWORD}" \
    "$DB_NAME" < "$SQL_FILE"; then
    
    log "✅ Restauración completada exitosamente"
    
    # Limpiar archivo temporal
    if [ -n "$TEMP_FILE" ]; then
        rm -f "$TEMP_FILE"
    fi
    
    exit 0
else
    error "❌ Falló la restauración de la base de datos"
    
    # Limpiar archivo temporal
    if [ -n "$TEMP_FILE" ]; then
        rm -f "$TEMP_FILE"
    fi
    
    exit 1
fi
