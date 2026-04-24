#!/bin/bash

# Script completo de backup para MariaDB
# - Backup de todas las bases de datos de usuario (no del sistema)
# - Subida automática a Wasabi S3
# - Notificación al sistema de monitoreo ADN
#
# Uso: ./backup-complete.sh

# NO usamos set -e porque queremos que continúe con todas las BDs aunque una falle

# Cargar variables de entorno si existen (para cron)
if [ -f /etc/cron.d/adn-backup-env ]; then
    set -a
    source /etc/cron.d/adn-backup-env
    set +a
    # Log de diagnóstico (solo si se ejecuta desde cron)
    if [ -z "$TERM" ]; then
        echo "[DEBUG] Variables cargadas desde /etc/cron.d/adn-backup-env" >&2
        echo "[DEBUG] PATH=$PATH" >&2
        echo "[DEBUG] MONITOR_API_URL=$MONITOR_API_URL" >&2
        echo "[DEBUG] WASABI_ENDPOINT=$WASABI_ENDPOINT" >&2
    fi
fi

# ============================================
# CONFIGURACIÓN
# ============================================
BACKUP_DIR="${BACKUP_DIR:-/backups}"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"

# Credenciales MariaDB - Intentar múltiples fuentes
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-${MYSQL_ROOT_PASSWORD:-${MARIADB_ROOT_PASSWORD}}}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"

# Configuración del sistema de monitoreo
MONITOR_API_URL="${MONITOR_API_URL}"
MONITOR_API_KEY="${MONITOR_API_KEY}"
MONITOR_SERVER_ID="${MONITOR_SERVER_ID}"

# Configuración Wasabi S3
WASABI_ACCESS_KEY="${WASABI_ACCESS_KEY}"
WASABI_SECRET_KEY="${WASABI_SECRET_KEY}"
WASABI_BUCKET="${WASABI_BUCKET}"
WASABI_REGION="${WASABI_REGION:-us-east-1}"
WASABI_ENDPOINT="${WASABI_ENDPOINT:-https://s3.us-east-1.wasabisys.com}"
WASABI_UPLOAD_ENABLED="${WASABI_UPLOAD_ENABLED:-true}"

# Configuración del formato de nombre de backup
CONTAINER_NAME="${CONTAINER_NAME:-$(hostname)}"
MYSQL_PORT_EXT="${MYSQL_PORT_EXT:-3306}"

# ============================================
# COLORES PARA OUTPUT
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# ============================================
# FUNCIONES DE UTILIDAD
# ============================================

# Obtener lista de bases de datos de usuario (excluyendo las del sistema)
get_user_databases() {
    mysql \
        -h "$DB_HOST" \
        -P "$DB_PORT" \
        -u "$DB_USER" \
        -p"${DB_PASSWORD}" \
        -e "SHOW DATABASES WHERE \`Database\` NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys');" \
        2>/dev/null | tail -n +2
}

# Cache de database IDs (se carga una vez al inicio)
declare -A DATABASE_IDS_CACHE

# Cargar database IDs desde el endpoint
load_database_ids() {
    info "=== INICIANDO CARGA DE DATABASE IDs ==="
    info "MONITOR_API_URL: '${MONITOR_API_URL}'"
    info "MONITOR_SERVER_ID: '${MONITOR_SERVER_ID}'"
    
    if [ -z "$MONITOR_API_URL" ] || [ -z "$MONITOR_SERVER_ID" ]; then
        warning "Sistema de monitoreo no configurado completamente"
        return 1
    fi
    
    # Verificar si jq está instalado
    if ! command -v jq &> /dev/null; then
        warning "jq no está instalado, no se pueden cargar IDs de bases de datos"
        return 1
    fi
    
    info "Obteniendo IDs de bases de datos desde el servidor..."
    
    # Usar el puerto externo para identificar el servidor
    # El servidor está registrado con la IP del host y el puerto externo
    local port="${MYSQL_PORT_EXT:-3306}"
    
    # Intentar obtener la configuración por serverId si está disponible
    if [ -n "$MONITOR_SERVER_ID" ]; then
        info "Consultando: ${MONITOR_API_URL}/database-servers/${MONITOR_SERVER_ID}"
        local response=$(curl -s -X GET "${MONITOR_API_URL}/database-servers/${MONITOR_SERVER_ID}" \
            --max-time 10 2>&1)
        info "Response status: $?"
        info "Response (primeros 500 chars): ${response:0:500}"
    else
        warning "MONITOR_SERVER_ID no configurado, no se pueden cargar IDs de bases de datos"
        return 1
    fi
    
    if [ $? -eq 0 ]; then
        # Parsear respuesta y llenar cache
        # El endpoint devuelve { id, name, ..., databases: [...] }
        local db_count=$(echo "$response" | jq -r '.databases | length' 2>/dev/null)
        info "db_count parseado: '$db_count'"
        
        # Validar que db_count es un número
        if [[ ! "$db_count" =~ ^[0-9]+$ ]]; then
            warning "Respuesta del servidor no válida (db_count no es un número): $db_count"
            warning "Response completo: $response"
            return 1
        fi
        
        if [ "$db_count" -gt 0 ]; then
            for i in $(seq 0 $((db_count - 1))); do
                local db_name=$(echo "$response" | jq -r ".databases[$i].databaseName" 2>/dev/null)
                local db_id=$(echo "$response" | jq -r ".databases[$i].id" 2>/dev/null)
                
                if [ -n "$db_name" ] && [ "$db_name" != "null" ] && [ -n "$db_id" ] && [ "$db_id" != "null" ]; then
                    DATABASE_IDS_CACHE["$db_name"]="$db_id"
                    info "  - $db_name -> $db_id"
                fi
            done
            
            info "✓ Cargados ${db_count} IDs de bases de datos"
            return 0
        else
            info "No se encontraron bases de datos en el servidor"
            return 0
        fi
    else
        warning "Error al conectar con el servidor de monitoreo"
        return 1
    fi
}

# Obtener databaseId para una base de datos específica
get_database_id() {
    local db_name="$1"
    
    # Intentar obtener del cache
    if [ -n "${DATABASE_IDS_CACHE[$db_name]}" ]; then
        echo "${DATABASE_IDS_CACHE[$db_name]}"
        return 0
    fi
    
    # Fallback: intentar obtener de variable de entorno (compatibilidad)
    local var_name="DBID_${db_name}"
    if [ -n "${!var_name}" ]; then
        echo "${!var_name}"
        return 0
    fi
    
    # No encontrado
    echo ""
    return 1
}

# ============================================
# FUNCIONES DE WASABI S3
# ============================================

# Limpiar backups antiguos en Wasabi manteniendo solo los últimos 7
cleanup_wasabi_backups() {
    local db_name="$1"
    local retention_count=7
    
    if [ "$WASABI_UPLOAD_ENABLED" != "true" ]; then
        return 0
    fi
    
    local backup_pattern="${CONTAINER_NAME}-${MYSQL_PORT_EXT}-${db_name}-*.sql.gz"
    
    log "Limpiando backups antiguos en Wasabi (manteniendo últimos $retention_count)..."
    
    # Listar todos los backups de esta BD ordenados por fecha
    local all_backups=$(aws s3 ls "s3://${WASABI_BUCKET}/${CONTAINER_NAME}-${MYSQL_PORT_EXT}-${db_name}-" \
        --endpoint-url="$WASABI_ENDPOINT" \
        --region="$WASABI_REGION" 2>/dev/null | grep "\.sql\.gz$" | sort -k1,2 -r)
    
    local backup_count=$(echo "$all_backups" | wc -l)
    
    if [ "$backup_count" -gt "$retention_count" ]; then
        info "Encontrados $backup_count backups, eliminando $(($backup_count - $retention_count)) antiguos..."
        
        local backups_to_delete=$(echo "$all_backups" | tail -n +$(($retention_count + 1)))
        
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                local old_file=$(echo "$line" | awk '{print $4}')
                if [ -n "$old_file" ]; then
                    aws s3 rm "s3://${WASABI_BUCKET}/${old_file}" \
                        --endpoint-url="$WASABI_ENDPOINT" \
                        --region="$WASABI_REGION" >/dev/null 2>&1
                fi
            fi
        done <<< "$backups_to_delete"
        
        log "Limpieza en Wasabi completada. Mantenidos: $retention_count backups"
    fi
}

# Subir archivo a Wasabi S3
upload_to_wasabi() {
    local backup_file="$1"
    local db_name="$2"
    
    if [ "$WASABI_UPLOAD_ENABLED" != "true" ]; then
        info "Upload a Wasabi está deshabilitado"
        return 0
    fi
    
    if [ -z "$WASABI_ACCESS_KEY" ] || [ -z "$WASABI_SECRET_KEY" ] || [ -z "$WASABI_BUCKET" ]; then
        warning "Credenciales de Wasabi no configuradas, omitiendo upload"
        return 1
    fi
    
    if ! command -v aws &> /dev/null; then
        warning "AWS CLI no instalado, omitiendo upload a Wasabi"
        return 1
    fi
    
    # Construir nombre del archivo en S3
    local timestamp=$(basename "$backup_file" | grep -oE '[0-9]{8}_[0-9]{6}' || date +'%Y%m%d_%H%M%S')
    local formatted_timestamp=$(echo "$timestamp" | sed 's/_/-/')
    local s3_key="${CONTAINER_NAME}-${MYSQL_PORT_EXT}-${db_name}-${formatted_timestamp}.sql.gz"
    
    # Guardar la ruta de S3 en una variable global para usarla después
    WASABI_S3_PATH="s3://${WASABI_BUCKET}/${s3_key}"
    
    # Configurar credenciales AWS temporalmente
    local aws_config_dir=$(mktemp -d)
    trap "rm -rf $aws_config_dir" RETURN
    
    cat > "$aws_config_dir/credentials" << EOF
[default]
aws_access_key_id = $WASABI_ACCESS_KEY
aws_secret_access_key = $WASABI_SECRET_KEY
EOF
    
    cat > "$aws_config_dir/config" << EOF
[default]
region = $WASABI_REGION
EOF
    
    export AWS_CONFIG_FILE="$aws_config_dir/config"
    export AWS_SHARED_CREDENTIALS_FILE="$aws_config_dir/credentials"
    
    local file_size=$(du -h "$backup_file" | cut -f1)
    info "Subiendo a Wasabi: $backup_file ($file_size)"
    info "Destino: s3://$WASABI_BUCKET/$s3_key"
    
    if aws s3 cp "$backup_file" "s3://$WASABI_BUCKET/$s3_key" \
        --endpoint-url="$WASABI_ENDPOINT" \
        --region="$WASABI_REGION" \
        --storage-class STANDARD 2>&1; then
        
        log "✓ Upload a Wasabi completado exitosamente"
        
        # Verificar que el archivo existe
        if aws s3 ls "s3://${WASABI_BUCKET}/$s3_key" \
            --endpoint-url="$WASABI_ENDPOINT" \
            --region="$WASABI_REGION" > /dev/null 2>&1; then
            
            # Limpiar backups antiguos
            cleanup_wasabi_backups "$db_name"
            return 0
        else
            warning "No se pudo verificar el archivo en Wasabi"
            return 0
        fi
    else
        error "✗ Falló el upload a Wasabi"
        return 1
    fi
}

# ============================================
# FUNCIONES DE NOTIFICACIÓN AL SISTEMA
# ============================================

# Enviar notificación al sistema de monitoreo
send_notification() {
    local payload="$1"
    
    if [ -z "$MONITOR_API_URL" ]; then
        warning "Sistema de monitoreo no configurado (MONITOR_API_URL faltante)"
        return 0
    fi
    
    info "Enviando notificación al sistema de monitoreo..."
    
    local response
    local http_code
    
    # Construir comando curl con headers correctos
    if [ -n "$MONITOR_API_KEY" ]; then
        response=$(curl -s -w "\n%{http_code}" -X POST "${MONITOR_API_URL}/backup-logs" \
            -H "Content-Type: application/json" \
            -H "X-API-Key: ${MONITOR_API_KEY}" \
            -d "$payload" \
            --max-time 30 \
            --retry 3 \
            --retry-delay 5 \
            --connect-timeout 10 2>&1)
    else
        response=$(curl -s -w "\n%{http_code}" -X POST "${MONITOR_API_URL}/backup-logs" \
            -H "Content-Type: application/json" \
            -d "$payload" \
            --max-time 30 \
            --retry 3 \
            --retry-delay 5 \
            --connect-timeout 10 2>&1)
    fi
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
        log "✓ Notificación enviada exitosamente (HTTP $http_code)"
        return 0
    elif [ "$http_code" = "000" ]; then
        warning "⚠ No se pudo conectar al sistema de monitoreo (posible problema de red)"
        return 0  # No fallar el proceso por error de conexión
    else
        warning "⚠ Error al enviar notificación (HTTP $http_code)"
        warning "Response: $body"
        return 0  # No fallar el proceso por error de notificación
    fi
}

# ============================================
# FUNCIONES DE BACKUP
# ============================================

# Realizar backup de una base de datos
backup_database() {
    local db_name="$1"
    local start_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local start_timestamp=$(date +%s)
    
    log "════════════════════════════════════════════════"
    log "INICIANDO BACKUP: $db_name"
    log "════════════════════════════════════════════════"
    
    # Generar timestamp único para este backup específico
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/backup_${db_name}_${backup_timestamp}.sql"
    local wasabi_uploaded=false
    local wasabi_error=""
    local notification_sent=false
    local notification_error=""
    
    # Ejecutar mysqldump
    if mysqldump \
        -h "$DB_HOST" \
        -P "$DB_PORT" \
        -u "$DB_USER" \
        -p"${DB_PASSWORD}" \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        "$db_name" > "$backup_file" 2>/dev/null; then
        
        # Backup exitoso - comprimir
        local uncompressed_size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file" 2>/dev/null)
        local backup_file_gz="${backup_file}.gz"
        
        # Eliminar archivo .gz existente si existe para evitar conflictos
        rm -f "$backup_file_gz"
        
        # Asegurar que todos los datos estén escritos en disco
        sync
        sleep 0.5
        
        # Comprimir el archivo
        gzip "$backup_file"
        
        local compressed_size=$(stat -c%s "$backup_file_gz" 2>/dev/null || stat -f%z "$backup_file_gz" 2>/dev/null)
        # Usar awk en lugar de bc para calcular tamaño en MB
        local compressed_size_mb=$(awk "BEGIN {printf \"%.2f\", $compressed_size / 1024 / 1024}")
        # Usar awk en lugar de bc para calcular ratio de compresión
        local compression_ratio=0
        if [ -n "$uncompressed_size" ] && [ "$uncompressed_size" -gt 0 ]; then
            compression_ratio=$(awk "BEGIN {printf \"%.4f\", $compressed_size / $uncompressed_size}")
        fi
        
        local end_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        local end_timestamp=$(date +%s)
        local duration=$((end_timestamp - start_timestamp))
        
        log "✓ Backup creado: ${backup_file_gz} (${compressed_size_mb} MB)"
        
        # Subir a Wasabi
        local wasabi_path=""
        if upload_to_wasabi "$backup_file_gz" "$db_name"; then
            wasabi_uploaded=true
            wasabi_path="$WASABI_S3_PATH"
            # Borrar archivo local después de subir exitosamente
            rm -f "$backup_file_gz"
            info "✓ Archivo local eliminado después de subir a Wasabi"
        else
            wasabi_error="Upload failed"
        fi
        
        # Preparar y enviar notificación al sistema
        local database_id=$(get_database_id "$db_name")
        local hostname=$(hostname)
        local mariadb_version=$(mysql -V | awk '{print $5}' | sed 's/,//')
        
        info "Preparando notificación para '$db_name':"
        info "  database_id: '${database_id}'"
        info "  MONITOR_SERVER_ID: '${MONITOR_SERVER_ID}'"
        
        # Solo enviar notificación si tenemos databaseId y serverId
        if [ -n "$database_id" ] && [ -n "$MONITOR_SERVER_ID" ]; then
            local payload=$(cat <<EOF
{
  "databaseId": "${database_id}",
  "serverId": "${MONITOR_SERVER_ID}",
  "backupType": "full",
  "status": "success",
  "startedAt": "${start_time}",
  "completedAt": "${end_time}",
  "duration": ${duration},
  "backupSize": ${compressed_size},
  "backupPath": "${wasabi_path}",
  "compressionRatio": ${compression_ratio},
  "source": "container",
  "metadata": {
    "hostname": "${hostname}",
    "mariadbVersion": "${mariadb_version}",
    "databaseName": "${db_name}",
    "uncompressedSize": ${uncompressed_size},
    "wasabiUploaded": ${wasabi_uploaded},
    $(if [ -n "$wasabi_error" ]; then echo "\"wasabiError\": \"${wasabi_error}\","; fi)
    "retentionDays": ${RETENTION_DAYS}
  }
}
EOF
)
            
            if send_notification "$payload"; then
                notification_sent=true
            else
                notification_error="Failed to send notification"
            fi
        else
            warning "⚠ No se envió notificación (databaseId o serverId no configurados)"
        fi
        
        log "✓ Backup de '$db_name' completado (${duration}s)"
        [ "$wasabi_uploaded" = true ] && log "  ✓ Subido a Wasabi" || warning "  ⚠ No se subió a Wasabi"
        [ "$notification_sent" = true ] && log "  ✓ Notificación enviada" || warning "  ⚠ No se envió notificación"
        
        return 0
        
    else
        # Backup fallido
        local end_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        local end_timestamp=$(date +%s)
        local duration=$((end_timestamp - start_timestamp))
        
        local error_msg=$(mysqldump \
            -h "$DB_HOST" \
            -P "$DB_PORT" \
            -u "$DB_USER" \
            -p"${DB_PASSWORD}" \
            "$db_name" 2>&1 | tail -5)
        
        error "✗ Falló el backup de '$db_name'"
        error "Error: $error_msg"
        
        rm -f "$backup_file" 2>/dev/null || true
        
        # Notificar fallo al sistema
        local database_id=$(get_database_id "$db_name")
        local hostname=$(hostname)
        
        local payload=$(cat <<EOF
{
  "databaseId": "${database_id:-$MONITOR_DATABASE_ID}",
  "serverId": "${MONITOR_SERVER_ID}",
  "backupType": "full",
  "status": "failed",
  "startedAt": "${start_time}",
  "completedAt": "${end_time}",
  "duration": ${duration},
  "source": "container",
  "errorMessage": "Backup failed",
  "errorDetails": {
    "error": "${error_msg}",
    "hostname": "${hostname}",
    "databaseName": "${db_name}"
  },
  "metadata": {
    "hostname": "${hostname}",
    "databaseName": "${db_name}"
  }
}
EOF
)
        
        send_notification "$payload"
        
        return 1
    fi
}

# ============================================
# LIMPIEZA DE BACKUPS ANTIGUOS
# ============================================

cleanup_local_backups() {
    log "Limpiando backups locales antiguos (más de $RETENTION_DAYS días)..."
    local deleted_count=$(find "$BACKUP_DIR" -name "backup_*.sql.gz" -mtime +"$RETENTION_DAYS" -print -delete 2>/dev/null | wc -l)
    log "Backups locales eliminados: $deleted_count"
}

# ============================================
# MAIN
# ============================================

main() {
    log "═══════════════════════════════════════════════════════════════"
    log "BACKUP COMPLETO - ADN SOFTWARE"
    log "═══════════════════════════════════════════════════════════════"
    log "Inicio: $(date)"
    log "Directorio: $BACKUP_DIR"
    log "Retención local: $RETENTION_DAYS días"
    log "Wasabi S3: $([ "$WASABI_UPLOAD_ENABLED" = "true" ] && echo "Habilitado" || echo "Deshabilitado")"
    log "Notificaciones: $([ -n "$MONITOR_API_URL" ] && echo "Habilitado" || echo "Deshabilitado")"
    log "═══════════════════════════════════════════════════════════════"
    echo ""
    
    # Crear directorio de backups si no existe
    mkdir -p "$BACKUP_DIR"
    
    # Cargar IDs de bases de datos desde el servidor (si está configurado)
    load_database_ids || warning "Continuando sin IDs de bases de datos actualizados"
    echo ""
    
    # Obtener lista de bases de datos de usuario
    local databases=$(get_user_databases)
    
    if [ -z "$databases" ]; then
        warning "No se encontraron bases de datos de usuario para respaldar"
        exit 0
    fi
    
    info "Bases de datos encontradas:"
    echo "$databases" | while read -r db; do
        info "  - $db"
    done
    echo ""
    
    # Variables para resumen
    local total_dbs=$(echo "$databases" | wc -l)
    local successful_backups=0
    local failed_backups=0
    
    # Procesar cada base de datos
    for db_name in $databases; do
        if [ -n "$db_name" ]; then
            if backup_database "$db_name"; then
                ((successful_backups++))
            else
                ((failed_backups++))
            fi
            echo ""
        fi
    done
    
    # Limpiar backups antiguos locales
    cleanup_local_backups
    
    # Resumen final
    local total_backups=$(find "$BACKUP_DIR" -name "backup_*.sql.gz" 2>/dev/null | wc -l)
    
    log "═══════════════════════════════════════════════════════════════"
    log "RESUMEN FINAL"
    log "═══════════════════════════════════════════════════════════════"
    log "Total bases de datos: $total_dbs"
    log "Exitosos: $successful_backups"
    if [ $failed_backups -gt 0 ]; then
        error "Fallidos: $failed_backups"
    fi
    log "Backups totales en disco: $total_backups"
    log "Fin: $(date)"
    log "═══════════════════════════════════════════════════════════════"
    
    if [ $failed_backups -gt 0 ]; then
        exit 1
    fi
    
    log "✓ Proceso completado exitosamente"
    exit 0
}

main "$@"
