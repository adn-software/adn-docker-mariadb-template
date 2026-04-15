#!/bin/bash

# ═══════════════════════════════════════════════════════════════
# CONFIGURACIÓN DE CRON EN CONTENEDORES MARIADB
# ═══════════════════════════════════════════════════════════════
# Este script configura cron jobs en todos los contenedores MariaDB
# para ejecutar backups y health checks automáticamente.
#
# Uso: ./configure-cron.sh <nombre_base_datos> [--backup-time "0 2 * * *"] [--health-time "0 8 * * *"]
#
# Ejemplo:
#   ./configure-cron.sh sistemasadn
#   ./configure-cron.sh mydb --backup-time "0 3 * * *" --health-time "0 9 * * *"
# ═══════════════════════════════════════════════════════════════

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuración por defecto
BACKUP_TIME="0 2 * * *"  # 2:00 AM
HEALTH_TIME="0 8 * * *"  # 8:00 AM
DATABASE_NAME=""

# Parsear argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --backup-time)
            BACKUP_TIME="$2"
            shift 2
            ;;
        --health-time)
            HEALTH_TIME="$2"
            shift 2
            ;;
        *)
            if [ -z "$DATABASE_NAME" ]; then
                DATABASE_NAME="$1"
            fi
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

# Validar argumentos
if [ -z "$DATABASE_NAME" ]; then
    error "Debe proporcionar el nombre de la base de datos"
    echo "Uso: $0 <nombre_base_datos> [--backup-time \"0 2 * * *\"] [--health-time \"0 8 * * *\"]"
    exit 1
fi

# Función para configurar cron en un contenedor
configure_cron_in_container() {
    local container="$1"
    
    log "Configurando cron en: $container"
    
    # Verificar que el contenedor está corriendo
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        warning "Contenedor no está corriendo, saltando..."
        return 1
    fi
    
    # Verificar que los scripts están instalados
    if ! docker exec "$container" test -f /usr/local/bin/backup-complete.sh; then
        error "Scripts no instalados en este contenedor"
        info "Ejecuta primero: ./install-all.sh"
        return 1
    fi
    
    # Instalar cron si no está instalado
    if ! docker exec "$container" which cron >/dev/null 2>&1; then
        log "Instalando cron..."
        docker exec "$container" bash -c "apt-get update -qq && apt-get install -y -qq cron" >/dev/null 2>&1 || {
            error "No se pudo instalar cron"
            return 1
        }
    fi
    
    # Obtener zona horaria del contenedor o usar default
    local tz=$(docker exec "$container" bash -c 'echo ${TZ:-America/Caracas}')
    log "Zona horaria del contenedor: $tz"
    
    # Crear crontab con timezone
    log "Configurando crontab..."
    docker exec "$container" bash -c "export TZ='$tz'; export BACKUP_TIME='$BACKUP_TIME'; export HEALTH_TIME='$HEALTH_TIME'; cat > /tmp/crontab.tmp << EOF
# Zona horaria configurada
TZ=$tz
# Backup automático completo (todas las BDs + Wasabi + Notificación)
${BACKUP_TIME} /usr/local/bin/backup-complete.sh >> /var/log/backup.log 2>&1

# Health check automático completo (todas las BDs + Reparación + Notificación)
${HEALTH_TIME} /usr/local/bin/health-check-complete.sh >> /var/log/health.log 2>&1
EOF"
    
    # Instalar crontab
    docker exec "$container" crontab /tmp/crontab.tmp
    docker exec "$container" rm /tmp/crontab.tmp
    
    # Iniciar cron
    docker exec "$container" service cron start >/dev/null 2>&1 || true
    
    # Verificar crontab
    info "Crontab configurado:"
    docker exec "$container" crontab -l | while read -r line; do
        if [[ ! "$line" =~ ^# ]]; then
            echo "  $line"
        fi
    done
    
    log "✓ Cron configurado exitosamente"
    
    return 0
}

# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

log "════════════════════════════════════════════════════════════════"
log "CONFIGURACIÓN DE CRON EN CONTENEDORES MARIADB"
log "════════════════════════════════════════════════════════════════"
log "Base de datos: $DATABASE_NAME"
log "Backup: $BACKUP_TIME"
log "Health check: $HEALTH_TIME"
log "════════════════════════════════════════════════════════════════"
echo ""

# Obtener lista de contenedores MariaDB
CONTAINERS=$(docker ps --filter "ancestor=mariadb" --format "{{.Names}}" 2>/dev/null)

if [ -z "$CONTAINERS" ]; then
    CONTAINERS=$(docker ps --format "{{.Names}}" | grep -iE "(mariadb|mysql)" || true)
fi

if [ -z "$CONTAINERS" ]; then
    error "No se encontraron contenedores MariaDB corriendo"
    exit 1
fi

TOTAL=$(echo "$CONTAINERS" | wc -l)
log "Encontrados $TOTAL contenedores MariaDB"
echo ""

# Confirmar
read -p "¿Configurar cron en $TOTAL contenedores? (s/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    warning "Operación cancelada"
    exit 0
fi

echo ""

# Procesar cada contenedor
SUCCESS=0
FAILED=0

echo "$CONTAINERS" | while read -r container; do
    if [ -z "$container" ]; then
        continue
    fi
    
    if configure_cron_in_container "$container"; then
        ((SUCCESS++))
    else
        ((FAILED++))
    fi
    
    echo ""
done

log "════════════════════════════════════════════════════════════════"
log "RESUMEN"
log "════════════════════════════════════════════════════════════════"
log "Exitosos: $SUCCESS"
if [ $FAILED -gt 0 ]; then
    error "Fallidos: $FAILED"
fi
log "════════════════════════════════════════════════════════════════"
