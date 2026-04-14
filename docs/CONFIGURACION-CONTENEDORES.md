# Configuración de Contenedores MariaDB para Monitoreo Automático

Esta guía explica cómo configurar los contenedores MariaDB para que ejecuten automáticamente los scripts de backup y health check.

---

## 📋 Arquitectura del Sistema

```
Servidor Netcup (/home/adn/)
├── adn-monitor-db-scripts/          ← Repo clonado (git pull para actualizar)
│   ├── scripts/                     ← Scripts que se copian a contenedores
│   ├── install-all.sh               ← Instalación masiva
│   ├── update-scripts.sh            ← Actualización rápida
│   └── configure-cron.sh            ← Configurar cron en todos
│
└── Contenedores MariaDB (40-70 por servidor)
    ├── mariadb-3330-cliente1/
    ├── mariadb-3331-cliente2/
    └── ...
    
    Cada contenedor tiene:
    ├── /usr/local/bin/
    │   ├── backup-notify.sh         ← Scripts copiados
    │   ├── health-check-notify.sh
    │   ├── backup-all.sh
    │   ├── wasabi-upload.sh
    │   ├── check-repair.sh
    │   └── restore.sh
    ├── /etc/monitor.env             ← Configuración del sistema
    ├── /backups/                    ← Backups locales
    └── /var/log/
        ├── backup.log
        └── health.log
```

---

## 🚀 Instalación Inicial (Una sola vez por servidor)

### Paso 1: Clonar el repositorio en el servidor Netcup

```bash
# SSH al servidor Netcup
ssh root@servidor-netcup.com

# Ir a /home/adn
cd /home/adn

# Clonar el repositorio
git clone https://github.com/tu-org/adn-monitor-db-scripts.git

# Entrar al directorio
cd adn-monitor-db-scripts

# Dar permisos de ejecución a los scripts
chmod +x *.sh
```

### Paso 2: Instalar scripts en TODOS los contenedores

```bash
# Instalación masiva (primera vez)
./install-all.sh

# O con dry-run para ver qué haría
./install-all.sh --dry-run

# Forzar reinstalación en todos
./install-all.sh --force
```

**Esto instalará:**
- ✅ 6 scripts en `/usr/local/bin/` de cada contenedor
- ✅ Directorios `/backups/` y `/var/log/`
- ✅ Dependencias (curl, bc)
- ✅ Archivo de configuración `/etc/monitor.env` (plantilla)

---

## ⚙️ Configuración por Contenedor

### Opción A: Configuración Manual (Recomendado para pocos contenedores)

```bash
# Editar configuración en cada contenedor
docker exec -it mariadb-3330-cliente1 nano /etc/monitor.env

# Cambiar estos valores:
MONITOR_API_URL=https://api.adnsistemas.com/api/v1
MONITOR_API_KEY=sk_live_abc123...
MONITOR_SERVER_ID=uuid-del-servidor
MONITOR_DATABASE_ID=uuid-de-la-base-datos
```

### Opción B: Configuración Masiva con Script (Para muchos contenedores)

Crea un script de configuración masiva:

```bash
# Crear archivo de configuración masiva
nano configure-all-containers.sh
```

```bash
#!/bin/bash

# Mapeo de contenedores a sus credenciales
# Formato: CONTAINER_NAME:DATABASE_ID:DATABASE_NAME

declare -A CONTAINER_CONFIG=(
    ["mariadb-3330-cliente1"]="db-uuid-1:sistemasadn"
    ["mariadb-3331-cliente2"]="db-uuid-2:appdb"
    ["mariadb-3332-cliente3"]="db-uuid-3:production"
    # ... agregar todos los contenedores
)

# Server ID y API Key son los mismos para todos en este servidor
SERVER_ID="server-uuid-netcup-1"
API_KEY="sk_live_abc123..."
API_URL="https://api.adnsistemas.com/api/v1"

for container in "${!CONTAINER_CONFIG[@]}"; do
    IFS=':' read -r db_id db_name <<< "${CONTAINER_CONFIG[$container]}"
    
    echo "Configurando $container..."
    
    docker exec "$container" bash -c "cat > /etc/monitor.env << EOF
MONITOR_API_URL=$API_URL
MONITOR_API_KEY=$API_KEY
MONITOR_SERVER_ID=$SERVER_ID
MONITOR_DATABASE_ID=$db_id
BACKUP_DIR=/backups
BACKUP_RETENTION_DAYS=7
DB_HOST=localhost
DB_PORT=3306
EOF"
    
    echo "✓ $container configurado"
done
```

---

## 🕐 Configurar Ejecución Automática (Cron)

### Opción 1: Configurar cron en todos los contenedores

```bash
# Configurar cron para backup a las 2 AM y health check a las 8 AM
./configure-cron.sh sistemasadn

# O personalizar horarios
./configure-cron.sh mydb --backup-time "0 3 * * *" --health-time "0 9 * * *"
```

### Opción 2: Configurar cron manualmente en un contenedor

```bash
# Entrar al contenedor
docker exec -it mariadb-3330-cliente1 bash

# Instalar cron si no está
apt-get update && apt-get install -y cron
service cron start

# Editar crontab
crontab -e

# Agregar:
0 2 * * * source /etc/monitor.env && /usr/local/bin/backup-notify.sh sistemasadn >> /var/log/backup.log 2>&1
0 8 * * * source /etc/monitor.env && /usr/local/bin/health-check-notify.sh sistemasadn >> /var/log/health.log 2>&1

# Salir
exit
```

---

## 🔄 Actualización de Scripts (Después de git pull)

Cuando hagas cambios en el repositorio y hagas `git pull`:

```bash
# En el servidor Netcup
cd /home/adn/adn-monitor-db-scripts

# Actualizar repositorio
git pull origin main

# Actualizar scripts en TODOS los contenedores (solo copia scripts, no toca config)
./update-scripts.sh

# O con dry-run para ver qué haría
./update-scripts.sh --dry-run
```

**Esto actualiza SOLO los scripts, NO toca:**
- ❌ Configuración (`/etc/monitor.env`)
- ❌ Cron jobs
- ❌ Logs
- ❌ Backups

---

## 🧪 Pruebas Manuales

### Probar backup en un contenedor

```bash
docker exec -it mariadb-3330-cliente1 bash -c "source /etc/monitor.env && /usr/local/bin/backup-notify.sh sistemasadn"
```

### Probar health check en un contenedor

```bash
docker exec -it mariadb-3330-cliente1 bash -c "source /etc/monitor.env && /usr/local/bin/health-check-notify.sh sistemasadn"
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
# Verificar que cron está corriendo
docker exec <contenedor> service cron status

# Reiniciar cron
docker exec <contenedor> service cron restart

# Ver crontab
docker exec <contenedor> crontab -l
```

### Variables de entorno no se cargan

```bash
# Verificar que existe /etc/monitor.env
docker exec <contenedor> cat /etc/monitor.env

# Verificar que se carga en .bashrc
docker exec <contenedor> grep "monitor.env" /root/.bashrc
```

### Backups no se crean

```bash
# Probar manualmente
docker exec -it <contenedor> bash
source /etc/monitor.env
/usr/local/bin/backup-notify.sh <nombre_bd>

# Ver logs
tail -f /var/log/backup.log
```

---

## 📚 Resumen de Scripts

| Script | Propósito | Cuándo usar |
|--------|-----------|-------------|
| `install-all.sh` | Instalación inicial en todos los contenedores | Primera vez o reinstalación completa |
| `update-scripts.sh` | Actualizar solo scripts (no config) | Después de git pull |
| `configure-cron.sh` | Configurar cron en todos | Después de instalación inicial |
| `test-manual.sh` | Prueba interactiva en un contenedor | Para testing individual |

---

## ✅ Checklist de Instalación

- [ ] Repositorio clonado en `/home/adn/adn-monitor-db-scripts`
- [ ] Scripts instalados en todos los contenedores (`install-all.sh`)
- [ ] Credenciales configuradas en cada contenedor
- [ ] Cron configurado en todos los contenedores
- [ ] Prueba manual exitosa en al menos un contenedor
- [ ] Verificación en el sistema de monitoreo (logs recibidos)
- [ ] Documentado qué contenedor tiene qué base de datos

---

**Siguiente paso:** Ver `INICIO-RAPIDO.md` para pruebas manuales.
