#!/bin/bash

# Entrypoint script para MariaDB con soporte de backups automáticos

set -e

# Configuración del cron job
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 2 * * *}"  # Por defecto: 2:00 AM todos los días
BACKUP_ENABLED="${BACKUP_ENABLED:-true}"

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[Entrypoint]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[Entrypoint]${NC} $1"
}

# Configurar cron job para backups
setup_backup_cron() {
    if [ "$BACKUP_ENABLED" != "true" ]; then
        log "Backups automáticos deshabilitados (BACKUP_ENABLED=false)"
        return 0
    fi

    log "Configurando backups automáticos..."
    log "Horario: $BACKUP_SCHEDULE"
    log "Directorio: /backups"
    log "Retención: ${BACKUP_RETENTION_DAYS:-7} días"

    # Crear directorio de backups
    mkdir -p /backups
    chmod 755 /backups

    # Dar permisos de ejecución al script de backup
    chmod +x /usr/local/bin/backup-all.sh

    # Configurar el cron job
    echo "$BACKUP_SCHEDULE /usr/local/bin/backup-all.sh >> /var/log/backup.log 2>&1" | crontab -

    # Iniciar cron daemon
    cron

    # Mostrar configuración actual
    log "Cron job configurado:"
    crontab -l | while read -r line; do
        log "  $line"
    done

    log "Backups automáticos activados"
}

# Configurar logging
cron_logs() {
    mkdir -p /var/log
    touch /var/log/backup.log
    tail -F /var/log/backup.log &
}

# Main
log "Iniciando MariaDB con soporte de backups automáticos..."

# Configurar backup
cron_logs
setup_backup_cron

# Ejecutar el entrypoint original de MariaDB
log "Iniciando MariaDB..."
exec docker-entrypoint.sh mysqld
