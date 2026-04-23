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
#
# Este script actualiza/agrega variables específicas en el .env de cada
# contenedor. Las variables a modificar se definen en la sección
# CONFIGURACIÓN DE VARIABLES al final del script.
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

    # Verificar que docker-compose.yml contiene mariadb
    if grep -q "mariadb" "$dir/docker-compose.yml" 2>/dev/null || \
       grep -q "image: mariadb" "$dir/docker-compose.yml" 2>/dev/null || \
       [ -f "$dir/Dockerfile" ]; then
        return 0
    fi

    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURACIÓN DE VARIABLES A ACTUALIZAR/AGREGAR
# ═══════════════════════════════════════════════════════════════════════════════
# Define aquí las variables que quieres actualizar/agregar en cada .env
# Formato: "NOMBRE_VARIABLE=valor"
# Las variables que ya existan se actualizarán, las que no existan se agregarán.
# ═══════════════════════════════════════════════════════════════════════════════

declare -a ENV_VARS=(
    # Tareas automáticas (CRON)
    "BACKUP_ENABLED=true"
    "BACKUP_SCHEDULE=40 9 * * *"
    "HEALTH_CHECK_ENABLED=true"
    "HEALTH_CHECK_SCHEDULE=0 3 * * *"

    # Monitoreo
    "MONITOR_API_URL=http://192.168.10.89:4000/api"
    "MONITOR_API_KEY="
    "MONITOR_SERVER_ID="

    # Despliegue masivo
    "MARIADB_CONTAINERS_PATH=/home/aleguizamon/ADN/adn-servers-manager/docker-mariadb-tests"
    "BACKUP_PATH=/home/aleguizamon/ADN/adn-servers-manager/backups"

    # Wasabi S3
    "WASABI_UPLOAD_ENABLED=true"
    "WASABI_ACCESS_KEY=0O4LJTDG9TF64N3NSQHD"
    "WASABI_SECRET_KEY=M5crOj5KtmKYOUUaW5Je2EnztVOW7gFNlYpFXjG7"
    "WASABI_BUCKET=adn-backups-bd"
    "WASABI_REGION=us-east-1"
    "WASABI_ENDPOINT=https://s3.wasabisys.com"
)

# ═══════════════════════════════════════════════════════════════════════════════
# FUNCIONES DE MANEJO DE VARIABLES
# ═══════════════════════════════════════════════════════════════════════════════

# Función para escapar caracteres especiales en sed
escape_for_sed() {
    echo "$1" | sed 's/[&/\]/\\&/g'
}

# Función para asegurar que el archivo termine con newline
ensure_trailing_newline() {
    local file="$1"
    # Verificar si el archivo termina con newline, si no, agregarlo
    if [ -s "$file" ]; then
        local last_char=$(tail -c 1 "$file" | od -An -tx1 | tr -d ' ')
        if [ "$last_char" != "0a" ]; then
            echo "" >> "$file"
        fi
    fi
}

# Función para actualizar o agregar una variable en el .env
update_or_add_var() {
    local env_file="$1"
    local var_name="$2"
    local var_value="$3"

    # Verificar si la variable ya existe (no comentada)
    if grep -q "^${var_name}=" "$env_file" 2>/dev/null; then
        # La variable existe, actualizar su valor
        local escaped_value=$(escape_for_sed "$var_value")
        sed -i "s/^${var_name}=.*/${var_name}=${escaped_value}/" "$env_file"
        echo "updated"
    elif grep -q "^#${var_name}=" "$env_file" 2>/dev/null; then
        # La variable está comentada, agregar nueva línea al final
        ensure_trailing_newline "$env_file"
        echo "${var_name}=${var_value}" >> "$env_file"
        echo "added"
    else
        # La variable no existe, agregarla al final
        ensure_trailing_newline "$env_file"
        echo "${var_name}=${var_value}" >> "$env_file"
        echo "added"
    fi
}

# Función para verificar si el .env necesita actualización
# Retorna 0 si necesita cambios, 1 si está actualizado
needs_update() {
    local env_file="$1"

    if [ ! -f "$env_file" ]; then
        return 0
    fi

    for var_def in "${ENV_VARS[@]}"; do
        local var_name=$(echo "$var_def" | cut -d'=' -f1)
        local var_value=$(echo "$var_def" | cut -d'=' -f2-)

        # Verificar si la variable existe con el valor correcto
        if ! grep -q "^${var_name}=${var_value}$" "$env_file" 2>/dev/null; then
            # No existe o tiene valor diferente
            return 0
        fi
    done

    # Todas las variables están actualizadas
    return 1
}

# Función para contar cuántas variables se actualizarán/agregarán
count_pending_changes() {
    local env_file="$1"
    local count=0

    if [ ! -f "$env_file" ]; then
        echo "${#ENV_VARS[@]}"
        return
    fi

    for var_def in "${ENV_VARS[@]}"; do
        local var_name=$(echo "$var_def" | cut -d'=' -f1)
        local var_value=$(echo "$var_def" | cut -d'=' -f2-)

        if ! grep -q "^${var_name}=${var_value}$" "$env_file" 2>/dev/null; then
            count=$((count + 1))
        fi
    done

    echo "$count"
}

# Función para actualizar el .env
update_env() {
    local container_dir="$1"
    local container_name=$(basename "$container_dir")
    local env_file="$container_dir/.env"
    local updated_count=0
    local added_count=0

    log "Procesando: $container_name"

    # Verificar si existe .env
    if [ ! -f "$env_file" ]; then
        warning "  No existe .env en $container_name, creando uno nuevo..."
        touch "$env_file"
        # Agregar header informativo
        echo "# Configuración de MariaDB Container" >> "$env_file"
        echo "" >> "$env_file"
    fi

    # Verificar si necesita actualización
    local pending=$(count_pending_changes "$env_file")
    if [ "$pending" -eq 0 ]; then
        info "  Todas las variables están actualizadas, saltando..."
        return 0
    fi

    info "  Variables pendientes: $pending"

    # Hacer backup del .env
    local backup_file="$env_file.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$env_file" "$backup_file"
    log "  Backup creado: $(basename "$backup_file")"

    # Procesar cada variable
    for var_def in "${ENV_VARS[@]}"; do
        local var_name=$(echo "$var_def" | cut -d'=' -f1)
        local var_value=$(echo "$var_def" | cut -d'=' -f2-)

        local result=$(update_or_add_var "$env_file" "$var_name" "$var_value")

        if [ "$result" = "updated" ]; then
            updated_count=$((updated_count + 1))
        elif [ "$result" = "added" ]; then
            added_count=$((added_count + 1))
        fi
    done

    success "  ✓ Actualizadas: $updated_count, Agregadas: $added_count"
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

    # Verificar si necesita actualización antes de procesar
    env_file="$container_dir/.env"
    if ! needs_update "$env_file"; then
        saltados=$((saltados + 1))
        continue
    fi

    # Actualizar el .env
    if update_env "$container_dir"; then
        actualizados=$((actualizados + 1))
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
    warning "Saltados (ya actualizados): $saltados"
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
