#!/bin/bash

# Script completo de health check para MariaDB
# - Verifica todas las bases de datos de usuario (no del sistema)
# - Intenta reparar tablas con problemas
# - Notifica al sistema de monitoreo ADN
#
# Uso: ./health-check-complete.sh

# NO usamos set -e porque queremos que continúe con todas las BDs aunque una falle

# ============================================
# CONFIGURACIÓN
# ============================================
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-${MYSQL_ROOT_PASSWORD}}"

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

# Obtener databaseId para una base de datos
get_database_id() {
    local db_name="$1"
    local var_name="DBID_${db_name}"
    echo "${!var_name}"
}

# ============================================
# FUNCIONES DE NOTIFICACIÓN
# ============================================

send_notification() {
    local payload="$1"
    
    if [ -z "$MONITOR_API_URL" ] || [ -z "$MONITOR_API_KEY" ]; then
        warning "Sistema de monitoreo no configurado"
        return 0
    fi
    
    info "Enviando notificación al sistema de monitoreo..."
    
    local response
    local http_code
    
    response=$(curl -s -w "\n%{http_code}" -X POST "${MONITOR_API_URL}/health-logs" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: ${MONITOR_API_KEY}" \
        -d "$payload" \
        --max-time 30 \
        --retry 3 \
        --retry-delay 5 2>&1)
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
        log "✓ Notificación enviada exitosamente (HTTP $http_code)"
        return 0
    else
        error "✗ Error al enviar notificación (HTTP $http_code)"
        return 1
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
    
    info "  Verificando tabla: ${table_name}"
    
    local check_result=$(check_table "$db_name" "$table_name")
    local status=$(echo "$check_result" | awk -F'\t' '{print $4}')
    local msg_type=$(echo "$check_result" | awk -F'\t' '{print $3}')
    
    if [[ "$status" == "OK" ]] && [[ "$msg_type" != "Error" ]]; then
        echo -e "    ${GREEN}✓${NC} OK"
        db_tables_ok=$((db_tables_ok + 1))
    else
        warning "    ⚠ Necesita reparación: $status"
        
        # Intentar reparar
        info "    Reparando..."
        local repair_result=$(repair_table "$db_name" "$table_name")
        local repair_status=$(echo "$repair_result" | awk -F'\t' '{print $4}')
        
        if [[ "$repair_status" == "OK" ]] || [[ "$repair_status" == *"repaired"* ]]; then
            log "    ✅ Reparada exitosamente"
            db_tables_repaired=$((db_tables_repaired + 1))
        else
            error "    ❌ No se pudo reparar: $repair_status"
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
    local table_count=$(echo "$tables" | wc -l)
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
    if [ $tables_failed -gt 0 ]; then
        overall_status="critical"
    elif [ $tables_repaired -gt 0 ]; then
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
    
    # Preparar payload
    local payload=$(cat <<EOF
{
  "databaseId": "${database_id:-$MONITOR_DATABASE_ID}",
  "serverId": "${MONITOR_SERVER_ID}",
  "status": "${overall_status}",
  "checkedAt": "${start_time}",
  "duration": ${duration},
  "tablesChecked": ${tables_checked},
  "tablesOk": ${tables_ok},
  "tablesWithWarnings": 0,
  "tablesWithErrors": ${tables_failed},
  "tablesRepaired": ${tables_repaired},
  "issues": ${issues_json},
  "connectionTime": ${connection_time},
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
    send_notification "$payload"
    
    # Resumen de la BD
    log "Resumen de ${db_name}:"
    log "  Tablas verificadas: $tables_checked"
    log "  ✓ OK: $tables_ok"
    if [ $tables_repaired -gt 0 ]; then
        warning "  ⚠ Reparadas: $tables_repaired"
    fi
    if [ $tables_failed -gt 0 ]; then
        error "  ✗ Fallidas: $tables_failed"
    fi
    log "  Estado: ${overall_status}"
    log "  Duración: ${duration}ms"
    
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
