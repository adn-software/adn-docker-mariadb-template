#!/bin/bash

# Script completo de health check para MariaDB
# - Verifica todas las bases de datos de usuario (no del sistema)
# - Intenta reparar tablas con problemas
# - Notifica al sistema de monitoreo ADN
#
# Uso: ./health-check-complete.sh

# NO usamos set -e porque queremos que continúe con todas las BDs aunque una falle

# Cargar variables de entorno si existen (para cron)
if [ -f /etc/cron.d/adn-backup-env ]; then
    set -a
    source /etc/cron.d/adn-backup-env
    set +a
fi

# ============================================
# CONFIGURACIÓN
# ============================================
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-${MYSQL_ROOT_PASSWORD:-${MARIADB_ROOT_PASSWORD}}}"

# Configuración del sistema de monitoreo
MONITOR_API_URL="${MONITOR_API_URL}"
MONITOR_API_KEY="${MONITOR_API_KEY}"
MONITOR_SERVER_ID="${MONITOR_SERVER_ID}"

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
# FUNCIONES DE BASE DE DATOS
# ============================================

# Verificar conexión a MariaDB
check_connection() {
    if ! mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"${DB_PASSWORD}" -e "SELECT 1" >/dev/null 2>&1; then
        error "No se puede conectar a MariaDB en ${DB_HOST}:${DB_PORT}"
        return 1
    fi
    return 0
}

# Obtener lista de bases de datos de usuario (excluyendo sistema)
get_user_databases() {
    mysql \
        -h "$DB_HOST" \
        -P "$DB_PORT" \
        -u "$DB_USER" \
        -p"${DB_PASSWORD}" \
        -e "SHOW DATABASES WHERE \`Database\` NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys');" \
        2>/dev/null | tail -n +2
}

# Obtener lista de tablas de una base de datos
get_tables() {
    local db_name="$1"
    mysql \
        -h "$DB_HOST" \
        -P "$DB_PORT" \
        -u "$DB_USER" \
        -p"${DB_PASSWORD}" \
        -e "SHOW TABLES FROM \`${db_name}\`;" \
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
    
    # Intentar obtener la configuración por serverId si está disponible
    if [ -n "$MONITOR_SERVER_ID" ]; then
        info "Consultando: ${MONITOR_API_URL}/database-servers/${MONITOR_SERVER_ID}"
        local response=$(curl -s -X GET "${MONITOR_API_URL}/database-servers/${MONITOR_SERVER_ID}" \
            --max-time 10 2>&1)
        info "Response status: $?"
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
# FUNCIONES DE NOTIFICACIÓN
# ============================================

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
        response=$(curl -s -w "\n%{http_code}" -X POST "${MONITOR_API_URL}/health-logs" \
            -H "Content-Type: application/json" \
            -H "X-API-Key: ${MONITOR_API_KEY}" \
            -d "$payload" \
            --max-time 30 \
            --retry 3 \
            --retry-delay 5 \
            --connect-timeout 10 2>&1)
    else
        response=$(curl -s -w "\n%{http_code}" -X POST "${MONITOR_API_URL}/health-logs" \
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
# FUNCIONES DE CHECK Y REPAIR
# ============================================

# Verificar una tabla específica
check_table() {
    local db_name="$1"
    local table_name="$2"
    
    local result=$(mysql \
        -h "$DB_HOST" \
        -P "$DB_PORT" \
        -u "$DB_USER" \
        -p"${DB_PASSWORD}" \
        -e "CHECK TABLE \`${db_name}\`.\`${table_name}\` MEDIUM;" \
        2>/dev/null | tail -1)
    
    echo "$result"
}

# Reparar una tabla específica
repair_table() {
    local db_name="$1"
    local table_name="$2"
    
    local result=$(mysql \
        -h "$DB_HOST" \
        -P "$DB_PORT" \
        -u "$DB_USER" \
        -p"${DB_PASSWORD}" \
        -e "REPAIR TABLE \`${db_name}\`.\`${table_name}\`;" \
        2>/dev/null | tail -1)
    
    echo "$result"
}

# Verificar y reparar una tabla
verify_and_repair_table() {
    local db_name="$1"
    local table_name="$2"
    local db_tables_checked="$3"
    local db_tables_ok="$4"
    local db_tables_repaired="$5"
    local db_tables_failed="$6"
    local db_issues="$7"
    
    # Incrementar contador
    db_tables_checked=$((db_tables_checked + 1))
    
    echo "[INFO]   Verificando tabla: ${table_name}" >&2
    
    local check_result=$(check_table "$db_name" "$table_name")
    local status=$(echo "$check_result" | awk -F'\t' '{print $4}')
    local msg_type=$(echo "$check_result" | awk -F'\t' '{print $3}')
    
    if [[ "$status" == "OK" ]] && [[ "$msg_type" != "Error" ]]; then
        echo -e "    ${GREEN}✓${NC} OK" >&2
        db_tables_ok=$((db_tables_ok + 1))
    else
        echo "[WARNING]     ⚠ Necesita reparación: $status" >&2
        
        # Intentar reparar
        echo "[INFO]     Reparando..." >&2
        local repair_result=$(repair_table "$db_name" "$table_name")
        local repair_status=$(echo "$repair_result" | awk -F'\t' '{print $4}')
        
        if [[ "$repair_status" == "OK" ]] || [[ "$repair_status" == *"repaired"* ]]; then
            echo "[INFO]     ✅ Reparada exitosamente" >&2
            db_tables_repaired=$((db_tables_repaired + 1))
        else
            echo "[ERROR]     ❌ No se pudo reparar: $repair_status" >&2
            db_tables_failed=$((db_tables_failed + 1))
            # Agregar a issues
            local table_escaped=$(echo "$table_name" | sed 's/"/\\"/g')
            local result_escaped=$(echo "$repair_status" | sed 's/"/\\"/g')
            db_issues="${db_issues}{\"table\": \"${table_escaped}\", \"issue\": \"${result_escaped}\", \"severity\": \"critical\"},"
        fi
    fi
    
    # Retornar valores actualizados
    echo "${db_tables_checked}|${db_tables_ok}|${db_tables_repaired}|${db_tables_failed}|${db_issues}"
}

# ============================================
# HEALTH CHECK DE UNA BASE DE DATOS
# ============================================

health_check_database() {
    local db_name="$1"
    local start_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local start_ms=$(date +%s%3N)
    
    log "════════════════════════════════════════════════"
    log "Health Check: ${db_name}"
    log "════════════════════════════════════════════════"
    
    # Verificar conexión a la BD
    local conn_start=$(date +%s%3N)
    if ! mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"${DB_PASSWORD}" -e "USE \`${db_name}\`;" 2>/dev/null; then
        error "✗ No se puede conectar a la base de datos ${db_name}"
        
        # Notificar fallo
        local end_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        local database_id=$(get_database_id "$db_name")
        local hostname=$(hostname)
        
        local payload=$(cat <<EOF
{
  "databaseId": "${database_id:-$MONITOR_DATABASE_ID}",
  "serverId": "${MONITOR_SERVER_ID}",
  "status": "failed",
  "checkedAt": "${start_time}",
  "source": "container",
  "metadata": {
    "hostname": "${hostname}",
    "databaseName": "${db_name}",
    "error": "Connection failed"
  }
}
EOF
)
        send_notification "$payload"
        return 1
    fi
    local conn_end=$(date +%s%3N)
    local connection_time=$((conn_end - conn_start))
    log "✓ Conexión exitosa (${connection_time}ms)"
    
    # Obtener tablas
    local tables=$(get_tables "$db_name")
    local table_count=0
    if [ -n "$tables" ]; then
        table_count=$(echo "$tables" | wc -l)
    fi
    info "Encontradas $table_count tablas"
    
    # Inicializar contadores
    local tables_checked=0
    local tables_ok=0
    local tables_repaired=0
    local tables_failed=0
    local issues=""
    
    # Verificar cada tabla
    while IFS= read -r table; do
        if [ -n "$table" ]; then
            local result=$(verify_and_repair_table "$db_name" "$table" "$tables_checked" "$tables_ok" "$tables_repaired" "$tables_failed" "$issues")
            IFS='|' read -r tables_checked tables_ok tables_repaired tables_failed issues <<< "$result"
        fi
    done <<< "$tables"
    
    # Calcular duración
    local end_ms=$(date +%s%3N)
    local duration=$((end_ms - start_ms))
    local end_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Determinar estado
    local overall_status
    if [ "${tables_failed:-0}" -gt 0 ]; then
        overall_status="critical"
    elif [ "${tables_repaired:-0}" -gt 0 ]; then
        overall_status="warning"
    else
        overall_status="healthy"
    fi
    
    # Preparar issues JSON
    local issues_json="[${issues%,}]"
    if [ -z "$issues" ]; then
        issues_json="[]"
    fi
    
    # Obtener información adicional
    local database_id=$(get_database_id "$db_name")
    local hostname=$(hostname)
    local mariadb_version=$(mysql -V | awk '{print $5}' | sed 's/,//')
    
    info "Preparando notificación para '$db_name':"
    info "  database_id: '${database_id}'"
    info "  MONITOR_SERVER_ID: '${MONITOR_SERVER_ID}'"
    info "  tables_checked: '${tables_checked}'"
    info "  tables_ok: '${tables_ok}'"
    info "  tables_repaired: '${tables_repaired}'"
    info "  tables_failed: '${tables_failed}'"
    
    # Preparar payload
    local payload=$(cat <<EOF
{
  "databaseId": "${database_id:-$MONITOR_DATABASE_ID}",
  "serverId": "${MONITOR_SERVER_ID}",
  "status": "${overall_status}",
  "checkedAt": "${start_time}",
  "duration": ${duration:-0},
  "tablesChecked": ${tables_checked:-0},
  "tablesOk": ${tables_ok:-0},
  "tablesWithWarnings": 0,
  "tablesWithErrors": ${tables_failed:-0},
  "tablesRepaired": ${tables_repaired:-0},
  "issues": ${issues_json},
  "connectionTime": ${connection_time:-0},
  "queryTime": 0,
  "source": "container",
  "metadata": {
    "hostname": "${hostname}",
    "mariadbVersion": "${mariadb_version}",
    "databaseName": "${db_name}"
  }
}
EOF
)
    
    # Enviar notificación
    local notification_sent=false
    if [ -n "$database_id" ] && [ -n "$MONITOR_SERVER_ID" ]; then
        if send_notification "$payload"; then
            notification_sent=true
        fi
    else
        warning "⚠ No se envió notificación (databaseId o serverId no configurados)"
    fi
    
    # Resumen de la BD
    log "✓ Health check de '$db_name' completado"
    log "  Tablas verificadas: ${tables_checked:-0}"
    log "  ✓ OK: ${tables_ok:-0}"
    if [ "${tables_repaired:-0}" -gt 0 ]; then
        warning "  ⚠ Reparadas: $tables_repaired"
    fi
    if [ "${tables_failed:-0}" -gt 0 ]; then
        error "  ✗ Fallidas: $tables_failed"
    fi
    log "  Estado: ${overall_status}"
    log "  Duración: ${duration}ms"
    [ "$notification_sent" = true ] && log "  ✓ Notificación enviada" || warning "  ⚠ No se envió notificación"
    
    return $tables_failed
}

# ============================================
# MAIN
# ============================================

main() {
    log "═══════════════════════════════════════════════════════════════"
    log "HEALTH CHECK COMPLETO - ADN SOFTWARE"
    log "═══════════════════════════════════════════════════════════════"
    log "Inicio: $(date)"
    log "═══════════════════════════════════════════════════════════════"
    echo ""
    
    # Verificar conexión a MariaDB
    if ! check_connection; then
        error "No se pudo conectar a MariaDB. Abortando."
        exit 1
    fi
    log "✓ Conexión a MariaDB establecida"
    echo ""
    
    # Cargar IDs de bases de datos desde el servidor (si está configurado)
    load_database_ids || warning "Continuando sin IDs de bases de datos actualizados"
    echo ""
    
    # Obtener lista de bases de datos de usuario
    local databases=$(get_user_databases)
    
    if [ -z "$databases" ]; then
        warning "No se encontraron bases de datos de usuario para verificar"
        exit 0
    fi
    
    info "Bases de datos encontradas:"
    echo "$databases" | while read -r db; do
        info "  - $db"
    done
    echo ""
    
    # Variables para resumen global
    local total_dbs=$(echo "$databases" | wc -l)
    local successful_checks=0
    local failed_checks=0
    local total_tables_checked=0
    local total_tables_ok=0
    local total_tables_repaired=0
    local total_tables_failed=0
    
    # Procesar cada base de datos
    for db_name in $databases; do
        if [ -n "$db_name" ]; then
            if health_check_database "$db_name"; then
                ((successful_checks++))
            else
                ((failed_checks++))
            fi
            echo ""
        fi
    done
    
    # Resumen final
    log "═══════════════════════════════════════════════════════════════"
    log "RESUMEN FINAL - HEALTH CHECK"
    log "═══════════════════════════════════════════════════════════════"
    log "Total bases de datos: $total_dbs"
    log "Exitosos: $successful_checks"
    if [ $failed_checks -gt 0 ]; then
        error "Con problemas: $failed_checks"
    fi
    log "Fin: $(date)"
    log "═══════════════════════════════════════════════════════════════"
    
    if [ $failed_checks -gt 0 ]; then
        exit 1
    fi
    
    log "✓ Health check completado exitosamente"
    exit 0
}

main "$@"
