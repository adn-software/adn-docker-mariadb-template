# 🚀 Inicio Rápido - Plantilla Docker MariaDB con Monitoreo

Guía rápida para crear un contenedor MariaDB con backup, health check y monitoreo automáticos.

---

## ✅ Estado del Backend

El sistema backup-manager **YA TIENE IMPLEMENTADOS** los endpoints necesarios:

- ✅ `POST /backup-logs` - Recibe notificaciones de backup
- ✅ `POST /health-logs` - Recibe notificaciones de health check
- ✅ `ApiKeyGuard` - Autenticación con X-API-Key
- ✅ Database Servers y Database IDs para monitoreo

**URL del sistema:** `https://qa.sm.apps-adn.com/backup-manager`

---

## 📦 Paso 1: Crear Contenedor desde la Plantilla (2 minutos)

```bash
# Ir al directorio de la plantilla
cd /home/adn/adn-docker-mariadb-template

# Crear nuevo directorio para el contenedor
mkdir -p /var/docker-data/mariadb/mariadb-3309-cliente1
cd /var/docker-data/mariadb/mariadb-3309-cliente1

# Copiar archivos de la plantilla
cp /home/adn/adn-docker-mariadb-template/Dockerfile .
cp /home/adn/adn-docker-mariadb-template/docker-compose.yml .
cp /home/adn/adn-docker-mariadb-template/.env.example .env

# Editar configuración
nano .env
```

**Configurar mínimamente en `.env`:**
```env
CONTAINER_NAME=mariadb-3309-cliente1
MYSQL_PORT=3309
MYSQL_ROOT_PASSWORD=tu_password_seguro
MYSQL_DATABASE=sistemasadn

# Deshabilitar monitoreo temporalmente para prueba
BACKUP_ENABLED=false
HEALTH_CHECK_ENABLED=false
```

```bash
# Iniciar contenedor
docker compose up -d
```

**Esto creará:**
- ✅ Contenedor MariaDB con scripts embebidos
- ✅ Scripts de backup y health check en `/usr/local/bin/`
- ✅ Directorios `/backups/` y `/var/log/`

---

## ⚙️ Paso 2: Configuración Manual (Requerida)

El registro del contenedor en el sistema de monitoreo debe hacerse **manualmente**.

### 2.1 Obtener credenciales del sistema (backup-manager)

**Usar la interfaz web:**
1. Ir a `https://qa.sm.apps-adn.com/backup-manager`
2. Crear "Database Server" con método de monitoreo **PASSIVE**
3. Anotar `Server ID` y `API Key` generados
4. Ejecutar "Sincronizar" para descubrir bases de datos
5. Ir a "Bases de Datos" y anotar el `Database ID` de cada BD

**Ver GUÍA-CONFIGURACION-MONITOREO.md para instrucciones detalladas con imágenes**

### 2.2 Editar configuración del contenedor

```bash
# Editar el .env del contenedor
cd /var/docker-data/mariadb/mariadb-3309-cliente1
nano .env
```

**Configurar credenciales obtenidas:**
```env
# Monitoreo (del paso anterior)
MONITOR_API_URL=https://qa.sm-api.apps-adn.com/api
MONITOR_API_KEY=sk_live_abc123xyz789...
MONITOR_SERVER_ID=550e8400-e29b-41d4-a716-446655440000

# Database IDs usando formato DBID_<nombre_bd>=<uuid>
# (uno por cada base de datos en el contenedor)
DBID_sistemasadn=660e8400-e29b-41d4-a716-446655440001

# Habilitar automatizaciones
BACKUP_ENABLED=true
BACKUP_SCHEDULE=0 2 * * *        # 2:00 AM diario

HEALTH_CHECK_ENABLED=true
HEALTH_SCHEDULE=0 */6 * * *     # Cada 6 horas
```

```bash
# Reiniciar contenedor para aplicar cambios
docker compose restart
```

---

## 🧪 Paso 3: Prueba Manual (3 minutos)

### Comandos directos (sin entrar al contenedor)

```bash
# Probar backup completo (todas las BDs + Wasabi + Notificación)
docker exec mariadb-3309-cliente1 /usr/local/bin/backup-complete.sh

# Ver logs en tiempo real
docker exec mariadb-3309-cliente1 tail -f /var/log/backup.log

# En otra terminal, probar health check
docker exec mariadb-3309-cliente1 /usr/local/bin/health-check-complete.sh

# Ver logs de health check
docker exec mariadb-3309-cliente1 tail -f /var/log/health.log
```

### Verificar en el sistema

1. Ir a `https://qa.sm.apps-adn.com/backup-manager`
2. Verificar en "Logs de Backup" que aparece el registro
3. Verificar en "Logs de Salud" que aparece el health check

---

## 📊 Paso 4: Verificar en el Sistema (1 minuto)

### En la interfaz web del sistema:

1. **Ir a "Backup Logs"**
   - Deberías ver un nuevo registro con:
     - ✅ Status: success
     - ✅ Tamaño del backup
     - ✅ Duración
     - ✅ Ratio de compresión

2. **Ir a "Health Logs"**
   - Deberías ver un nuevo registro con:
     - ✅ Status: healthy/warning/critical
     - ✅ Tablas verificadas
     - ✅ Issues detectados (si hay)

3. **Ir a "Databases"**
   - La base de datos debería mostrar:
     - ✅ `lastBackupAt` actualizado
     - ✅ `healthStatus` actualizado

### Verificar con el API:

```bash
# Ver últimos backup logs
curl -X GET "https://api.adnsistemas.com/api/v1/backup-logs?databaseId=<database_id>&limit=5" \
  -H "Authorization: Bearer <JWT_TOKEN>"

# Ver últimos health logs
curl -X GET "https://api.adnsistemas.com/api/v1/health-logs?databaseId=<database_id>&limit=5" \
  -H "Authorization: Bearer <JWT_TOKEN>"
```

---

## 🕐 Paso 5: Configurar Ejecución Automática (CRON)

**⚠️ IMPORTANTE:** Solo configura esto después de verificar que todo funciona correctamente en modo manual.

```bash
# Entrar al contenedor
docker exec -it <nombre_contenedor> bash

# Instalar cron (si no está instalado)
apt-get update && apt-get install -y cron
service cron start

# Editar crontab
crontab -e

# Agregar estas líneas:
# Backup diario a las 2:00 AM
0 2 * * * source /etc/monitor.env && /usr/local/bin/backup-notify.sh sistemasadn >> /var/log/backup.log 2>&1

# Health check diario a las 8:00 AM
0 8 * * * source /etc/monitor.env && /usr/local/bin/health-check-notify.sh sistemasadn >> /var/log/health.log 2>&1

# Guardar y salir (Ctrl+X, Y, Enter en nano)

# Verificar crontab
crontab -l

# Salir del contenedor
exit
```

---

## 📝 Comandos Útiles

### Ver logs en tiempo real

```bash
# Logs de backup
docker exec <contenedor> tail -f /var/log/backup.log

# Logs de health check
docker exec <contenedor> tail -f /var/log/health.log
```

### Ver backups creados

```bash
# Listar backups
docker exec <contenedor> ls -lh /backups/

# Ver espacio usado
docker exec <contenedor> du -sh /backups/
```

### Ejecutar manualmente desde el host

```bash
# Backup
docker exec -it <contenedor> bash -c "source /etc/monitor.env && /usr/local/bin/backup-notify.sh sistemasadn"

# Health check
docker exec -it <contenedor> bash -c "source /etc/monitor.env && /usr/local/bin/health-check-notify.sh sistemasadn"
```

---

## 🔍 Troubleshooting Rápido

### ❌ Error: "Invalid API Key"

```bash
# Verificar API Key
docker exec <contenedor> bash -c 'source /etc/monitor.env && echo $MONITOR_API_KEY'

# Debe empezar con: sk_live_
# Si no, editar /etc/monitor.env
```

### ❌ Error: "Database not found"

```bash
# Verificar Database ID
docker exec <contenedor> bash -c 'source /etc/monitor.env && echo $MONITOR_DATABASE_ID'

# Verificar en el sistema que la BD existe con ese ID
```

### ❌ No se envía notificación

```bash
# Verificar conectividad con el API
docker exec <contenedor> curl -I https://api.adnsistemas.com/api/v1/health

# Debe responder: HTTP/2 200
```

### ❌ Backup falla

```bash
# Verificar password de root
docker exec <contenedor> bash -c 'echo $MYSQL_ROOT_PASSWORD'

# Probar conexión
docker exec <contenedor> mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1"
```

---

## 📚 Documentación Completa

- **README.md** - Documentación general
- **INSTALACION.md** - Guía detallada paso a paso
- **.env.monitor.example** - Ejemplo de configuración completo

---

## ✅ Checklist Final

Antes de considerar la instalación completa, verifica:

- [ ] Scripts instalados en el contenedor
- [ ] Configuración editada con credenciales reales
- [ ] Backup manual ejecutado exitosamente
- [ ] Health check manual ejecutado exitosamente
- [ ] Notificaciones recibidas en el sistema de monitoreo
- [ ] Logs visibles en `/var/log/backup.log` y `/var/log/health.log`
- [ ] Backups creados en `/backups/`
- [ ] (Opcional) Cron configurado para ejecución automática

---

## 🎯 Resumen de Archivos Creados

```
mariadb-backup-scripts/
├── scripts/
│   ├── backup-notify.sh          ← Script de backup CON notificación ✅
│   └── health-check-notify.sh    ← Script de health check CON notificación ✅
├── install.sh                    ← Instalación automática ✅
├── test-manual.sh                ← Prueba interactiva ✅
├── INICIO-RAPIDO.md              ← Esta guía ✅
├── INSTALACION.md                ← Guía detallada ✅
├── README.md                     ← Documentación general ✅
└── .env.monitor.example          ← Ejemplo de configuración ✅
```

---

**¡Listo para usar!** 🚀

Si tienes problemas, revisa **INSTALACION.md** para más detalles o ejecuta `./test-manual.sh` para diagnóstico interactivo.
