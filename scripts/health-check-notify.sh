#!/bin/bash

# Script de health check para MariaDB con notificación al sistema de monitoreo
# Uso: ./health-check-notify.sh [nombre_base_datos]

# Configuración
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="root"
DB_PASSWORD="${MYSQL_ROOT_PASSWORD}"
DB_NAME="${1}"

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
        warning "El health check se completó pero no se notificó al sistema"
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

# Inicio
CHECKED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
START_MS=$(date +%s%3N)

log "════════════════════════════════════════════════"
log "INICIANDO HEALTH CHECK DE BASE DE DATOS"
log "════════════════════════════════════════════════"
log "Base de datos: $DB_NAME"
log "Hora: $CHECKED_AT"
log "════════════════════════════════════════════════"

# Verificar conectividad básica
log "Verificando conectividad a MariaDB..."
CONN_START=$(date +%s%3N)
if ! mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"${DB_PASSWORD}" -e "SELECT 1" "$DB_NAME" > /dev/null 2>&1; then
    error "✗ No se puede conectar a la base de datos"
    
    # Enviar notificación de fallo
    PAYLOAD=$(cat <<EOF
{
  "databaseId": "${MONITOR_DATABASE_ID}",
  "serverId": "${MONITOR_SERVER_ID}",
  "status": "failed",
  "checkedAt": "${CHECKED_AT}",
  "source": "container",
  "metadata": {
    "hostname": "$(hostname)",
    "databaseName": "${DB_NAME}",
    "error": "Connection failed"
  }
}
EOF
)
    send_notification "$PAYLOAD"
    exit 1
fi
CONN_END=$(date +%s%3N)
CONNECTION_TIME=$((CONN_END - CONN_START))
log "✓ Conexión exitosa (${CONNECTION_TIME}ms)"

# Obtener lista de tablas
log "Obteniendo lista de tablas..."
QUERY_START=$(date +%s%3N)
TABLES=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"${DB_PASSWORD}" -N -e "SHOW TABLES" "$DB_NAME" 2>/dev/null)
QUERY_END=$(date +%s%3N)
QUERY_TIME=$((QUERY_END - QUERY_START))

if [ -z "$TABLES" ]; then
    warning "⚠ No se encontraron tablas en la base de datos"
    TABLES_CHECKED=0
    TABLES_OK=0
    TABLES_WITH_WARNINGS=0
    TABLES_WITH_ERRORS=0
    OVERALL_STATUS="healthy"
    ISSUES_JSON="[]"
else
    # Inicializar contadores
    TABLES_CHECKED=0
    TABLES_OK=0
    TABLES_WITH_WARNINGS=0
    TABLES_WITH_ERRORS=0
    TABLES_REPAIRED=0
    ISSUES_JSON="[]"
    
    log "Verificando integridad de tablas..."
    
    # Verificar cada tabla
    while IFS= read -r table; do
        if [ -z "$table" ]; then
            continue
        fi
        
        TABLES_CHECKED=$((TABLES_CHECKED + 1))
        info "  [$TABLES_CHECKED] Verificando tabla: $table"
        
        # Ejecutar CHECK TABLE
        CHECK_RESULT=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"${DB_PASSWORD}" \
            -e "CHECK TABLE \`$table\`" "$DB_NAME" 2>/dev/null | tail -1 | awk '{print $4}')
        
        if [ "$CHECK_RESULT" = "OK" ]; then
            TABLES_OK=$((TABLES_OK + 1))
            echo -e "    ${GREEN}✓${NC} OK"
        elif [ "$CHECK_RESULT" = "warning" ]; then
            TABLES_WITH_WARNINGS=$((TABLES_WITH_WARNINGS + 1))
            warning "    ⚠ Warning detectado"
            # Agregar a issues (escapar comillas)
            table_escaped=$(echo "$table" | sed 's/"/\\"/g')
            ISSUES_JSON=$(echo "$ISSUES_JSON" | jq ". += [{\"table\": \"$table_escaped\", \"issue\": \"warning\", \"severity\": \"warning\"}]" 2>/dev/null || echo "[]")
        else
            TABLES_WITH_ERRORS=$((TABLES_WITH_ERRORS + 1))
            error "    ✗ Error: $CHECK_RESULT"
            # Agregar a issues (escapar comillas)
            table_escaped=$(echo "$table" | sed 's/"/\\"/g')
            result_escaped=$(echo "$CHECK_RESULT" | sed 's/"/\\"/g')
            ISSUES_JSON=$(echo "$ISSUES_JSON" | jq ". += [{\"table\": \"$table_escaped\", \"issue\": \"$result_escaped\", \"severity\": \"critical\"}]" 2>/dev/null || echo "[]")
        fi
    done <<< "$TABLES"
    
    # Determinar estado general
    if [ $TABLES_WITH_ERRORS -gt 0 ]; then
        OVERALL_STATUS="critical"
    elif [ $TABLES_WITH_WARNINGS -gt 0 ]; then
        OVERALL_STATUS="warning"
    else
        OVERALL_STATUS="healthy"
    fi
fi

# Calcular duración total
END_MS=$(date +%s%3N)
DURATION=$((END_MS - START_MS))

# Obtener información adicional
HOSTNAME=$(hostname)
MARIADB_VERSION=$(mysql -V | awk '{print $5}' | sed 's/,//')

# Si ISSUES_JSON está vacío o no es válido, usar array vacío
if [ -z "$ISSUES_JSON" ] || ! echo "$ISSUES_JSON" | jq empty 2>/dev/null; then
    ISSUES_JSON="[]"
fi

# Preparar payload para el sistema de monitoreo
PAYLOAD=$(cat <<EOF
{
  "databaseId": "${MONITOR_DATABASE_ID}",
  "serverId": "${MONITOR_SERVER_ID}",
  "status": "${OVERALL_STATUS}",
  "checkedAt": "${CHECKED_AT}",
  "duration": ${DURATION},
  "tablesChecked": ${TABLES_CHECKED},
  "tablesOk": ${TABLES_OK},
  "tablesWithWarnings": ${TABLES_WITH_WARNINGS},
  "tablesWithErrors": ${TABLES_WITH_ERRORS},
  "tablesRepaired": ${TABLES_REPAIRED},
  "issues": ${ISSUES_JSON},
  "connectionTime": ${CONNECTION_TIME},
  "queryTime": ${QUERY_TIME},
  "source": "container",
  "metadata": {
    "hostname": "${HOSTNAME}",
    "mariadbVersion": "${MARIADB_VERSION}",
    "databaseName": "${DB_NAME}"
  }
}
EOF
)

# Enviar notificación al sistema
send_notification "$PAYLOAD"

# Resumen
log "════════════════════════════════════════════════"
if [ "$OVERALL_STATUS" = "healthy" ]; then
    log "✓ HEALTH CHECK COMPLETADO - ESTADO: SALUDABLE"
elif [ "$OVERALL_STATUS" = "warning" ]; then
    warning "⚠ HEALTH CHECK COMPLETADO - ESTADO: ADVERTENCIAS"
else
    error "✗ HEALTH CHECK COMPLETADO - ESTADO: CRÍTICO"
fi
log "════════════════════════════════════════════════"
log "Tablas verificadas: $TABLES_CHECKED"
log "  ✓ OK: $TABLES_OK"
if [ $TABLES_WITH_WARNINGS -gt 0 ]; then
    warning "  ⚠ Con advertencias: $TABLES_WITH_WARNINGS"
fi
if [ $TABLES_WITH_ERRORS -gt 0 ]; then
    error "  ✗ Con errores: $TABLES_WITH_ERRORS"
fi
log "Tiempo de conexión: ${CONNECTION_TIME}ms"
log "Tiempo de consulta: ${QUERY_TIME}ms"
log "Duración total: ${DURATION}ms"
log "════════════════════════════════════════════════"

if [ "$OVERALL_STATUS" = "critical" ]; then
    exit 1
else
    exit 0
fi
