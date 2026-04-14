# 🚀 Inicio Rápido - Scripts de Backup y Health Check

Guía rápida para instalar y probar los scripts en un contenedor MariaDB existente.

---

## ✅ Estado del Backend

El backend **YA TIENE IMPLEMENTADOS** los endpoints necesarios:

- ✅ `POST /backup-logs` - Recibe notificaciones de backup
- ✅ `POST /health-logs` - Recibe notificaciones de health check
- ✅ `ApiKeyGuard` - Autenticación con X-API-Key
- ✅ Validación de DTOs completa
- ✅ Actualización automática de `lastBackupAt` y `healthStatus`

**Ubicación en el código:**
- `@/adn-servers-manager-api/src/modules/backup-logs/`
- `@/adn-servers-manager-api/src/modules/health-logs/`
- `@/adn-servers-manager-api/src/common/guards/api-key.guard.ts`

---

## 📦 Paso 1: Instalación (1 minuto)

```bash
# Ir al directorio
cd /home/aleguizamon/ADN/adn-servers-manager/mariadb-backup-scripts

# Ejecutar instalación automática
./install.sh <nombre_contenedor>

# Ejemplo:
./install.sh mariadb-3330-jccrp
```

**Esto instalará:**
- ✅ Scripts de backup y health check
- ✅ Permisos de ejecución
- ✅ Directorios necesarios
- ✅ Archivo de configuración de ejemplo

---

## ⚙️ Paso 2: Configuración (2 minutos)

### 2.1 Obtener credenciales del sistema

**Opción A: Usar la interfaz web**
1. Ir a la sección "Database Servers"
2. Crear nuevo servidor o seleccionar existente
3. Copiar `serverId` y `apiKey`
4. Sincronizar bases de datos
5. Copiar `databaseId` de la base de datos que quieres monitorear

**Opción B: Usar el API**
```bash
# Crear servidor (requiere JWT token)
curl -X POST https://api.adnsistemas.com/api/v1/database-servers \
  -H "Authorization: Bearer <JWT_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "MariaDB Container - Cliente ABC",
    "engine": "mariadb",
    "host": "192.168.1.100",
    "port": 3306,
    "username": "root",
    "password": "password",
    "monitoringEnabled": true,
    "backupEnabled": true
  }'

# Respuesta incluirá: serverId y apiKey
```

### 2.2 Editar configuración

```bash
# Editar configuración dentro del contenedor
docker exec -it <nombre_contenedor> nano /etc/monitor.env

# Cambiar estos valores:
MONITOR_API_KEY=sk_live_TU_API_KEY_AQUI
MONITOR_SERVER_ID=tu-server-uuid-aqui
MONITOR_DATABASE_ID=tu-database-uuid-aqui
```

**Ejemplo de configuración completa:**
```bash
MONITOR_API_URL=https://api.adnsistemas.com/api/v1
MONITOR_API_KEY=sk_live_abc123xyz789...
MONITOR_SERVER_ID=550e8400-e29b-41d4-a716-446655440000
MONITOR_DATABASE_ID=660e8400-e29b-41d4-a716-446655440001
BACKUP_DIR=/backups
BACKUP_RETENTION_DAYS=7
DB_HOST=localhost
DB_PORT=3306
```

---

## 🧪 Paso 3: Prueba Manual (3 minutos)

### Opción A: Script interactivo (RECOMENDADO)

```bash
# Ejecutar script de prueba
./test-manual.sh <nombre_contenedor> <nombre_base_datos>

# Ejemplo:
./test-manual.sh mariadb-3330-jccrp sistemasadn
```

**El script te mostrará un menú:**
```
1. Ejecutar BACKUP
2. Ejecutar HEALTH CHECK
3. Ejecutar AMBOS (backup + health check)
4. Ver logs de backup
5. Ver logs de health check
6. Listar backups existentes
7. Salir
```

### Opción B: Comandos manuales

```bash
# Entrar al contenedor
docker exec -it <nombre_contenedor> bash

# Cargar variables
source /etc/monitor.env

# Ejecutar backup (verás logs en tiempo real)
/usr/local/bin/backup-notify.sh sistemasadn

# Ejecutar health check
/usr/local/bin/health-check-notify.sh sistemasadn

# Salir del contenedor
exit
```

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

## 🕐 Paso 5: Configurar Ejecución Automática (OPCIONAL)

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
