#!/bin/bash

# Entrypoint script para MariaDB con soporte de backups y health checks automáticos
# Configura cron al iniciar el contenedor para ejecutar:
# - backup-complete.sh: Backup de todas las BDs + Wasabi + Notificación
# - health-check-complete.sh: Health check de todas las BDs + Reparación + Notificación

set -e

# Configuración de cron jobs
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 2 * * *}"     # Por defecto: 2:00 AM diario
HEALTH_SCHEDULE="${HEALTH_SCHEDULE:-0 */6 * * *}"   # Por defecto: Cada 6 horas
BACKUP_ENABLED="${BACKUP_ENABLED:-true}"
HEALTH_CHECK_ENABLED="${HEALTH_CHECK_ENABLED:-true}"

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[Entrypoint]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[Entrypoint]${NC} $1"
}

info() {
    echo -e "${BLUE}[Entrypoint]${NC} $1"
}

# Configurar zona horaria para cron
setup_timezone() {
    local tz="${TZ:-America/Caracas}"
    log "Configurando zona horaria: $tz"
    
    # Configurar timezone del sistema
    export TZ="$tz"
    
    # Configurar en crontab para que cron use la zona horaria correcta
    echo "TZ=$tz" | crontab -
    
    # También configurar en el entorno global
    echo "TZ=$tz" >> /etc/environment
    
    log "Zona horaria configurada: $tz"
}

# Configurar cron jobs para backup y health check
setup_cron_jobs() {
    # Configurar zona horaria primero
    setup_timezone
    
    # Crear directorios necesarios
    mkdir -p /backups
    chmod 755 /backups
    mkdir -p /var/log
    touch /var/log/backup.log
    touch /var/log/health.log
    
    # Dar permisos de ejecución a los scripts
    chmod +x /usr/local/bin/backup-complete.sh 2>/dev/null || warning "backup-complete.sh no encontrado"
    chmod +x /usr/local/bin/health-check-complete.sh 2>/dev/null || warning "health-check-complete.sh no encontrado"
    
    # Obtener zona horaria configurada
    local tz="${TZ:-America/Caracas}"
    
    # Construir crontab (incluyendo TZ al inicio)
    local crontab_content="TZ=$tz\n"
    
    # Backup automático
    if [ "$BACKUP_ENABLED" = "true" ]; then
        log "Configurando backup automático..."
        log "  Horario: $BACKUP_SCHEDULE"
        log "  Script: backup-complete.sh (todas las BDs + Wasabi + Notificación)"
        crontab_content="${crontab_content}${BACKUP_SCHEDULE} /usr/local/bin/backup-complete.sh >> /var/log/backup.log 2>&1\n"
    else
        log "Backups automáticos deshabilitados (BACKUP_ENABLED=false)"
    fi
    
    # Health check automático
    if [ "$HEALTH_CHECK_ENABLED" = "true" ]; then
        log "Configurando health check automático..."
        log "  Horario: $HEALTH_SCHEDULE"
        log "  Script: health-check-complete.sh (todas las BDs + Reparación + Notificación)"
        crontab_content="${crontab_content}${HEALTH_SCHEDULE} /usr/local/bin/health-check-complete.sh >> /var/log/health.log 2>&1\n"
    else
        log "Health check automático deshabilitado (HEALTH_CHECK_ENABLED=false)"
    fi
    
    # Instalar crontab si hay contenido
    if [ -n "$crontab_content" ]; then
        echo -e "$crontab_content" | crontab -
        
        # Iniciar cron daemon
        cron
        
        # Mostrar configuración
        log "Cron jobs configurados (Zona horaria: $tz):"
        crontab -l | while read -r line; do
            if [ -n "$line" ]; then
                log "  $line"
            fi
        done
        
        log "Cron daemon iniciado en zona horaria: $tz"
    fi
}

# Configurar logging en foreground
cron_logs() {
    # Iniciar tail en background para mostrar logs en los logs de Docker
    (
        tail -F /var/log/backup.log 2>/dev/null &
        tail -F /var/log/health.log 2>/dev/null &
    ) 2>/dev/null || true
}

# Main
log "═══════════════════════════════════════════════════════════════"
log "ADN MariaDB Docker - Entrypoint"
log "═══════════════════════════════════════════════════════════════"
log "Iniciando contenedor MariaDB con soporte de backups y health checks..."
log "═══════════════════════════════════════════════════════════════"

# Configurar cron jobs
cron_logs
setup_cron_jobs

# Ejecutar el entrypoint original de MariaDB
log "Iniciando MariaDB..."
exec docker-entrypoint.sh mysqld
