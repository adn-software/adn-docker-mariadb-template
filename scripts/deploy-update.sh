#!/bin/bash

# ═══════════════════════════════════════════════════════════════
# Script de Actualización Masiva de Contenedores MariaDB
# ═══════════════════════════════════════════════════════════════
# Actualiza Dockerfile, docker-compose.yml, .dockerignore y scripts
# en todos los contenedores MariaDB del servidor o en uno específico.
#
# Uso:
#   ./deploy-update.sh                    # Actualiza todos los contenedores
#   ./deploy-update.sh 3313-mora-y-garcia # Actualiza solo ese contenedor
# ═══════════════════════════════════════════════════════════════

set -e

# ═══════════════════════════════════════════════════════════════
# CONFIGURACIÓN
# ═══════════════════════════════════════════════════════════════

# Cargar variables de entorno desde .env si existe
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$TEMPLATE_DIR/.env" ]; then
    source "$TEMPLATE_DIR/.env"
fi

# Rutas configurables (con valores por defecto)
MARIADB_CONTAINERS_PATH="${MARIADB_CONTAINERS_PATH:-/var/docker-data/mariadb}"
BACKUP_PATH="${BACKUP_PATH:-/home/adn/backup/contenedores}"

# Archivos a actualizar
FILES_TO_UPDATE=(
    "Dockerfile"
    "docker-compose.yml"
    ".dockerignore"
)

# Directorio a actualizar
DIRS_TO_UPDATE=(
    "scripts"
)

# ═══════════════════════════════════════════════════════════════
# COLORES Y FUNCIONES DE LOG
# ═══════════════════════════════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${CYAN}[✓]${NC} $1"
}

# ═══════════════════════════════════════════════════════════════
# FUNCIONES AUXILIARES
# ═══════════════════════════════════════════════════════════════

# Verificar si un contenedor está corriendo
is_container_running() {
    local container_name="$1"
    docker ps --format '{{.Names}}' | grep -q "^${container_name}$"
}

# Obtener el nombre del contenedor desde docker-compose.yml
get_container_name() {
    local container_dir="$1"
    local compose_file="$container_dir/docker-compose.yml"
    
    if [ ! -f "$compose_file" ]; then
        echo ""
        return 1
    fi
    
    # Intentar obtener el nombre del contenedor
    local container_name=$(grep -E '^\s*container_name:' "$compose_file" | sed 's/.*container_name:\s*//' | tr -d '"' | tr -d "'" | xargs)
    
    if [ -z "$container_name" ]; then
        # Si no tiene container_name, usar el nombre de la carpeta
        container_name=$(basename "$container_dir")
    fi
    
    echo "$container_name"
}

# Verificar si es un directorio de contenedor MariaDB válido
is_mariadb_container() {
    local dir="$1"
    
    # Debe tener docker-compose.yml y Dockerfile
    [ -f "$dir/docker-compose.yml" ] && [ -f "$dir/Dockerfile" ]
}

# Crear backup de un contenedor
backup_container() {
    local container_dir="$1"
    local container_name=$(basename "$container_dir")
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_PATH/${container_name}_${timestamp}.tar.gz"
    
    log "Creando backup de: $container_name"
    
    # Crear directorio de backup si no existe
    mkdir -p "$BACKUP_PATH"
    
    # Crear backup comprimido
    tar -czf "$backup_file" -C "$(dirname "$container_dir")" "$container_name" 2>/dev/null || {
        error "No se pudo crear el backup de $container_name"
        return 1
    }
    
    success "Backup creado: $backup_file"
    echo "$backup_file"
}

# Crear backup de todos los contenedores
backup_all_containers() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_PATH/all_mariadb_containers_${timestamp}.tar.gz"
    
    log "Creando backup de todos los contenedores MariaDB..."
    
    # Crear directorio de backup si no existe
    mkdir -p "$BACKUP_PATH"
    
    # Crear backup comprimido de toda la carpeta
    tar -czf "$backup_file" -C "$(dirname "$MARIADB_CONTAINERS_PATH")" "$(basename "$MARIADB_CONTAINERS_PATH")" 2>/dev/null || {
        error "No se pudo crear el backup de todos los contenedores"
        return 1
    }
    
    success "Backup completo creado: $backup_file"
    echo "$backup_file"
}

# Actualizar archivos en un contenedor
update_container_files() {
    local container_dir="$1"
    local container_name=$(basename "$container_dir")
    
    log "Actualizando archivos en: $container_name"
    
    # Actualizar archivos individuales
    for file in "${FILES_TO_UPDATE[@]}"; do
        if [ -f "$TEMPLATE_DIR/$file" ]; then
            info "  Copiando $file..."
            cp "$TEMPLATE_DIR/$file" "$container_dir/$file" || {
                warning "  No se pudo copiar $file"
            }
        else
            warning "  Archivo $file no encontrado en template"
        fi
    done
    
    # Actualizar directorios
    for dir in "${DIRS_TO_UPDATE[@]}"; do
        if [ -d "$TEMPLATE_DIR/$dir" ]; then
            info "  Actualizando directorio $dir..."
            
            # Eliminar directorio antiguo si existe
            if [ -d "$container_dir/$dir" ]; then
                rm -rf "$container_dir/$dir"
            fi
            
            # Copiar directorio completo
            cp -r "$TEMPLATE_DIR/$dir" "$container_dir/$dir" || {
                warning "  No se pudo copiar directorio $dir"
            }
        else
            warning "  Directorio $dir no encontrado en template"
        fi
    done
    
    success "Archivos actualizados en: $container_name"
}

# Actualizar un contenedor específico
update_container() {
    local container_dir="$1"
    local container_name=$(get_container_name "$container_dir")
    local was_running=false
    
    if [ -z "$container_name" ]; then
        error "No se pudo obtener el nombre del contenedor de: $container_dir"
        return 1
    fi
    
    log "═══════════════════════════════════════════════════════════════"
    log "Procesando contenedor: $container_name"
    log "═══════════════════════════════════════════════════════════════"
    
    # Verificar si está corriendo
    if is_container_running "$container_name"; then
        was_running=true
        info "Contenedor está corriendo, será detenido temporalmente"
        
        # Detener contenedor
        log "Deteniendo contenedor..."
        cd "$container_dir"
        docker-compose down || {
            error "No se pudo detener el contenedor"
            return 1
        }
        success "Contenedor detenido"
    else
        info "Contenedor no está corriendo"
    fi
    
    # Actualizar archivos
    update_container_files "$container_dir"
    
    # Reconstruir e iniciar solo si estaba corriendo
    if [ "$was_running" = true ]; then
        log "Reconstruyendo e iniciando contenedor..."
        cd "$container_dir"
        docker-compose up -d --build || {
            error "No se pudo reconstruir/iniciar el contenedor"
            return 1
        }
        success "Contenedor reconstruido e iniciado"
    else
        info "Contenedor no será iniciado (no estaba corriendo antes)"
    fi
    
    success "Actualización completada: $container_name"
    echo ""
    
    return 0
}

# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

main() {
    local target_container="$1"
    
    log "════════════════════════════════════════════════════════════════"
    log "ACTUALIZACIÓN DE CONTENEDORES MARIADB"
    log "════════════════════════════════════════════════════════════════"
    log "Template: $TEMPLATE_DIR"
    log "Contenedores: $MARIADB_CONTAINERS_PATH"
    log "Backups: $BACKUP_PATH"
    log "════════════════════════════════════════════════════════════════"
    echo ""
    
    # Verificar que existe el directorio de contenedores
    if [ ! -d "$MARIADB_CONTAINERS_PATH" ]; then
        error "No existe el directorio de contenedores: $MARIADB_CONTAINERS_PATH"
        exit 1
    fi
    
    # Verificar que existe el template
    if [ ! -d "$TEMPLATE_DIR" ]; then
        error "No existe el directorio template: $TEMPLATE_DIR"
        exit 1
    fi
    
    # Verificar archivos necesarios en template
    local missing_files=false
    for file in "${FILES_TO_UPDATE[@]}"; do
        if [ ! -f "$TEMPLATE_DIR/$file" ]; then
            error "Archivo no encontrado en template: $file"
            missing_files=true
        fi
    done
    
    for dir in "${DIRS_TO_UPDATE[@]}"; do
        if [ ! -d "$TEMPLATE_DIR/$dir" ]; then
            error "Directorio no encontrado en template: $dir"
            missing_files=true
        fi
    done
    
    if [ "$missing_files" = true ]; then
        error "Faltan archivos/directorios necesarios en el template"
        exit 1
    fi
    
    # Modo: contenedor específico o todos
    if [ -n "$target_container" ]; then
        # Actualizar contenedor específico
        local container_dir="$MARIADB_CONTAINERS_PATH/$target_container"
        
        if [ ! -d "$container_dir" ]; then
            error "No existe el contenedor: $target_container"
            exit 1
        fi
        
        if ! is_mariadb_container "$container_dir"; then
            error "El directorio no parece ser un contenedor MariaDB válido: $target_container"
            exit 1
        fi
        
        # Backup del contenedor específico
        backup_container "$container_dir"
        echo ""
        
        # Actualizar
        update_container "$container_dir"
        
    else
        # Actualizar todos los contenedores
        log "Modo: Actualización masiva de todos los contenedores"
        echo ""
        
        # Backup de todos los contenedores
        backup_all_containers
        echo ""
        
        # Buscar y actualizar todos los contenedores
        local total=0
        local success_count=0
        local failed_count=0
        
        for container_dir in "$MARIADB_CONTAINERS_PATH"/*; do
            if [ ! -d "$container_dir" ]; then
                continue
            fi
            
            # Verificar si es un contenedor MariaDB válido
            if ! is_mariadb_container "$container_dir"; then
                warning "Saltando (no es contenedor MariaDB válido): $(basename "$container_dir")"
                continue
            fi
            
            total=$((total + 1))
            
            if update_container "$container_dir"; then
                success_count=$((success_count + 1))
            else
                failed_count=$((failed_count + 1))
            fi
        done
        
        # Resumen
        log "════════════════════════════════════════════════════════════════"
        log "RESUMEN DE ACTUALIZACIÓN"
        log "════════════════════════════════════════════════════════════════"
        info "Total procesados: $total"
        success "Exitosos: $success_count"
        if [ $failed_count -gt 0 ]; then
            error "Fallidos: $failed_count"
        fi
        log "════════════════════════════════════════════════════════════════"
    fi
    
    success "Proceso completado"
}

# Ejecutar main
main "$@"
