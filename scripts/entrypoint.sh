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

# Auto-registrar contenedor en el servidor de monitoreo
auto_register() {
    if [ -z "$MONITOR_API_URL" ]; then
        warning "MONITOR_API_URL no configurado, saltando auto-registro"
        return 0
    fi
    
    log "Auto-registrando contenedor en el servidor de monitoreo..."
    
    # Obtener información del contenedor
    local host=$(hostname -i | awk '{print $1}')
    local port="${MYSQL_PORT:-3306}"
    local container_name="${CONTAINER_NAME:-$(hostname)}"
    local mariadb_version=$(mysqld --version | awk '{print $3}')
    
    # Preparar payload
    local payload=$(cat <<EOF
{
  "host": "${host}",
  "port": ${port},
  "rootPassword": "${MYSQL_ROOT_PASSWORD}",
  "containerName": "${container_name}",
  "mariadbVersion": "${mariadb_version}"
}
EOF
)
    
    # Hacer request al endpoint de registro
    local response=$(curl -s -w "\n%{http_code}" -X POST "${MONITOR_API_URL}/database-servers/register" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --max-time 30 2>&1)
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
        log "✓ Contenedor registrado exitosamente (HTTP $http_code)"
        
        # Extraer credenciales de la respuesta
        local server_id=$(echo "$body" | jq -r '.serverId' 2>/dev/null)
        local api_key=$(echo "$body" | jq -r '.apiKey' 2>/dev/null)
        local is_new=$(echo "$body" | jq -r '.isNew' 2>/dev/null)
        
        if [ "$is_new" = "true" ]; then
            log "  ℹ Servidor nuevo creado"
        else
            log "  ℹ Servidor existente actualizado"
        fi
        
        log "  Server ID: ${server_id:0:8}..."
        log "  API Key: ${api_key:0:12}..."
        
        # Actualizar .env si es necesario
        if [ -f "/.env" ]; then
            if ! grep -q "^MONITOR_SERVER_ID=" /.env 2>/dev/null; then
                echo "MONITOR_SERVER_ID=${server_id}" >> /.env
                log "  ✓ MONITOR_SERVER_ID agregado al .env"
            fi
            
            if ! grep -q "^MONITOR_API_KEY=" /.env 2>/dev/null; then
                echo "MONITOR_API_KEY=${api_key}" >> /.env
                log "  ✓ MONITOR_API_KEY agregado al .env"
            fi
        fi
        
        return 0
    else
        warning "No se pudo registrar el contenedor (HTTP $http_code)"
        warning "Response: $body"
        return 1
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
log "Iniciando contenedor MariaDB con soporte de monitoreo automático..."
log "═══════════════════════════════════════════════════════════════"

# Auto-registrar en el servidor de monitoreo (en background para no bloquear)
(sleep 30 && auto_register) &

# Configurar cron jobs
cron_logs
setup_cron_jobs

# Ejecutar el entrypoint original de MariaDB
log "Iniciando MariaDB..."
exec docker-entrypoint.sh mysqld
