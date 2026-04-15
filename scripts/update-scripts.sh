#!/bin/bash

# ═══════════════════════════════════════════════════════════════
# ACTUALIZACIÓN DE SCRIPTS EN CONTENEDORES MARIADB
# ═══════════════════════════════════════════════════════════════
# Este script actualiza SOLO los scripts de backup y health check
# en todos los contenedores MariaDB sin tocar la configuración.
#
# Uso: ./update-scripts.sh [--dry-run]
#
# Este script es útil cuando haces git pull y quieres actualizar
# los scripts en todos los contenedores sin reconfigurar.
# ═══════════════════════════════════════════════════════════════

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

DRY_RUN=false

# Parsear argumentos
for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
    esac
done

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${CYAN}[SUCCESS]${NC} $1"
}

# Función para actualizar scripts en un contenedor
update_scripts_in_container() {
    local container="$1"
    
    log "Actualizando scripts en: $container"
    
    # Verificar que el contenedor está corriendo
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        warning "Contenedor no está corriendo, saltando..."
        return 1
    fi
    
    if [ "$DRY_RUN" = true ]; then
        info "[DRY-RUN] Se actualizarían 3 scripts en $container"
        return 0
    fi
    
    # Copiar scripts esenciales
    docker cp scripts/backup-complete.sh "${container}:/usr/local/bin/" || return 1
    docker cp scripts/health-check-complete.sh "${container}:/usr/local/bin/" || return 1
    docker cp scripts/wasabi-upload.sh "${container}:/usr/local/bin/" || return 1
    
    # Asegurar permisos
    docker exec "$container" chmod +x /usr/local/bin/backup-complete.sh
    docker exec "$container" chmod +x /usr/local/bin/health-check-complete.sh
    docker exec "$container" chmod +x /usr/local/bin/wasabi-upload.sh
    
    success "✓ Scripts actualizados en: $container"
    return 0
}

# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

log "════════════════════════════════════════════════════════════════"
log "ACTUALIZACIÓN DE SCRIPTS DE MONITOREO"
log "════════════════════════════════════════════════════════════════"

if [ "$DRY_RUN" = true ]; then
    warning "MODO DRY-RUN: No se realizarán cambios reales"
fi

echo ""

# Obtener lista de contenedores MariaDB corriendo
CONTAINERS=$(docker ps --filter "ancestor=mariadb" --format "{{.Names}}" 2>/dev/null)

if [ -z "$CONTAINERS" ]; then
    CONTAINERS=$(docker ps --format "{{.Names}}" | grep -iE "(mariadb|mysql)" || true)
fi

if [ -z "$CONTAINERS" ]; then
    error "No se encontraron contenedores MariaDB corriendo"
    exit 1
fi

TOTAL=$(echo "$CONTAINERS" | wc -l)
log "Encontrados $TOTAL contenedores MariaDB corriendo"
echo ""

info "Contenedores a actualizar:"
echo "$CONTAINERS" | while read -r container; do
    echo "  - $container"
done

echo ""

# Confirmar
if [ "$DRY_RUN" = false ]; then
    read -p "¿Actualizar scripts en $TOTAL contenedores? (s/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        warning "Actualización cancelada"
        exit 0
    fi
fi

echo ""

# Procesar cada contenedor
SUCCESS=0
FAILED=0

echo "$CONTAINERS" | while read -r container; do
    if [ -z "$container" ]; then
        continue
    fi
    
    if update_scripts_in_container "$container"; then
        ((SUCCESS++))
    else
        ((FAILED++))
    fi
done

echo ""
log "════════════════════════════════════════════════════════════════"
log "RESUMEN DE ACTUALIZACIÓN"
log "════════════════════════════════════════════════════════════════"
success "Exitosos: $SUCCESS"
if [ $FAILED -gt 0 ]; then
    error "Fallidos: $FAILED"
fi
log "Total procesados: $TOTAL"
log "════════════════════════════════════════════════════════════════"

if [ "$DRY_RUN" = true ]; then
    warning "Esto fue una simulación. Ejecuta sin --dry-run para aplicar cambios."
fi
