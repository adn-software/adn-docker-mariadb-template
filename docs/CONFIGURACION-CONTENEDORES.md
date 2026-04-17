# Configuración de Contenedores MariaDB para Monitoreo Automático

Esta guía explica cómo configurar los contenedores MariaDB para que ejecuten automáticamente los scripts de backup y health check.

---

## 📋 Arquitectura del Sistema

```
adn-docker-mariadb-template/         ← Plantilla Docker (este repositorio)
├── scripts/                         ← Scripts embebidos en la imagen
│   ├── entrypoint.sh                ← Configura cron al iniciar
│   ├── backup-complete.sh           ← Backup completo + Wasabi + Notificación
│   ├── health-check-complete.sh     ← Health check + Reparación + Notificación
│   ├── wasabi-upload.sh             ← Upload a Wasabi S3
│   └── deploy-update.sh             ← Actualización masiva de contenedores
├── Dockerfile                       ← Construye imagen con scripts incluidos
└── docker-compose.yml               ← Orquesta el contenedor

Servidor Netcup (/var/docker-data/mariadb/)
├── mariadb-3330-cliente1/           ← Contenedor basado en la plantilla
│   ├── Dockerfile                   ← Copiado de la plantilla
│   ├── docker-compose.yml           ← Configuración específica
│   ├── .env                         ← Variables de entorno (BACKUP_ENABLED, etc.)
│   └── ...
├── mariadb-3331-cliente2/
└── ...

Dentro de cada contenedor:
├── /usr/local/bin/
│   ├── backup-complete.sh           ← Script completo de backup
│   ├── health-check-complete.sh     ← Script completo de health check
│   ├── wasabi-upload.sh             ← Upload a Wasabi
│   └── custom-entrypoint.sh         ← Entrypoint con soporte cron
├── /etc/monitor.env                 ← Configuración del sistema ADN
├── /backups/                        ← Backups locales
└── /var/log/
    ├── backup.log
    └── health.log
```

---

## 🚀 Instalación Inicial (Una sola vez por servidor)

### Paso 1: Clonar la plantilla en el servidor Netcup

```bash
# SSH al servidor Netcup
ssh root@servidor-netcup.com

# Ir a /home/adn
cd /home/adn

# Clonar la plantilla
git clone https://github.com/adn-software/adn-docker-mariadb-template.git

# Entrar al directorio
cd adn-docker-mariadb-template

# Dar permisos de ejecución a los scripts
chmod +x scripts/*.sh
```

### Paso 2: Crear contenedores desde la plantilla

Cada contenedor se crea copiando la plantilla y configurando su `.env`:

```bash
# Ejemplo: Crear un nuevo contenedor para cliente1 en puerto 3309
mkdir -p /var/docker-data/mariadb/mariadb-3309-cliente1
cd /var/docker-data/mariadb/mariadb-3309-cliente1

# Copiar archivos de la plantilla
cp /home/adn/adn-docker-mariadb-template/Dockerfile .
cp /home/adn/adn-docker-mariadb-template/docker-compose.yml .
cp /home/adn/adn-docker-mariadb-template/.env.example .env

# Editar configuración
nano .env
```

**Configurar en `.env`:**
```env
# Configuración del contenedor
CONTAINER_NAME=mariadb-3309-cliente1
MYSQL_PORT=3309
MYSQL_ROOT_PASSWORD=password_seguro
MYSQL_DATABASE=sistemasadn

# Configuración de monitoreo (ver sección Configuración)
MONITOR_API_URL=https://qa.sm-api.apps-adn.com/api
MONITOR_API_KEY=sk_live_TU_API_KEY
MONITOR_SERVER_ID=550e8400-e29b-41d4-a716-446655440000

# Para múltiples bases de datos, usa DBID_<nombre>:
DBID_sistemasadn=660e8400-e29b-41d4-a716-446655440001
DBID_otrabase=660e8400-e29b-41d4-a716-446655440002

# Habilitar automatizaciones
BACKUP_ENABLED=true
BACKUP_SCHEDULE=0 2 * * *
HEALTH_CHECK_ENABLED=true
HEALTH_SCHEDULE=0 */6 * * *
```

### Paso 3: Iniciar el contenedor

```bash
# Construir e iniciar
docker compose up -d

# Ver logs
docker compose logs -f
```

**Esto creará automáticamente:**
- ✅ Contenedor MariaDB con scripts embebidos
- ✅ Cron configurado según las variables de entorno
- ✅ Directorios `/backups/` y `/var/log/`
- ✅ Scripts listos en `/usr/local/bin/`

---

## ⚙️ Configuración por Contenedor

Las variables de monitoreo se pasan **automáticamente** desde el archivo `.env` del contenedor, a través de `docker-compose.yml`, como variables de entorno. **No es necesario editar nada dentro del contenedor.**

### Opción A: Configuración Manual (Recomendado para pocos contenedores)

```bash
# Ir al directorio del contenedor
cd /var/docker-data/mariadb/mariadb-3309-cliente1

# Editar el archivo .env (variables se pasan automáticamente al contenedor)
nano .env
```

**Configurar en `.env`:**
```env
# Monitoreo (obtenidos del sistema backup-manager)
MONITOR_API_URL=https://qa.sm-api.apps-adn.com/api
MONITOR_API_KEY=sk_live_abc123xyz...
MONITOR_SERVER_ID=550e8400-e29b-41d4-a716-446655440000

# Database IDs usando formato DBID_<nombre_bd>=<uuid>
# Estas variables se pasan automáticamente al contenedor
DBID_sistemasadn=660e8400-e29b-41d4-a716-446655440001

# Habilitar automatizaciones
BACKUP_ENABLED=true
BACKUP_SCHEDULE=0 2 * * *
HEALTH_CHECK_ENABLED=true
HEALTH_SCHEDULE=0 */6 * * *
```

```bash
# Reiniciar contenedor para aplicar cambios
docker compose restart
```

### Opción B: Configuración Masiva con Script (Para muchos contenedores)

Crea un script que edite los archivos `.env` de cada contenedor:

```bash
nano configure-all-containers.sh
```

```bash
#!/bin/bash

# Credenciales del servidor (mismo Server ID y API Key para todos)
SERVER_ID="550e8400-e29b-41d4-a716-446655440000"
API_KEY="sk_live_abc123..."
API_URL="https://qa.sm-api.apps-adn.com/api"

# Mapeo de contenedores: Puerto:DatabaseID:DatabaseName
# Obtener estos IDs del sistema backup-manager tras sincronizar
CONTAINERS=(
    "3309:660e8400-e29b-41d4-a716-446655440001:sistemasadn"
    "3310:660e8400-e29b-41d4-a716-446655440002:appdb"
    "3311:660e8400-e29b-41d4-a716-446655440003:production"
)

for mapping in "${CONTAINERS[@]}"; do
    IFS=':' read -r port db_id db_name <<< "$mapping"
    container_dir="/var/docker-data/mariadb/mariadb-${port}-cliente"
    
    echo "Configurando contenedor en puerto $port..."
    
    if [ -f "$container_dir/.env" ]; then
        # Actualizar variables de monitoreo en .env
        sed -i "s|^MONITOR_API_URL=.*|MONITOR_API_URL=$API_URL|" "$container_dir/.env"
        sed -i "s|^MONITOR_API_KEY=.*|MONITOR_API_KEY=$API_KEY|" "$container_dir/.env"
        sed -i "s|^MONITOR_SERVER_ID=.*|MONITOR_SERVER_ID=$SERVER_ID|" "$container_dir/.env"
        
        # Agregar/actualizar DBID
        if grep -q "DBID_${db_name}=" "$container_dir/.env"; then
            sed -i "s|^DBID_${db_name}=.*|DBID_${db_name}=${db_id}|" "$container_dir/.env"
        else
            echo "DBID_${db_name}=${db_id}" >> "$container_dir/.env"
        fi
        
        echo "  ✓ $container_dir configurado"
    else
        echo "  ✗ .env no encontrado en $container_dir"
    fi
done

echo ""
echo "⚠️  IMPORTANTE: Para aplicar cambios, reiniciar los contenedores:"
echo "   cd /var/docker-data/mariadb && docker compose -f */docker-compose.yml restart"
```

---

## 🕐 Configurar Ejecución Automática (Cron)

**⚠️ IMPORTANTE:** El cron se configura **automáticamente** al iniciar el contenedor mediante el `entrypoint.sh`. Solo necesitas configurar las variables en el `.env` del contenedor.

### Configuración Automática (Recomendado)

Edita el `.env` de cada contenedor:

```bash
# En el directorio del contenedor
nano .env
```

```env
# Habilitar automatizaciones
BACKUP_ENABLED=true
BACKUP_SCHEDULE=0 2 * * *        # 2:00 AM todos los días

HEALTH_CHECK_ENABLED=true
HEALTH_SCHEDULE=0 */6 * * *      # Cada 6 horas

# Zona horaria
TIMEZONE=America/Caracas
```

Luego reinicia el contenedor para aplicar:

```bash
docker compose restart
```

**El entrypoint configurará automáticamente:**
- ✅ Cron daemon iniciado
- ✅ Jobs programados según las variables
- ✅ Logs en `/var/log/backup.log` y `/var/log/health.log`
- ✅ Zona horaria correcta

### Verificar Configuración de Cron

```bash
# Entrar al contenedor
docker exec -it mariadb-3309-cliente1 bash

# Ver crontab actual
crontab -l

# Ver logs de backup
tail -f /var/log/backup.log

# Ver logs de health check
tail -f /var/log/health.log
```

---

## 🔄 Actualización Masiva de Contenedores

Cuando hayas mejorado la plantilla y quieras actualizar TODOS los contenedores existentes:

```bash
# En el directorio de la plantilla
cd /home/adn/adn-docker-mariadb-template

# Actualizar repositorio
git pull origin main

# Actualizar TODOS los contenedores del servidor
./scripts/deploy-update.sh

# O actualizar solo uno específico
./scripts/deploy-update.sh 3309-cliente1
```

**Esto hará:**
- ✅ Backup de seguridad del contenedor antes de actualizar
- ✅ Actualiza `Dockerfile`, `docker-compose.yml`, y carpeta `scripts/`
- ✅ Reconstruye la imagen con los nuevos scripts
- ✅ Reinicia el contenedor (cron se reconfigura automáticamente)
- ✅ **NO toca** los datos de MySQL ni el archivo `.env`
---

## 🧪 Pruebas Manuales

### Probar backup en un contenedor

```bash
# Ejecutar backup completo (todas las BDs + Wasabi + Notificación)
docker exec mariadb-3309-cliente1 /usr/local/bin/backup-complete.sh

# O para una BD específica (sin notificación)
docker exec mariadb-3309-cliente1 /usr/local/bin/backup-complete.sh sistemasadn
```

### Probar health check en un contenedor

```bash
# Ejecutar health check completo (todas las BDs + Reparación + Notificación)
docker exec mariadb-3309-cliente1 /usr/local/bin/health-check-complete.sh
```

### Ver logs

```bash
# Logs de backup
docker exec mariadb-3330-cliente1 tail -f /var/log/backup.log

# Logs de health check
docker exec mariadb-3330-cliente1 tail -f /var/log/health.log
```

### Listar backups

```bash
docker exec mariadb-3330-cliente1 ls -lh /backups/
```

---

## 📊 Monitoreo del Sistema

### Ver estado de cron en todos los contenedores

```bash
for container in $(docker ps --filter "ancestor=mariadb" --format "{{.Names}}"); do
    echo "=== $container ==="
    docker exec "$container" crontab -l 2>/dev/null || echo "No crontab"
    echo ""
done
```

### Ver últimos backups de todos los contenedores

```bash
for container in $(docker ps --filter "ancestor=mariadb" --format "{{.Names}}"); do
    echo "=== $container ==="
    docker exec "$container" ls -lht /backups/ 2>/dev/null | head -5 || echo "No backups"
    echo ""
done
```

---

## 🔧 Modificar docker-compose.yml de Contenedores

Para que los contenedores tengan las variables de entorno necesarias desde el inicio, modifica el `docker-compose.yml`:

```yaml
services:
  mariadb:
    image: mariadb:10.5
    container_name: ${CONTAINER_NAME:-mariadb-client}
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      TZ: ${TIMEZONE:-America/Caracas}
      
      # Variables del sistema de monitoreo (opcional)
      MONITOR_API_URL: ${MONITOR_API_URL:-https://api.adnsistemas.com/api/v1}
      MONITOR_API_KEY: ${MONITOR_API_KEY}
      MONITOR_SERVER_ID: ${MONITOR_SERVER_ID}
      MONITOR_DATABASE_ID: ${MONITOR_DATABASE_ID}
      
    volumes:
      - mariadb_data:/var/lib/mysql
      - ./init:/docker-entrypoint-initdb.d
      - ./config/my.cnf:/etc/mysql/conf.d/custom.cnf:ro
      - backups:/backups  # ← Agregar volumen para backups
    
volumes:
  mariadb_data:
    driver: local
  backups:  # ← Agregar volumen para backups
    driver: local
```

Y en el `.env` de cada contenedor:

```bash
# Variables del sistema de monitoreo
MONITOR_API_URL=https://api.adnsistemas.com/api/v1
MONITOR_API_KEY=sk_live_abc123...
MONITOR_SERVER_ID=server-uuid
MONITOR_DATABASE_ID=database-uuid
```

---

## 📝 Workflow Completo

### Setup Inicial (Una vez por servidor)

```bash
# 1. Clonar repo
cd /home/adn
git clone https://github.com/tu-org/adn-monitor-db-scripts.git
cd adn-monitor-db-scripts
chmod +x *.sh

# 2. Instalar en todos los contenedores
./install-all.sh

# 3. Configurar credenciales (manual o script)
# Ver Opción A o B arriba

# 4. Configurar cron
./configure-cron.sh sistemasadn

# 5. Probar en un contenedor
docker exec -it mariadb-3330-cliente1 bash -c "source /etc/monitor.env && /usr/local/bin/backup-notify.sh sistemasadn"
```

### Actualización Regular (Después de cambios)

```bash
# 1. Actualizar repo
cd /home/adn/adn-monitor-db-scripts
git pull origin main

# 2. Actualizar scripts en contenedores
./update-scripts.sh

# Listo! Los contenedores tienen los scripts actualizados
```

---

## 🚨 Troubleshooting

### Scripts no se ejecutan automáticamente

```bash
# Verificar que cron está corriendo (se inicia automáticamente en entrypoint)
docker exec <contenedor> pgrep cron

# Si no está corriendo, reiniciar el contenedor
docker compose restart

# Ver crontab configurado
docker exec <contenedor> crontab -l

# Ver logs del entrypoint
docker compose logs | grep -i cron
```

### Variables de entorno no se cargan

```bash
# Verificar variables en el contenedor
docker exec <contenedor> env | grep -E "(MONITOR_|DBID_)"

# Verificar que el .env del host tiene las variables
cat /var/docker-data/mariadb/<nombre>/.env | grep -E "(MONITOR_|DBID_)"

# Recargar variables reiniciando el contenedor
docker compose restart
```

**Nota:** Las variables se definen en el archivo `.env` del directorio del contenedor (en el host), y `docker-compose.yml` las pasa automáticamente como variables de entorno al contenedor. **No es necesario crear `/etc/monitor.env` dentro del contenedor.**

### Backups no se crean

```bash
# Probar manualmente
docker exec <contenedor> /usr/local/bin/backup-complete.sh

# Ver logs en tiempo real
docker exec <contenedor> tail -f /var/log/backup.log

# Verificar que el directorio de backups existe
docker exec <contenedor> ls -la /backups/
```

---

## 📚 Resumen de Scripts

| Script | Propósito | Cuándo usar |
|--------|-----------|-------------|
| `entrypoint.sh` | Configura cron automáticamente al iniciar | Siempre (embebido en imagen) |
| `backup-complete.sh` | Backup de todas las BDs + Wasabi + Notificación | Ejecución automática por cron o manual |
| `health-check-complete.sh` | Health check de todas las BDs + Reparación + Notificación | Ejecución automática por cron o manual |
| `wasabi-upload.sh` | Subir backups a Wasabi S3 | Llamado automáticamente por backup-complete |
| `deploy-update.sh` | Actualizar TODOS los contenedores del servidor | Después de mejorar la plantilla |
| `configure-all-containers.sh` | Configurar credenciales masivamente | Después de crear contenedores |

---

## ✅ Checklist de Instalación

- [ ] Plantilla clonada en `/home/adn/adn-docker-mariadb-template`
- [ ] Contenedores creados desde la plantilla en `/var/docker-data/mariadb/`
- [ ] Database Servers creados en el sistema (obtenidos Server ID y API Key)
- [ ] Bases de datos sincronizadas (obtenidos Database IDs)
- [ ] Credenciales configuradas en cada contenedor (`.env` con DBIDs)
- [ ] Contenedores iniciados (cron se configura automáticamente)
- [ ] Prueba manual exitosa en al menos un contenedor
- [ ] Verificación en el sistema de monitoreo (logs recibidos)
- [ ] Documentado qué contenedor tiene qué base de datos

---

**Siguiente paso:** Ver `INICIO-RAPIDO.md` para pruebas manuales.
