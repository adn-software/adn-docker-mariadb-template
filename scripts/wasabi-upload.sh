#!/bin/bash

# Script para subir archivos a Wasabi S3
# Uso: ./wasabi-upload.sh <archivo_local> <nombre_base_datos>
# El nombre en S3 se construye: SERVIDOR-PUERTO-CLIENTE-BASEDATOS-FECHAHORA.sql.gz

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} [Wasabi] $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} [Wasabi] $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} [Wasabi] $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} [Wasabi] $1"
}

# Función para limpiar backups antiguos manteniendo solo los últimos 7
cleanup_old_backups() {
    local RETENTION_COUNT=7
    
    # Patrón para buscar backups de esta base de datos
    local BACKUP_PATTERN="${SERVER_NAME}-${MYSQL_PORT_EXT}-${CLIENT_NAME}-${DB_NAME}-*.sql.gz"
    
    log "Limpiando backups antiguos en Wasabi (manteniendo últimos $RETENTION_COUNT)..."
    
    # Listar todos los backups de esta BD ordenados por fecha (más recientes primero)
    local ALL_BACKUPS=$(aws s3 ls "s3://${WASABI_BUCKET}/${SERVER_NAME}-${MYSQL_PORT_EXT}-${CLIENT_NAME}-${DB_NAME}-" \
        --endpoint-url="$WASABI_ENDPOINT" \
        --region="$WASABI_REGION" 2>/dev/null | grep "\.sql\.gz$" | sort -k1,2 -r)
    
    local BACKUP_COUNT=$(echo "$ALL_BACKUPS" | wc -l)
    
    if [ "$BACKUP_COUNT" -gt "$RETENTION_COUNT" ]; then
        info "Encontrados $BACKUP_COUNT backups, eliminando $(($BACKUP_COUNT - $RETENTION_COUNT)) antiguos..."
        
        # Obtener los archivos a eliminar (del 8vo en adelante)
        local BACKUPS_TO_DELETE=$(echo "$ALL_BACKUPS" | tail -n +$(($RETENTION_COUNT + 1)))
        
        # Eliminar cada archivo antiguo
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                local OLD_FILE=$(echo "$line" | awk '{print $4}')
                if [ -n "$OLD_FILE" ]; then
                    info "Eliminando backup antiguo: $OLD_FILE"
                    aws s3 rm "s3://${WASABI_BUCKET}/${OLD_FILE}" \
                        --endpoint-url="$WASABI_ENDPOINT" \
                        --region="$WASABI_REGION" >/dev/null 2>&1
                fi
            fi
        done <<< "$BACKUPS_TO_DELETE"
        
        log "Limpieza completada. Mantenidos: $RETENTION_COUNT backups"
    else
        info "No hay backups para eliminar. Total: $BACKUP_COUNT (límite: $RETENTION_COUNT)"
    fi
}

# Verificar que AWS CLI está instalado
if ! command -v aws &> /dev/null; then
    error "AWS CLI no está instalado"
    exit 1
fi

# Configuración de Wasabi desde variables de entorno
WASABI_ACCESS_KEY="${WASABI_ACCESS_KEY:-}"
WASABI_SECRET_KEY="${WASABI_SECRET_KEY:-}"
WASABI_BUCKET="${WASABI_BUCKET:-}"
WASABI_REGION="${WASABI_REGION:-us-east-1}"
WASABI_ENDPOINT="${WASABI_ENDPOINT:-https://s3.us-east-1.wasabisys.com}"
WASABI_UPLOAD_ENABLED="${WASABI_UPLOAD_ENABLED:-true}"

# Configuración del formato de nombre de backup
SERVER_NAME="${SERVER_NAME:-servidor}"
CLIENT_NAME="${CLIENT_NAME:-cliente}"
MYSQL_PORT_EXT="${MYSQL_PORT_EXT:-3306}"

# Verificar si el upload está habilitado
if [ "$WASABI_UPLOAD_ENABLED" != "true" ]; then
    info "Upload a Wasabi está deshabilitado (WASABI_UPLOAD_ENABLED=false)"
    exit 0
fi

# Verificar credenciales
if [ -z "$WASABI_ACCESS_KEY" ] || [ -z "$WASABI_SECRET_KEY" ]; then
    error "Credenciales de Wasabi no configuradas (WASABI_ACCESS_KEY / WASABI_SECRET_KEY)"
    exit 1
fi

if [ -z "$WASABI_BUCKET" ]; then
    error "Bucket de Wasabi no configurado (WASABI_BUCKET)"
    exit 1
fi

# Parámetros
LOCAL_FILE="${1:-}"
DB_NAME="${2:-}"

if [ -z "$LOCAL_FILE" ]; then
    error "Debe especificar el archivo local a subir"
    echo "Uso: $0 <archivo_local> <nombre_base_datos>"
    exit 1
fi

if [ ! -f "$LOCAL_FILE" ]; then
    error "El archivo no existe: $LOCAL_FILE"
    exit 1
fi

# Construir nombre del archivo en S3 con formato: servidor-puerto-cliente-basededatos-fechahora.sql.gz
# Extraer timestamp del nombre del archivo local (formato: backup_DBNAME_YYYYMMDD_HHMMSS.sql.gz)
TIMESTAMP=$(basename "$LOCAL_FILE" | grep -oE '[0-9]{8}_[0-9]{6}' || date +'%Y%m%d_%H%M%S')
# Formatear timestamp: YYYYMMDD_HHMMSS → YYYYMMDD-HHMMSS (con guion en lugar de underscore)
FORMATTED_TIMESTAMP=$(echo "$TIMESTAMP" | sed 's/_/-/')
S3_KEY="${SERVER_NAME}-${MYSQL_PORT_EXT}-${CLIENT_NAME}-${DB_NAME}-${FORMATTED_TIMESTAMP}.sql.gz"

# Crear directorio temporal para configuración AWS
AWS_CONFIG_DIR=$(mktemp -d)
trap "rm -rf $AWS_CONFIG_DIR" EXIT

# Configurar credenciales AWS para Wasabi
cat > "$AWS_CONFIG_DIR/credentials" << EOF
[default]
aws_access_key_id = $WASABI_ACCESS_KEY
aws_secret_access_key = $WASABI_SECRET_KEY
EOF

cat > "$AWS_CONFIG_DIR/config" << EOF
[default]
region = $WASABI_REGION
EOF

export AWS_CONFIG_FILE="$AWS_CONFIG_DIR/config"
export AWS_SHARED_CREDENTIALS_FILE="$AWS_CONFIG_DIR/credentials"

# Información del archivo
FILE_SIZE=$(du -h "$LOCAL_FILE" | cut -f1)
FILE_SIZE_BYTES=$(stat -c%s "$LOCAL_FILE" 2>/dev/null || stat -f%z "$LOCAL_FILE" 2>/dev/null)

log "Iniciando upload a Wasabi..."
info "Archivo local: $LOCAL_FILE ($FILE_SIZE)"
info "Destino: s3://$WASABI_BUCKET/$S3_KEY"
info "Endpoint: $WASABI_ENDPOINT"

# Subir archivo a Wasabi usando AWS CLI
if aws s3 cp "$LOCAL_FILE" "s3://$WASABI_BUCKET/$S3_KEY" \
    --endpoint-url="$WASABI_ENDPOINT" \
    --region="$WASABI_REGION" \
    --storage-class STANDARD \
    2>&1; then
    
    log "Upload completado exitosamente"
    info "URL: s3://$WASABI_BUCKET/$S3_KEY"
    
    # Verificar que el archivo existe en S3
    if aws s3 ls "s3://$WASABI_BUCKET/$S3_KEY" \
        --endpoint-url="$WASABI_ENDPOINT" \
        --region="$WASABI_REGION" > /dev/null 2>&1; then
        
        # Obtener tamaño del archivo en S3
        S3_SIZE=$(aws s3 ls "s3://$WASABI_BUCKET/$S3_KEY" \
            --endpoint-url="$WASABI_ENDPOINT" \
            --region="$WASABI_REGION" 2>/dev/null | awk '{print $3}')
        
        if [ "$S3_SIZE" = "$FILE_SIZE_BYTES" ]; then
            log "Verificación exitosa: archivo en S3 tiene el mismo tamaño que el local"
            # Limpiar backups antiguos manteniendo solo los últimos 7
            cleanup_old_backups
            exit 0
        else
            warning "El tamaño del archivo en S3 ($S3_SIZE bytes) difiere del local ($FILE_SIZE_BYTES bytes)"
            exit 0  # No fallar, pero advertir
        fi
    else
        warning "No se pudo verificar el archivo en S3, pero el upload no reportó errores"
        exit 0
    fi
else
    error "Falló el upload a Wasabi"
    exit 1
fi
