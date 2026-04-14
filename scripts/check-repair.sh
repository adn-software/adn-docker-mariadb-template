#!/bin/bash

# Script de verificación y reparación automática de tablas MariaDB
# Uso: ./check-repair.sh [nombre_bd] (si no se especifica, verifica todas las BDs de usuario)

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuración de conexión a MariaDB
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-${MYSQL_ROOT_PASSWORD}}"

# Configuración de logs
LOG_DIR="${LOG_DIR:-/var/log/mysql-maintenance}"
LOG_FILE="${LOG_DIR}/check-repair-$(date +%Y%m%d_%H%M%S).log"
SUMMARY_FILE="${LOG_DIR}/check-repair-summary.log"

# Contadores para el resumen
TOTAL_DATABASES=0
TOTAL_TABLES=0
TABLES_CHECKED=0
TABLES_OK=0
TABLES_REPAIRED=0
TABLES_FAILED=0

# Crear directorio de logs si no existe
mkdir -p "$LOG_DIR"

# Funciones de logging
log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo -e "${GREEN}${message}${NC}"
    echo "$message" >> "$LOG_FILE"
}

error() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $1"
    echo -e "${RED}${message}${NC}" >&2
    echo "$message" >> "$LOG_FILE"
}

warning() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] [WARNING] $1"
    echo -e "${YELLOW}${message}${NC}"
    echo "$message" >> "$LOG_FILE"
}

info() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $1"
    echo -e "${BLUE}${message}${NC}"
    echo "$message" >> "$LOG_FILE"
}

# Función para verificar conexión a MariaDB
check_connection() {
    if ! mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"${DB_PASSWORD}" -e "SELECT 1" >/dev/null 2>&1; then
        error "No se puede conectar a MariaDB en ${DB_HOST}:${DB_PORT}"
        return 1
    fi
    return 0
}

# Función para obtener lista de bases de datos de usuario (excluyendo sistema)
get_user_databases() {
    mysql \
        -h "$DB_HOST" \
        -P "$DB_PORT" \
        -u "$DB_USER" \
        -p"${DB_PASSWORD}" \
        -e "SHOW DATABASES WHERE \`Database\` NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys');" \
        2>/dev/null | tail -n +2
}

# Función para obtener lista de tablas de una base de datos
get_tables() {
    local DB_NAME="$1"
    mysql \
        -h "$DB_HOST" \
        -P "$DB_PORT" \
        -u "$DB_USER" \
        -p"${DB_PASSWORD}" \
        -e "SHOW TABLES FROM \`${DB_NAME}\`;" \
        2>/dev/null | tail -n +2
}

# Función para verificar una tabla específica
check_table() {
    local DB_NAME="$1"
    local TABLE_NAME="$2"
    
    local RESULT=$(mysql \
        -h "$DB_HOST" \
        -P "$DB_PORT" \
        -u "$DB_USER" \
        -p"${DB_PASSWORD}" \
        -e "CHECK TABLE \`${DB_NAME}\`.\`${TABLE_NAME}\` MEDIUM;" \
        2>/dev/null | tail -1)
    
    echo "$RESULT"
}

# Función para reparar una tabla específica
repair_table() {
    local DB_NAME="$1"
    local TABLE_NAME="$2"
    
    local RESULT=$(mysql \
        -h "$DB_HOST" \
        -P "$DB_PORT" \
        -u "$DB_USER" \
        -p"${DB_PASSWORD}" \
        -e "REPAIR TABLE \`${DB_NAME}\`.\`${TABLE_NAME}\`;" \
        2>/dev/null | tail -1)
    
    echo "$RESULT"
}

# Función para verificar y reparar (si es necesario) una tabla
verify_and_repair_table() {
    local DB_NAME="$1"
    local TABLE_NAME="$2"
    
    ((TABLES_CHECKED++))
    
    info "Verificando tabla: ${DB_NAME}.${TABLE_NAME}"
    
    local CHECK_RESULT=$(check_table "$DB_NAME" "$TABLE_NAME")
    local STATUS=$(echo "$CHECK_RESULT" | awk -F'\t' '{print $4}')
    local MSG_TYPE=$(echo "$CHECK_RESULT" | awk -F'\t' '{print $3}')
    
    if [[ "$STATUS" == "OK" ]] && [[ "$MSG_TYPE" != "Error" ]]; then
        log "✓ Tabla ${DB_NAME}.${TABLE_NAME} está OK"
        ((TABLES_OK++))
        return 0
    else
        warning "⚠ Tabla ${DB_NAME}.${TABLE_NAME} necesita reparación: $STATUS"
        
        # Intentar reparar la tabla
        info "Reparando tabla: ${DB_NAME}.${TABLE_NAME}..."
        local REPAIR_RESULT=$(repair_table "$DB_NAME" "$TABLE_NAME")
        local REPAIR_STATUS=$(echo "$REPAIR_RESULT" | awk -F'\t' '{print $4}')
        
        if [[ "$REPAIR_STATUS" == "OK" ]] || [[ "$REPAIR_STATUS" == *"repaired"* ]]; then
            log "✅ Tabla ${DB_NAME}.${TABLE_NAME} reparada exitosamente"
            ((TABLES_REPAIRED++))
            return 0
        else
            error "❌ No se pudo reparar la tabla ${DB_NAME}.${TABLE_NAME}: $REPAIR_STATUS"
            ((TABLES_FAILED++))
            return 1
        fi
    fi
}

# Función para verificar una base de datos completa
verify_database() {
    local DB_NAME="$1"
    
    ((TOTAL_DATABASES++))
    log "=========================================="
    log "Iniciando verificación de base de datos: $DB_NAME"
    log "=========================================="
    
    # Obtener lista de tablas
    local TABLES=$(get_tables "$DB_NAME")
    local DB_TABLE_COUNT=$(echo "$TABLES" | wc -l)
    ((TOTAL_TABLES += DB_TABLE_COUNT))
    
    info "Encontradas $DB_TABLE_COUNT tablas en $DB_NAME"
    
    # Verificar cada tabla
    while IFS= read -r TABLE; do
        if [ -n "$TABLE" ]; then
            verify_and_repair_table "$DB_NAME" "$TABLE"
        fi
    done <<< "$TABLES"
    
    log "Finalizada verificación de: $DB_NAME"
    log ""
}

# Función para generar resumen final
generate_summary() {
    log "=========================================="
    log "RESUMEN FINAL DE VERIFICACIÓN Y REPARACIÓN"
    log "=========================================="
    log "Bases de datos verificadas: $TOTAL_DATABASES"
    log "Total de tablas encontradas: $TOTAL_TABLES"
    log "Tablas verificadas: $TABLES_CHECKED"
    log "Tablas OK (sin problemas): $TABLES_OK"
    log "Tablas reparadas: $TABLES_REPAIRED"
    log "Tablas con errores (no reparadas): $TABLES_FAILED"
    log "=========================================="
    log "Archivo de log: $LOG_FILE"
    log "=========================================="
    
    # Guardar resumen en archivo de resumen
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] BDs: $TOTAL_DATABASES | Tablas: $TOTAL_TABLES | OK: $TABLES_OK | Reparadas: $TABLES_REPAIRED | Fallidas: $TABLES_FAILED | Log: $LOG_FILE" >> "$SUMMARY_FILE"
    
    # Mantener solo los últimos 30 registros en el archivo de resumen
    if [ -f "$SUMMARY_FILE" ]; then
        tail -n 30 "$SUMMARY_FILE" > "$SUMMARY_FILE.tmp" && mv "$SUMMARY_FILE.tmp" "$SUMMARY_FILE"
    fi
}

# Función principal
main() {
    local TARGET_DB="${1:-}"
    
    log "=========================================="
    log "INICIANDO VERIFICACIÓN DE TABLAS MARIADB"
    log "Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
    log "=========================================="
    
    # Verificar conexión a MariaDB
    if ! check_connection; then
        error "No se pudo establecer conexión con MariaDB. Abortando."
        exit 1
    fi
    
    log "Conexión a MariaDB establecida correctamente"
    
    # Si se especificó una BD específica, verificar solo esa
    if [ -n "$TARGET_DB" ]; then
        info "Modo: Verificación de base de datos específica: $TARGET_DB"
        
        # Verificar que la BD existe
        if ! mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"${DB_PASSWORD}" -e "USE \`${TARGET_DB}\`;" 2>/dev/null; then
            error "La base de datos '$TARGET_DB' no existe o no es accesible"
            exit 1
        fi
        
        verify_database "$TARGET_DB"
    else
        info "Modo: Verificación de todas las bases de datos de usuario"
        
        # Obtener lista de bases de datos
        local DATABASES=$(get_user_databases)
        
        if [ -z "$DATABASES" ]; then
            warning "No se encontraron bases de datos de usuario para verificar"
            exit 0
        fi
        
        info "Bases de datos encontradas:"
        while IFS= read -r DB; do
            if [ -n "$DB" ]; then
                info "  - $DB"
            fi
        done <<< "$DATABASES"
        
        log ""
        
        # Verificar cada base de datos
        while IFS= read -r DB; do
            if [ -n "$DB" ]; then
                verify_database "$DB"
            fi
        done <<< "$DATABASES"
    fi
    
    # Generar resumen final
    generate_summary
    
    # Retornar código de error si hubo tablas fallidas
    if [ $TABLES_FAILED -gt 0 ]; then
        error "El proceso completó pero con $TABLES_FAILED tabla(s) que no pudieron ser reparadas"
        exit 1
    else
        log "Proceso completado exitosamente"
        exit 0
    fi
}

# Ejecutar función principal
main "$@"
