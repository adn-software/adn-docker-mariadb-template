#!/bin/bash

# ═══════════════════════════════════════════════════════════════
# INSTALACIÓN MASIVA DE SCRIPTS DE MONITOREO EN CONTENEDORES MARIADB
# ═══════════════════════════════════════════════════════════════
# Este script instala/actualiza los scripts de backup y health check
# en TODOS los contenedores MariaDB del servidor.
#
# Uso: ./install-all.sh [--force] [--dry-run]
#
# Opciones:
#   --force    : Reinstalar incluso si ya está instalado
#   --dry-run  : Solo mostrar qué se haría sin ejecutar
# ═══════════════════════════════════════════════════════════════

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Flags
FORCE_INSTALL=false
DRY_RUN=false

# Parsear argumentos
for arg in "$@"; do
    case $arg in
        --force)
            FORCE_INSTALL=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
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

# Función para instalar scripts en un contenedor
install_in_container() {
    local container="$1"
    local container_status="$2"
    
    echo ""
    log "════════════════════════════════════════════════"
    log "Procesando contenedor: $container"
    log "Estado: $container_status"
    log "════════════════════════════════════════════════"
    
    # Si el contenedor no está corriendo, intentar iniciarlo
    if [ "$container_status" != "running" ]; then
        warning "Contenedor no está corriendo"
        
        if [ "$DRY_RUN" = true ]; then
            info "[DRY-RUN] Se iniciaría el contenedor"
        else
            info "Iniciando contenedor..."
            docker start "$container" >/dev/null 2>&1 || {
                error "No se pudo iniciar el contenedor"
                return 1
            }
            sleep 3
            log "✓ Contenedor iniciado"
        fi
    fi
    
    # Verificar si ya está instalado
    if [ "$FORCE_INSTALL" = false ]; then
        if docker exec "$container" test -f /usr/local/bin/backup-notify.sh 2>/dev/null; then
            info "Scripts ya instalados en este contenedor"
            read -p "¿Actualizar de todas formas? (s/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Ss]$ ]]; then
                warning "Saltando contenedor $container"
                return 0
            fi
        fi
    fi
    
    if [ "$DRY_RUN" = true ]; then
        info "[DRY-RUN] Se copiarían los siguientes scripts:"
        info "  - backup-notify.sh"
        info "  - health-check-notify.sh"
        info "  - backup-all.sh"
        info "  - wasabi-upload.sh"
        info "  - check-repair.sh"
        info "  - restore.sh"
        return 0
    fi
    
    # 1. Copiar TODOS los scripts necesarios
    log "Copiando scripts al contenedor..."
    
    docker cp scripts/backup-notify.sh "${container}:/usr/local/bin/" || {
        error "Error al copiar backup-notify.sh"
        return 1
    }
    
    docker cp scripts/health-check-notify.sh "${container}:/usr/local/bin/" || {
        error "Error al copiar health-check-notify.sh"
        return 1
    }
    
    docker cp scripts/backup-all.sh "${container}:/usr/local/bin/" || {
        error "Error al copiar backup-all.sh"
        return 1
    }
    
    docker cp scripts/wasabi-upload.sh "${container}:/usr/local/bin/" || {
        error "Error al copiar wasabi-upload.sh"
        return 1
    }
    
    docker cp scripts/check-repair.sh "${container}:/usr/local/bin/" || {
        error "Error al copiar check-repair.sh"
        return 1
    }
    
    docker cp scripts/restore.sh "${container}:/usr/local/bin/" || {
        error "Error al copiar restore.sh"
        return 1
    }
    
    log "✓ Scripts copiados (6 archivos)"
    
    # 2. Dar permisos de ejecución
    log "Configurando permisos de ejecución..."
    docker exec "$container" chmod +x /usr/local/bin/backup-notify.sh
    docker exec "$container" chmod +x /usr/local/bin/health-check-notify.sh
    docker exec "$container" chmod +x /usr/local/bin/backup-all.sh
    docker exec "$container" chmod +x /usr/local/bin/wasabi-upload.sh
    docker exec "$container" chmod +x /usr/local/bin/check-repair.sh
    docker exec "$container" chmod +x /usr/local/bin/restore.sh
    log "✓ Permisos configurados"
    
    # 3. Crear directorios necesarios
    log "Creando directorios necesarios..."
    docker exec "$container" mkdir -p /backups
    docker exec "$container" chmod 755 /backups
    docker exec "$container" mkdir -p /var/log
    docker exec "$container" touch /var/log/backup.log
    docker exec "$container" touch /var/log/health.log
    log "✓ Directorios creados"
    
    # 4. Instalar dependencias necesarias
    log "Verificando dependencias..."
    
    # Verificar si curl está instalado
    if ! docker exec "$container" which curl >/dev/null 2>&1; then
        warning "curl no está instalado, instalando..."
        docker exec "$container" bash -c "apt-get update -qq && apt-get install -y -qq curl" >/dev/null 2>&1 || {
            warning "No se pudo instalar curl automáticamente"
        }
    fi
    
    # Verificar si jq está instalado (para health check)
    if ! docker exec "$container" which jq >/dev/null 2>&1; then
        info "jq no está instalado (opcional para health check avanzado)"
    fi
    
    # Verificar si bc está instalado (para cálculos)
    if ! docker exec "$container" which bc >/dev/null 2>&1; then
        warning "bc no está instalado, instalando..."
        docker exec "$container" bash -c "apt-get update -qq && apt-get install -y -qq bc" >/dev/null 2>&1 || {
            warning "No se pudo instalar bc automáticamente"
        }
    fi
    
    log "✓ Dependencias verificadas"
    
    # 5. Verificar si existe archivo de configuración
    if docker exec "$container" test -f /etc/monitor.env 2>/dev/null; then
        info "Archivo de configuración ya existe: /etc/monitor.env"
    else
        log "Creando archivo de configuración de ejemplo..."
        docker exec "$container" bash -c 'cat > /etc/monitor.env << EOF
# Configuración del Sistema de Monitoreo ADN
MONITOR_API_URL=https://api.adnsistemas.com/api/v1
MONITOR_API_KEY=CAMBIAR_POR_TU_API_KEY
MONITOR_SERVER_ID=CAMBIAR_POR_TU_SERVER_UUID
MONITOR_DATABASE_ID=CAMBIAR_POR_TU_DATABASE_UUID

# Configuración de Backups
BACKUP_DIR=/backups
BACKUP_RETENTION_DAYS=7

# Configuración de MariaDB
DB_HOST=localhost
DB_PORT=3306
EOF'
        log "✓ Archivo de configuración creado"
        warning "⚠ Debes editar /etc/monitor.env en el contenedor con las credenciales correctas"
    fi
    
    # 6. Configurar carga automática de variables
    log "Configurando carga automática de variables..."
    docker exec "$container" bash -c 'grep -q "source /etc/monitor.env" /root/.bashrc 2>/dev/null || echo "source /etc/monitor.env" >> /root/.bashrc'
    log "✓ Variables se cargarán automáticamente"
    
    success "✓ Instalación completada en: $container"
    
    return 0
}

# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

log "════════════════════════════════════════════════════════════════"
log "INSTALACIÓN MASIVA DE SCRIPTS DE MONITOREO"
log "════════════════════════════════════════════════════════════════"

if [ "$DRY_RUN" = true ]; then
    warning "MODO DRY-RUN: No se realizarán cambios reales"
fi

if [ "$FORCE_INSTALL" = true ]; then
    info "MODO FORCE: Se reinstalará en todos los contenedores"
fi

echo ""

# Obtener lista de contenedores MariaDB
log "Buscando contenedores MariaDB..."

# Buscar contenedores que usen imagen mariadb o mysql
CONTAINERS=$(docker ps -a --filter "ancestor=mariadb" --format "{{.Names}}" 2>/dev/null)

if [ -z "$CONTAINERS" ]; then
    # Intentar buscar por nombre de imagen alternativo
    CONTAINERS=$(docker ps -a --filter "ancestor=mysql" --format "{{.Names}}" 2>/dev/null)
fi

if [ -z "$CONTAINERS" ]; then
    # Buscar por nombre de contenedor que contenga "mariadb" o "mysql"
    CONTAINERS=$(docker ps -a --format "{{.Names}}" | grep -iE "(mariadb|mysql)" || true)
fi

if [ -z "$CONTAINERS" ]; then
    error "No se encontraron contenedores MariaDB/MySQL"
    echo ""
    info "Contenedores disponibles:"
    docker ps -a --format "  - {{.Names}} ({{.Image}})"
    exit 1
fi

# Contar contenedores
TOTAL_CONTAINERS=$(echo "$CONTAINERS" | wc -l)
log "Encontrados $TOTAL_CONTAINERS contenedores MariaDB/MySQL"
echo ""

# Mostrar lista de contenedores
info "Contenedores a procesar:"
echo "$CONTAINERS" | while read -r container; do
    status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
    echo "  - $container ($status)"
done

echo ""

# Confirmar antes de proceder
if [ "$DRY_RUN" = false ]; then
    read -p "¿Proceder con la instalación en $TOTAL_CONTAINERS contenedores? (s/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        warning "Instalación cancelada por el usuario"
        exit 0
    fi
fi

echo ""

# Contadores
SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

# Procesar cada contenedor
echo "$CONTAINERS" | while read -r container; do
    if [ -z "$container" ]; then
        continue
    fi
    
    # Obtener estado del contenedor
    status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
    
    # Instalar en el contenedor
    if install_in_container "$container" "$status"; then
        ((SUCCESS_COUNT++))
    else
        ((FAILED_COUNT++))
    fi
    
    echo ""
done

# Resumen final
log "════════════════════════════════════════════════════════════════"
log "RESUMEN DE INSTALACIÓN"
log "════════════════════════════════════════════════════════════════"
success "Exitosos: $SUCCESS_COUNT"
if [ $FAILED_COUNT -gt 0 ]; then
    error "Fallidos: $FAILED_COUNT"
fi
if [ $SKIPPED_COUNT -gt 0 ]; then
    warning "Saltados: $SKIPPED_COUNT"
fi
log "Total procesados: $TOTAL_CONTAINERS"
log "════════════════════════════════════════════════════════════════"

echo ""
info "Próximos pasos:"
echo "1. Configurar credenciales en cada contenedor:"
echo "   docker exec -it <contenedor> nano /etc/monitor.env"
echo ""
echo "2. Probar backup manualmente:"
echo "   docker exec -it <contenedor> bash -c 'source /etc/monitor.env && /usr/local/bin/backup-notify.sh <nombre_bd>'"
echo ""
echo "3. Configurar cron para ejecución automática (ver documentación)"
echo ""

if [ "$DRY_RUN" = true ]; then
    warning "Esto fue una simulación. Ejecuta sin --dry-run para aplicar cambios."
fi
