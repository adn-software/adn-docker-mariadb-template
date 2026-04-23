#!/bin/bash

#############################################################################
# Script de Auto-Configuración para Contenedores MariaDB (LEGACY)
# 
# ⚠️ NOTA: Este script es OPCIONAL y solo para casos especiales.
# 
# El entrypoint.sh realiza la auto-configuración automáticamente al iniciar
# el contenedor. Este script es útil solo si necesitas:
# - Re-configurar credenciales manualmente
# - Actualizar después de cambios en el servidor
#
# ✅ Los IDs de bases de datos se obtienen dinámicamente en cada ejecución
#    de backup-complete.sh y health-check-complete.sh
# ❌ Este script YA NO agrega DBID_* al .env
#
# Uso:
#   ./auto-configure.sh <host> <port> [api_url]
#
# Ejemplo:
#   ./auto-configure.sh 192.168.1.100 3309
#   ./auto-configure.sh netcup-vps1.adnsistemas.com 3309 https://sm-api.apps-adn.com/api
#############################################################################

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para logging
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Validar argumentos
if [ $# -lt 2 ]; then
    error "Uso: $0 <host> <port> [api_url]"
    error "Ejemplo: $0 192.168.1.100 3309"
    exit 1
fi

HOST="$1"
PORT="$2"
# API_URL="${3:-https://qa.sm-api.apps-adn.com/api}"
API_URL="http://localhost:4000/api"
ENV_FILE=".env"

log "Iniciando auto-configuración..."
log "Host: $HOST"
log "Puerto: $PORT"
log "API URL: $API_URL"

# Verificar que existe el archivo .env
if [ ! -f "$ENV_FILE" ]; then
    error "Archivo .env no encontrado en el directorio actual"
    exit 1
fi

# Hacer backup del .env actual
BACKUP_FILE=".env.backup.$(date +%Y%m%d_%H%M%S)"
cp "$ENV_FILE" "$BACKUP_FILE"
log "Backup creado: $BACKUP_FILE"

# Obtener configuración del servidor
log "Obteniendo configuración desde el servidor..."
log "URL: ${API_URL}/database-servers/get-config"
log "Payload: {\"host\":\"${HOST}\",\"port\":${PORT}}"

# Verificar que curl y jq están instalados
if ! command -v curl &> /dev/null; then
    error "curl no está instalado. Instálalo con: apt-get install curl"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    error "jq no está instalado. Instálalo con: apt-get install jq"
    exit 1
fi

# Hacer la petición HTTP
HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/database-servers/get-config" \
    -H "Content-Type: application/json" \
    -d "{\"host\":\"${HOST}\",\"port\":${PORT}}" \
    2>&1)

# Separar body y status code
HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tail -n1)
RESPONSE=$(echo "$HTTP_RESPONSE" | sed '$d')

log "HTTP Status: $HTTP_STATUS"
log "Response: $RESPONSE"

# Verificar status code (200 OK o 201 Created)
if [ "$HTTP_STATUS" != "200" ] && [ "$HTTP_STATUS" != "201" ]; then
    error "Error del servidor (HTTP $HTTP_STATUS):"
    
    # Intentar parsear el mensaje de error
    ERROR_MESSAGE=$(echo "$RESPONSE" | jq -r '.message // .error // "Error desconocido"' 2>/dev/null)
    if [ -n "$ERROR_MESSAGE" ] && [ "$ERROR_MESSAGE" != "null" ]; then
        error "$ERROR_MESSAGE"
    else
        error "$RESPONSE"
    fi
    
    exit 1
fi

# Parsear respuesta JSON
SERVER_ID=$(echo "$RESPONSE" | jq -r '.serverId' 2>/dev/null)
API_KEY=$(echo "$RESPONSE" | jq -r '.apiKey' 2>/dev/null)

if [ -z "$SERVER_ID" ] || [ "$SERVER_ID" = "null" ]; then
    error "No se pudo obtener el Server ID de la respuesta"
    error "Respuesta del servidor: $RESPONSE"
    exit 1
fi

success "Configuración obtenida exitosamente"
log "Server ID: $SERVER_ID"
log "API Key: ${API_KEY:0:12}..."

# Actualizar variables de monitoreo en .env
log "Actualizando archivo .env..."

# Función para actualizar o agregar variable
update_env_var() {
    local key="$1"
    local value="$2"
    
    if grep -q "^${key}=" "$ENV_FILE"; then
        # Variable existe, actualizarla
        # Escapar caracteres especiales en el valor para sed
        local escaped_value=$(printf '%s\n' "$value" | sed -e 's/[\/&]/\\&/g')
        sed -i.tmp "s|^${key}=.*|${key}=${escaped_value}|" "$ENV_FILE"
        rm -f "${ENV_FILE}.tmp"
        log "  ✓ Actualizado: $key"
    else
        # Variable no existe, agregarla
        echo "${key}=${value}" >> "$ENV_FILE"
        log "  ✓ Agregado: $key"
    fi
}

# Actualizar solo las credenciales del servidor (MONITOR_API_URL no se modifica)
update_env_var "MONITOR_API_KEY" "$API_KEY"
update_env_var "MONITOR_SERVER_ID" "$SERVER_ID"

success "Archivo .env actualizado correctamente"

# Mostrar resumen
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✓ Configuración completada${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Credenciales del servidor actualizadas:"
echo "  • MONITOR_API_KEY: ${API_KEY:0:12}..."
echo "  • MONITOR_SERVER_ID: $SERVER_ID"
echo ""
echo "  ℹ️  MONITOR_API_URL no se modificó (conserva su valor actual)"
echo ""
echo "ℹ️  Los IDs de bases de datos se obtienen dinámicamente en cada ejecución"
echo "    de backup-complete.sh y health-check-complete.sh"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
# Verificar si el contenedor está corriendo y reiniciarlo
log "Verificando estado del contenedor..."

# Obtener el nombre del contenedor desde el .env primero
CONTAINER_NAME_FROM_ENV=$(grep "^CONTAINER_NAME=" .env 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)

if [ -n "$CONTAINER_NAME_FROM_ENV" ]; then
    CONTAINER_NAME="$CONTAINER_NAME_FROM_ENV"
else
    # Fallback: obtener desde docker-compose.yml
    CONTAINER_NAME=$(grep -E '^\s*container_name:' docker-compose.yml 2>/dev/null | sed 's/.*container_name:\s*//' | tr -d '"' | tr -d "'" | xargs)
    
    # Si es una variable con default, extraer el default
    if echo "$CONTAINER_NAME" | grep -q '\${.*:-'; then
        CONTAINER_NAME=$(echo "$CONTAINER_NAME" | sed 's/.*:-\([^}]*\)}.*/\1/')
    fi
    
    # Si aún está vacío, usar el nombre de la carpeta
    if [ -z "$CONTAINER_NAME" ]; then
        CONTAINER_NAME=$(basename "$(pwd)")
    fi
fi

log "Nombre del contenedor: $CONTAINER_NAME"

# Función para ejecutar docker-compose/docker compose
run_docker_compose() {
    local cmd="$1"
    
    # Intentar con docker-compose (local)
    if docker-compose $cmd 2>/dev/null; then
        return 0
    fi
    
    # Si falla, intentar con docker compose (remoto)
    if docker compose $cmd 2>/dev/null; then
        return 0
    fi
    
    # Si ambos fallan, retornar error
    return 1
}

# Verificar si el contenedor está corriendo
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    success "Contenedor está corriendo - procediendo a reconstruir e iniciar..."
    echo ""
    
    # Reconstruir e iniciar el contenedor (preserva volúmenes/datos)
    if run_docker_compose "up -d --build"; then
        success "Contenedor reconstruido e iniciado exitosamente"
        log "Los cambios del .env y Dockerfile han sido aplicados"
    else
        error "No se pudo reconstruir e iniciar el contenedor"
        warning "Reinicio manual requerido:"
        echo "  docker-compose up -d --build  (o: docker compose up -d --build)"
    fi
else
    log "Contenedor no está corriendo - no se requiere reinicio"
    log "Para iniciar el contenedor más tarde:"
    echo "  docker-compose up -d  (o: docker compose up -d)"
fi

echo ""
log "Backup del .env anterior guardado en: $BACKUP_FILE"
