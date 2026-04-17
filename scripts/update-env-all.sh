#!/bin/bash

###############################################################################
# Script para actualizar el .env de todos los contenedores MariaDB
# en una ruta específica.
#
# Uso:
#   ./update-env-all.sh <ruta_contenedores>
#
# Ejemplo:
#   ./update-env-all.sh /var/docker-data/mariadb
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

# Validar argumento
if [ $# -lt 1 ]; then
    error "Uso: $0 <ruta_contenedores>"
    error "Ejemplo: $0 /var/docker-data/mariadb"
    exit 1
fi

BASE_PATH="$1"

# Verificar que la ruta existe
if [ ! -d "$BASE_PATH" ]; then
    error "La ruta no existe: $BASE_PATH"
    exit 1
fi

log "Procesando contenedores en: $BASE_PATH"

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

# Función para verificar si el .env ya tiene la configuración nueva
has_new_config() {
    local env_file="$1"
    
    if [ ! -f "$env_file" ]; then
        return 1
    fi
    
    # Verificar si ya tiene alguna de las variables nuevas
    if grep -q "CONFIGURACIÓN DE TAREAS AUTOMÁTICAS" "$env_file" 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# Función para actualizar el .env
update_env() {
    local container_dir="$1"
    local container_name=$(basename "$container_dir")
    local env_file="$container_dir/.env"
    
    log "Procesando: $container_name"
    
    # Verificar si existe .env
    if [ ! -f "$env_file" ]; then
        warning "  No existe .env en $container_name, creando uno nuevo..."
        touch "$env_file"
    fi
    
    # Verificar si ya tiene la configuración nueva
    if has_new_config "$env_file"; then
        warning "  $container_name ya tiene la configuración nueva, saltando..."
        return 0
    fi
    
    # Hacer backup del .env
    local backup_file="$env_file.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$env_file" "$backup_file"
    log "  Backup creado: $(basename "$backup_file")"
    
    # Agregar la configuración nueva
    cat >> "$env_file" << 'EOF'

# ═══════════════════════════════════════════════════════════════
# CONFIGURACIÓN DE TAREAS AUTOMÁTICAS (CRON)
# ═══════════════════════════════════════════════════════════════
# Formato cron: minuto hora día-mes mes día-semana
# Ejemplos:
#   "0 2 * * *"     = Todos los días a las 2:00 AM
#   "0 */6 * * *"   = Cada 6 horas
#   "0 0,12 * * *"  = Dos veces al día (medianoche y mediodía)
# ═══════════════════════════════════════════════════════════════

# Backup automático (backup-complete.sh: todas las BDs + Wasabi + Notificación)
BACKUP_ENABLED=false
BACKUP_SCHEDULE=0 2 * * *

# Health check y reparación automática (health-check-complete.sh: todas las BDs + Reparación + Notificación)
HEALTH_CHECK_ENABLED=false
HEALTH_CHECK_SCHEDULE=0 3 * * *

# ═══════════════════════════════════════════════════════════════
# CONFIGURACIÓN DEL SISTEMA DE MONITOREO ADN
# ═══════════════════════════════════════════════════════════════
# ⚠️ NOTA: Estos valores se configuran AUTOMÁTICAMENTE al iniciar el contenedor
# mediante el auto-registro en el endpoint /api/database-servers/register
#
# Solo necesitas configurar MONITOR_API_URL. Los demás valores se obtienen
# automáticamente cuando el contenedor se inicia.
#
# Si necesitas re-configurar manualmente:
#   ./scripts/auto-configure.sh <host> <port>
#
# URL base del API del sistema de monitoreo
#MONITOR_API_URL=https://qa.sm-api.apps-adn.com/api
MONITOR_API_URL=http://localhost:4000/api
# API Key del servidor (auto-configurado por entrypoint.sh)
# Ejemplo: sk_live_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6
MONITOR_API_KEY=

# UUID del servidor (auto-configurado por entrypoint.sh)
# Ejemplo: 550e8400-e29b-41d4-a716-446655440000
MONITOR_SERVER_ID=

# ═══════════════════════════════════════════════════════════════
# CONFIGURACIÓN DE DESPLIEGUE MASIVO (deploy-update.sh)
# ═══════════════════════════════════════════════════════════════
# Ruta donde están los contenedores MariaDB en el servidor
MARIADB_CONTAINERS_PATH=/var/docker-data/mariadb

# Ruta donde se guardarán los backups de contenedores
BACKUP_PATH=/home/adn/backup/contenedores

# ═══════════════════════════════════════════════════════════════
# CONFIGURACIÓN WASABI S3 (Opcional - para upload de backups)
# ═══════════════════════════════════════════════════════════════
# Dejar en blanco si no se usará Wasabi S3
WASABI_UPLOAD_ENABLED=false
WASABI_ACCESS_KEY=0O4LJTDG9TF64N3NSQHD
WASABI_SECRET_KEY=M5crOj5KtmKYOUUaW5Je2EnztVOW7gFNlYpFXjG7
WASABI_BUCKET=adn-backups-bd
WASABI_REGION=us-east-1
WASABI_ENDPOINT=https://s3.wasabisys.com

# ═══════════════════════════════════════════════════════════════
# NOTA IMPORTANTE: IDs de Bases de Datos
# ═══════════════════════════════════════════════════════════════
# Los scripts de backup y health-check obtienen los IDs de las bases
# de datos DINÁMICAMENTE desde el servidor de monitoreo en cada ejecución.
# Ya NO es necesario mantener variables DBID_* en este archivo.
#
# Ventajas:
# - Auto-detección de nuevas bases de datos
# - No requiere reiniciar el contenedor al crear/eliminar BDs
# - Siempre sincronizado con el servidor de monitoreo
EOF
    
    success "  ✓ Configuración agregada a $container_name"
    return 0
}

# Contadores
total=0
actualizados=0
saltados=0
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
    
    # Actualizar el .env
    if update_env "$container_dir"; then
        if has_new_config "$container_dir/.env"; then
            actualizados=$((actualizados + 1))
        else
            saltados=$((saltados + 1))
        fi
    else
        errores=$((errores + 1))
    fi
done

# Resumen
echo ""
log "════════════════════════════════════════════════════════════════"
log "RESUMEN DE ACTUALIZACIÓN"
log "════════════════════════════════════════════════════════════════"
info "Total contenedores procesados: $total"
success "Actualizados: $actualizados"
if [ $saltados -gt 0 ]; then
    warning "Saltados (ya tenían config): $saltados"
fi
if [ $errores -gt 0 ]; then
    error "Errores: $errores"
fi
log "════════════════════════════════════════════════════════════════"

if [ $errores -eq 0 ]; then
    success "Proceso completado exitosamente"
    exit 0
else
    error "Proceso completado con errores"
    exit 1
fi
