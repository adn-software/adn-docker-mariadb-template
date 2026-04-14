# Workflow Completo - Sistema de Monitoreo de Bases de Datos

Guía paso a paso para el workflow completo desde la instalación inicial hasta las actualizaciones regulares.

---

## 🎯 Escenario

- **3 servidores Netcup** con bases de datos
- **40-70 contenedores MariaDB** por servidor
- **Cientos de bases de datos** en total
- **Repositorio centralizado** para scripts
- **Actualización masiva** con git pull

---

## 📦 Setup Inicial (Una vez por servidor)

### Paso 1: Preparar el Servidor Netcup

```bash
# SSH al servidor
ssh root@netcup-server-1.com

# Crear directorio si no existe
mkdir -p /home/adn
cd /home/adn

# Clonar el repositorio
git clone https://github.com/tu-org/adn-monitor-db-scripts.git
cd adn-monitor-db-scripts

# Dar permisos de ejecución
chmod +x *.sh
```

### Paso 2: Registrar el Servidor en el Sistema de Monitoreo

**Opción A: Interfaz Web**
1. Ir a https://monitor.adnsistemas.com
2. Crear nuevo "Database Server"
3. Copiar `serverId` y `apiKey`

**Opción B: API**
```bash
curl -X POST https://api.adnsistemas.com/api/v1/database-servers \
  -H "Authorization: Bearer <JWT_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Netcup Server 1",
    "engine": "mariadb",
    "host": "netcup-server-1.com",
    "port": 3306,
    "monitoringEnabled": true,
    "backupEnabled": true
  }'
```

**Guardar:**
- `serverId`: ej. `550e8400-e29b-41d4-a716-446655440000`
- `apiKey`: ej. `sk_live_abc123xyz...`

### Paso 3: Sincronizar Bases de Datos

```bash
# Desde la interfaz web o API
POST /database-sync/sync
```

Esto descubrirá todas las bases de datos y generará un `databaseId` para cada una.

### Paso 4: Crear Mapeo de Contenedores

Crea un archivo con el mapeo de contenedores a bases de datos:

```bash
nano /home/adn/container-mapping.txt
```

```
# Formato: CONTAINER_NAME:DATABASE_ID:DATABASE_NAME
mariadb-3330-cliente1:db-uuid-1:sistemasadn
mariadb-3331-cliente2:db-uuid-2:appdb
mariadb-3332-cliente3:db-uuid-3:production
...
```

### Paso 5: Instalación Masiva

```bash
cd /home/adn/adn-monitor-db-scripts

# Ver qué haría (dry-run)
./install-all.sh --dry-run

# Instalar en todos los contenedores
./install-all.sh
```

**Esto instalará en cada contenedor:**
- ✅ 6 scripts en `/usr/local/bin/`
- ✅ Directorios `/backups/` y `/var/log/`
- ✅ Dependencias (curl, bc)
- ✅ Archivo `/etc/monitor.env` (plantilla)

### Paso 6: Configurar Credenciales

**Opción A: Script Automatizado (Recomendado)**

```bash
nano configure-all-env.sh
```

```bash
#!/bin/bash

# Credenciales del servidor (iguales para todos los contenedores)
SERVER_ID="550e8400-e29b-41d4-a716-446655440000"
API_KEY="sk_live_abc123xyz..."
API_URL="https://api.adnsistemas.com/api/v1"

# Leer mapeo de archivo
while IFS=':' read -r container db_id db_name; do
    # Saltar comentarios
    [[ "$container" =~ ^#.*$ ]] && continue
    [[ -z "$container" ]] && continue
    
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
    
    echo "✓ $container configurado para BD: $db_name"
done < /home/adn/container-mapping.txt
```

```bash
chmod +x configure-all-env.sh
./configure-all-env.sh
```

**Opción B: Manual (Para pocos contenedores)**

```bash
docker exec -it mariadb-3330-cliente1 nano /etc/monitor.env
```

### Paso 7: Configurar Cron

```bash
# Configurar cron en todos los contenedores
# Backup a las 2 AM, Health check a las 8 AM
./configure-cron.sh sistemasadn
```

### Paso 8: Prueba Manual

```bash
# Probar en un contenedor
docker exec -it mariadb-3330-cliente1 bash -c \
  "source /etc/monitor.env && /usr/local/bin/backup-notify.sh sistemasadn"

# Verificar en el sistema de monitoreo
# Debería aparecer un nuevo registro en Backup Logs
```

---

## 🔄 Workflow de Actualización (Después de cambios)

### Cuando se actualizan los scripts en el repositorio:

```bash
# 1. SSH al servidor
ssh root@netcup-server-1.com

# 2. Ir al directorio del repo
cd /home/adn/adn-monitor-db-scripts

# 3. Actualizar repositorio
git pull origin main

# 4. Actualizar scripts en TODOS los contenedores
./update-scripts.sh

# Listo! Todos los contenedores tienen los scripts actualizados
```

**El script `update-scripts.sh`:**
- ✅ Copia los 6 scripts actualizados a cada contenedor
- ✅ Actualiza permisos de ejecución
- ❌ NO toca configuración (`/etc/monitor.env`)
- ❌ NO toca cron jobs
- ❌ NO toca logs ni backups

---

## 📊 Monitoreo y Mantenimiento

### Ver estado de todos los contenedores

```bash
# Ver cron jobs configurados
for container in $(docker ps --filter "ancestor=mariadb" --format "{{.Names}}"); do
    echo "=== $container ==="
    docker exec "$container" crontab -l 2>/dev/null || echo "No crontab"
done
```

### Ver últimos backups

```bash
# Últimos backups de cada contenedor
for container in $(docker ps --filter "ancestor=mariadb" --format "{{.Names}}"); do
    echo "=== $container ==="
    docker exec "$container" ls -lht /backups/ 2>/dev/null | head -3
done
```

### Ver logs en tiempo real

```bash
# Logs de backup de un contenedor
docker exec mariadb-3330-cliente1 tail -f /var/log/backup.log

# Logs de health check
docker exec mariadb-3330-cliente1 tail -f /var/log/health.log
```

---

## 🔧 Mantenimiento Regular

### Semanal

```bash
# Verificar que todos los contenedores están reportando
# (desde la interfaz web del sistema de monitoreo)

# Ver bases de datos sin backup reciente
GET /databases?lastBackupAt=<7_days_ago>
```

### Mensual

```bash
# Limpiar backups muy antiguos (opcional, ya se hace automático)
for container in $(docker ps --filter "ancestor=mariadb" --format "{{.Names}}"); do
    docker exec "$container" find /backups -name "*.sql.gz" -mtime +30 -delete
done
```

### Después de agregar un nuevo contenedor

```bash
# 1. Agregar al mapeo
echo "mariadb-3340-nuevo:db-uuid-nuevo:nuevadb" >> /home/adn/container-mapping.txt

# 2. Instalar scripts
./install-all.sh  # Detectará el nuevo contenedor

# 3. Configurar credenciales
./configure-all-env.sh  # O manualmente

# 4. Configurar cron
./configure-cron.sh nuevadb
```

---

## 🚨 Troubleshooting

### Problema: Scripts no se actualizan en un contenedor

```bash
# Verificar que el contenedor está corriendo
docker ps | grep <contenedor>

# Forzar actualización en un contenedor específico
docker cp scripts/backup-notify.sh <contenedor>:/usr/local/bin/
docker exec <contenedor> chmod +x /usr/local/bin/backup-notify.sh
```

### Problema: Cron no ejecuta los scripts

```bash
# Verificar que cron está corriendo
docker exec <contenedor> service cron status

# Reiniciar cron
docker exec <contenedor> service cron restart

# Verificar crontab
docker exec <contenedor> crontab -l

# Ver logs de cron
docker exec <contenedor> tail -f /var/log/syslog | grep CRON
```

### Problema: Variables de entorno no se cargan

```bash
# Verificar archivo de configuración
docker exec <contenedor> cat /etc/monitor.env

# Probar carga manual
docker exec <contenedor> bash -c "source /etc/monitor.env && env | grep MONITOR"
```

---

## 📋 Checklist de Setup Completo

### Por Servidor (3 servidores)

- [ ] Repositorio clonado en `/home/adn/adn-monitor-db-scripts`
- [ ] Servidor registrado en el sistema de monitoreo
- [ ] `serverId` y `apiKey` obtenidos
- [ ] Bases de datos sincronizadas
- [ ] Archivo `container-mapping.txt` creado
- [ ] Scripts instalados en todos los contenedores (`install-all.sh`)
- [ ] Credenciales configuradas en todos los contenedores
- [ ] Cron configurado en todos los contenedores
- [ ] Prueba manual exitosa en al menos 3 contenedores
- [ ] Verificación en el sistema de monitoreo (logs recibidos)

### Por Contenedor (40-70 por servidor)

- [ ] Scripts instalados en `/usr/local/bin/`
- [ ] Archivo `/etc/monitor.env` configurado con credenciales correctas
- [ ] Cron job configurado
- [ ] Backup manual ejecutado exitosamente
- [ ] Health check manual ejecutado exitosamente
- [ ] Logs visibles en el sistema de monitoreo

---

## 📊 Resumen de Comandos

```bash
# Setup inicial
cd /home/adn
git clone <repo> adn-monitor-db-scripts
cd adn-monitor-db-scripts
chmod +x *.sh
./install-all.sh
./configure-all-env.sh  # (crear este script)
./configure-cron.sh sistemasadn

# Actualización regular
cd /home/adn/adn-monitor-db-scripts
git pull origin main
./update-scripts.sh

# Monitoreo
docker ps --filter "ancestor=mariadb"
docker exec <contenedor> tail -f /var/log/backup.log
docker exec <contenedor> ls -lh /backups/

# Pruebas
docker exec -it <contenedor> bash -c \
  "source /etc/monitor.env && /usr/local/bin/backup-notify.sh <bd>"
```

---

**Tiempo estimado de setup completo:**
- Servidor 1: ~2 horas (incluye aprendizaje)
- Servidor 2: ~1 hora
- Servidor 3: ~1 hora

**Tiempo de actualización:**
- 3 servidores: ~5 minutos total
