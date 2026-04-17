#!/bin/bash

###############################################################################
# Script para ejecutar auto-configure.sh en todos los contenedores MariaDB
# en una ruta específica.
#
# Uso:
#   ./auto-configure-all.sh <ruta_contenedores> <host>
#
# Ejemplo:
#   ./auto-configure-all.sh /var/docker-data/mariadb 159.195.57.30
#   ./auto-configure-all.sh /var/docker-data/mariadb 159.195.57.30 http://localhost:4000/api
###############################################################################

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Validar argumentos
if [ $# -lt 2 ]; then
    error "Uso: $0 <ruta_contenedores> <host> [api_url]"
    error "Ejemplo: $0 /var/docker-data/mariadb 159.195.57.30"
    error "Ejemplo: $0 /var/docker-data/mariadb 159.195.57.30 http://localhost:4000/api"
    exit 1
fi

BASE_PATH="$1"
HOST="$2"
API_URL="${3:-https://qa.sm-api.apps-adn.com/api}"

# Verificar que la ruta existe
if [ ! -d "$BASE_PATH" ]; then
    error "La ruta no existe: $BASE_PATH"
    exit 1
fi

# Verificar que auto-configure.sh existe
AUTO_CONFIGURE_SCRIPT="$(dirname "$0")/auto-configure.sh"
if [ ! -f "$AUTO_CONFIGURE_SCRIPT" ]; then
    error "No se encontró auto-configure.sh en: $AUTO_CONFIGURE_SCRIPT"
    exit 1
fi

log "Procesando contenedores en: $BASE_PATH"
log "Host: $HOST"
log "API URL: $API_URL"

# Función para verificar si es un contenedor MariaDB válido
is_mariadb_container() {
    local dir="$1"
    
    # Debe tener docker-compose.yml
    if [ ! -f "$dir/docker-compose.yml" ]; then
        return 1
    fi
    
    # Debe tener Dockerfile o ser un contenedor mariadb
    if [ ! -f "$dir/Dockerfile" ] && [ ! -f "$dir/docker-compose.yml" ]; then
        return 1
    fi
    
    # Verificar que docker-compose.yml contiene mariadb
    if grep -q "mariadb" "$dir/docker-compose.yml" 2>/dev/null || \
       grep -q "image: mariadb" "$dir/docker-compose.yml" 2>/dev/null || \
       [ -f "$dir/Dockerfile" ]; then
        return 0
    fi
    
    return 1
}

# Función para obtener el puerto del .env
get_port_from_env() {
    local env_file="$1"
    local port=""
    
    if [ -f "$env_file" ]; then
        port=$(grep "^MYSQL_PORT=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")
    fi
    
    echo "$port"
}

# Función para ejecutar auto-configure en un contenedor
configure_container() {
    local container_dir="$1"
    local container_name=$(basename "$container_dir")
    local env_file="$container_dir/.env"
    
    log "Procesando: $container_name"
    
    # Verificar que existe .env
    if [ ! -f "$env_file" ]; then
        warning "  No existe .env en $container_name, saltando..."
        return 1
    fi
    
    # Obtener el puerto del .env
    local port=$(get_port_from_env "$env_file")
    
    if [ -z "$port" ]; then
        warning "  No se encontró MYSQL_PORT en $env_file, saltando..."
        return 1
    fi
    
    log "  Puerto encontrado: $port"
    
    # Cambiar al directorio del contenedor para ejecutar auto-configure
    (
        cd "$container_dir" || exit 1
        
        # Ejecutar auto-configure.sh
        log "  Ejecutando auto-configure.sh $HOST $port $API_URL"
        
        if "$AUTO_CONFIGURE_SCRIPT" "$HOST" "$port" "$API_URL"; then
            success "  ✓ Configurado: $container_name"
            return 0
        else
            error "  ✗ Falló la configuración de $container_name"
            return 1
        fi
    )
}

# Contadores
total=0
exitosos=0
errores=0

# Iterar por todas las carpetas en la ruta base
for container_dir in "$BASE_PATH"/*/; do
    # Verificar si es un directorio
    if [ ! -d "$container_dir" ]; then
        continue
    fi
    
    container_name=$(basename "$container_dir")
    
    # Verificar si es un contenedor MariaDB válido
    if ! is_mariadb_container "$container_dir"; then
        warning "Saltando (no es contenedor MariaDB válido): $container_name"
        continue
    fi
    
    total=$((total + 1))
    
    # Configurar el contenedor
    if configure_container "$container_dir"; then
        exitosos=$((exitosos + 1))
    else
        errores=$((errores + 1))
    fi
done

# Resumen
echo ""
log "════════════════════════════════════════════════════════════════"
log "RESUMEN DE AUTO-CONFIGURACIÓN"
log "════════════════════════════════════════════════════════════════"
info "Total contenedores procesados: $total"
success "Exitosos: $exitosos"
if [ $errores -gt 0 ]; then
    error "Fallidos: $errores"
fi
log "════════════════════════════════════════════════════════════════"

if [ $errores -eq 0 ]; then
    success "Proceso completado exitosamente"
    exit 0
else
    error "Proceso completado con errores"
    exit 1
fi
