#!/bin/bash

# Script de verificación de salud para MariaDB Docker
# Uso: ./health-check.sh

set -e

CONTAINER_NAME="${CONTAINER_NAME:-mariadb-client}"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     MariaDB Docker - Health Check             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""

# 1. Verificar si el contenedor existe
echo -e "${YELLOW}[1/6]${NC} Verificando existencia del contenedor..."
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "  ${GREEN}✓${NC} Contenedor encontrado: $CONTAINER_NAME"
else
    echo -e "  ${RED}✗${NC} Contenedor no encontrado: $CONTAINER_NAME"
    exit 1
fi

# 2. Verificar si el contenedor está corriendo
echo -e "${YELLOW}[2/6]${NC} Verificando estado del contenedor..."
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "  ${GREEN}✓${NC} Contenedor está corriendo"
    
    # Obtener uptime
    UPTIME=$(docker inspect --format='{{.State.StartedAt}}' "$CONTAINER_NAME")
    echo -e "  ${BLUE}ℹ${NC} Iniciado: $UPTIME"
else
    echo -e "  ${RED}✗${NC} Contenedor está detenido"
    exit 1
fi

# 3. Verificar health status
echo -e "${YELLOW}[3/6]${NC} Verificando health status..."
HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "no-healthcheck")
if [ "$HEALTH_STATUS" = "healthy" ]; then
    echo -e "  ${GREEN}✓${NC} Estado de salud: healthy"
elif [ "$HEALTH_STATUS" = "no-healthcheck" ]; then
    echo -e "  ${YELLOW}⚠${NC} No hay healthcheck configurado"
else
    echo -e "  ${RED}✗${NC} Estado de salud: $HEALTH_STATUS"
fi

# 4. Verificar conectividad a MariaDB
echo -e "${YELLOW}[4/6]${NC} Verificando conectividad a MariaDB..."
if docker exec "$CONTAINER_NAME" mysqladmin ping -h localhost -u root -p"${MYSQL_ROOT_PASSWORD}" --silent 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} MariaDB está respondiendo"
else
    echo -e "  ${RED}✗${NC} MariaDB no está respondiendo"
    exit 1
fi

# 5. Verificar base de datos
echo -e "${YELLOW}[5/6]${NC} Verificando base de datos..."
if docker exec "$CONTAINER_NAME" mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "USE ${MYSQL_DATABASE};" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Base de datos accesible: ${MYSQL_DATABASE}"
else
    echo -e "  ${RED}✗${NC} No se puede acceder a la base de datos: ${MYSQL_DATABASE}"
    exit 1
fi

# 6. Obtener estadísticas
echo -e "${YELLOW}[6/6]${NC} Obteniendo estadísticas..."

# Versión de MariaDB
VERSION=$(docker exec "$CONTAINER_NAME" mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT VERSION();" -s -N 2>/dev/null)
echo -e "  ${BLUE}ℹ${NC} Versión: $VERSION"

# Conexiones activas
CONNECTIONS=$(docker exec "$CONTAINER_NAME" mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW STATUS LIKE 'Threads_connected';" -s -N 2>/dev/null | awk '{print $2}')
echo -e "  ${BLUE}ℹ${NC} Conexiones activas: $CONNECTIONS"

# Uptime de MariaDB
UPTIME_SECONDS=$(docker exec "$CONTAINER_NAME" mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW STATUS LIKE 'Uptime';" -s -N 2>/dev/null | awk '{print $2}')
UPTIME_HOURS=$((UPTIME_SECONDS / 3600))
echo -e "  ${BLUE}ℹ${NC} Uptime de MariaDB: ${UPTIME_HOURS} horas"

# Tamaño de la base de datos
DB_SIZE=$(docker exec "$CONTAINER_NAME" mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)' FROM information_schema.TABLES WHERE table_schema = '${MYSQL_DATABASE}';" -s -N 2>/dev/null)
echo -e "  ${BLUE}ℹ${NC} Tamaño de BD: ${DB_SIZE} MB"

# Uso de CPU y memoria del contenedor
CPU_USAGE=$(docker stats "$CONTAINER_NAME" --no-stream --format "{{.CPUPerc}}" 2>/dev/null)
MEM_USAGE=$(docker stats "$CONTAINER_NAME" --no-stream --format "{{.MemUsage}}" 2>/dev/null)
echo -e "  ${BLUE}ℹ${NC} CPU: $CPU_USAGE"
echo -e "  ${BLUE}ℹ${NC} Memoria: $MEM_USAGE"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✓ Todos los checks pasaron exitosamente      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"

exit 0
