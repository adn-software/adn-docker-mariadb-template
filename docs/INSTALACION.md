# Guía de Instalación - Scripts de Backup y Health Check con Notificación

Esta guía te ayudará a instalar los scripts de backup y health check en un contenedor MariaDB existente, con integración al sistema de monitoreo ADN.

## 📋 Requisitos Previos

1. **Contenedor MariaDB corriendo**
2. **Acceso al backend del sistema de monitoreo** (para obtener API Key y IDs)
3. **Herramientas instaladas en el host:**
   - `docker`
   - `curl`
   - `jq` (opcional, para formatear JSON)

---

## 🔧 Paso 1: Obtener Credenciales del Sistema de Monitoreo

### 1.1 Crear o Verificar el Database Server

Primero, necesitas registrar tu servidor MariaDB en el sistema de monitoreo:

```bash
# Endpoint: POST /database-servers
# O usa la interfaz web del sistema
```

**Obtendrás:**
- `serverId`: UUID del servidor (ej: `550e8400-e29b-41d4-a716-446655440000`)
- `apiKey`: Clave de API (ej: `sk_live_abc123xyz...`)

### 1.2 Obtener el Database ID

Después de sincronizar las bases de datos, obtendrás:
- `databaseId`: UUID de cada base de datos específica

**Ejemplo de respuesta:**
```json
{
  "id": "db-uuid-123",
  "serverId": "server-uuid-456",
  "databaseName": "sistemasadn",
  "apiKey": "sk_live_generated_key_abc123"
}
```

---

## 📦 Paso 2: Copiar Scripts al Contenedor

### 2.1 Identificar tu contenedor

```bash
# Listar contenedores MariaDB corriendo
docker ps | grep mariadb

# Ejemplo de salida:
# abc123def456   mariadb:10.5   "docker-entrypoint.s…"   mariadb-3330-jccrp
```

**Anota el nombre del contenedor** (ej: `mariadb-3330-jccrp`)

### 2.2 Copiar scripts al contenedor

```bash
# Ir al directorio de scripts
cd /home/aleguizamon/ADN/adn-servers-manager/mariadb-backup-scripts

# Copiar scripts de backup y health check
docker cp scripts/backup-notify.sh <NOMBRE_CONTENEDOR>:/usr/local/bin/
docker cp scripts/health-check-notify.sh <NOMBRE_CONTENEDOR>:/usr/local/bin/

# Ejemplo:
docker cp scripts/backup-notify.sh mariadb-3330-jccrp:/usr/local/bin/
docker cp scripts/health-check-notify.sh mariadb-3330-jccrp:/usr/local/bin/
```

### 2.3 Dar permisos de ejecución

```bash
docker exec <NOMBRE_CONTENEDOR> chmod +x /usr/local/bin/backup-notify.sh
docker exec <NOMBRE_CONTENEDOR> chmod +x /usr/local/bin/health-check-notify.sh

# Ejemplo:
docker exec mariadb-3330-jccrp chmod +x /usr/local/bin/backup-notify.sh
docker exec mariadb-3330-jccrp chmod +x /usr/local/bin/health-check-notify.sh
```

---

## ⚙️ Paso 3: Configurar Variables de Entorno

### 3.1 Crear archivo de configuración

```bash
# Crear archivo de variables dentro del contenedor
docker exec -it <NOMBRE_CONTENEDOR> bash -c 'cat > /etc/monitor.env << EOF
# Configuración del Sistema de Monitoreo ADN
MONITOR_API_URL=https://api.adnsistemas.com/api/v1
MONITOR_API_KEY=sk_live_TU_API_KEY_AQUI
MONITOR_SERVER_ID=tu-server-uuid-aqui
MONITOR_DATABASE_ID=tu-database-uuid-aqui

# Configuración de Backups
BACKUP_DIR=/backups
BACKUP_RETENTION_DAYS=7

# Credenciales de MariaDB (ya deberían estar configuradas)
MYSQL_ROOT_PASSWORD=tu_password_root
DB_HOST=localhost
DB_PORT=3306
EOF'
```

### 3.2 Cargar variables en el perfil

```bash
docker exec -it <NOMBRE_CONTENEDOR> bash -c 'echo "source /etc/monitor.env" >> /root/.bashrc'
```

---

## 🧪 Paso 4: Probar Manualmente (SIN CRON)

### 4.1 Probar Backup Manual

```bash
# Entrar al contenedor
docker exec -it <NOMBRE_CONTENEDOR> bash

# Cargar variables de entorno
source /etc/monitor.env

# Ejecutar backup manualmente (verás los logs en tiempo real)
/usr/local/bin/backup-notify.sh sistemasadn
```

**Salida esperada:**
```
[2024-01-15 10:30:00] ════════════════════════════════════════════════
[2024-01-15 10:30:00] INICIANDO BACKUP DE BASE DE DATOS
[2024-01-15 10:30:00] ════════════════════════════════════════════════
[2024-01-15 10:30:00] Base de datos: sistemasadn
[2024-01-15 10:30:00] Archivo: /backups/backup_sistemasadn_20240115_103000.sql
[2024-01-15 10:30:00] Hora inicio: 2024-01-15T14:30:00Z
[2024-01-15 10:30:00] ════════════════════════════════════════════════
[2024-01-15 10:30:00] Ejecutando mysqldump...
[2024-01-15 10:30:05] ✓ Dump SQL completado exitosamente
[INFO] Tamaño sin comprimir: 15.32 MB
[2024-01-15 10:30:05] Comprimiendo backup...
[2024-01-15 10:30:06] ✓ Backup comprimido exitosamente
[INFO] Tamaño comprimido: 3.45 MB
[INFO] Ratio de compresión: 0.2251 (77.5% reducción)
[INFO] Duración: 6 segundos
[INFO] Enviando notificación al sistema de monitoreo...
[2024-01-15 10:30:07] ✓ Notificación enviada exitosamente al sistema (HTTP 201)
[2024-01-15 10:30:07] Limpiando backups antiguos (más de 7 días)...
[INFO] No hay backups antiguos para eliminar
[2024-01-15 10:30:07] ════════════════════════════════════════════════
[2024-01-15 10:30:07] ✓ BACKUP COMPLETADO EXITOSAMENTE
[2024-01-15 10:30:07] ════════════════════════════════════════════════
[2024-01-15 10:30:07] Archivo: /backups/backup_sistemasadn_20240115_103000.sql.gz
[2024-01-15 10:30:07] Tamaño: 3.45 MB
[2024-01-15 10:30:07] Duración: 6s
[2024-01-15 10:30:07] Backups totales en disco: 1
[2024-01-15 10:30:07] ════════════════════════════════════════════════
```

### 4.2 Probar Health Check Manual

```bash
# Dentro del contenedor (si no estás ya dentro)
docker exec -it <NOMBRE_CONTENEDOR> bash
source /etc/monitor.env

# Ejecutar health check manualmente
/usr/local/bin/health-check-notify.sh sistemasadn
```

**Salida esperada:**
```
[2024-01-15 10:35:00] ════════════════════════════════════════════════
[2024-01-15 10:35:00] INICIANDO HEALTH CHECK DE BASE DE DATOS
[2024-01-15 10:35:00] ════════════════════════════════════════════════
[2024-01-15 10:35:00] Base de datos: sistemasadn
[2024-01-15 10:35:00] Hora: 2024-01-15T14:35:00Z
[2024-01-15 10:35:00] ════════════════════════════════════════════════
[2024-01-15 10:35:00] Verificando conectividad a MariaDB...
[2024-01-15 10:35:00] ✓ Conexión exitosa (15ms)
[2024-01-15 10:35:00] Obteniendo lista de tablas...
[2024-01-15 10:35:00] Verificando integridad de tablas...
[INFO]   [1] Verificando tabla: users
    ✓ OK
[INFO]   [2] Verificando tabla: products
    ✓ OK
[INFO]   [3] Verificando tabla: orders
    ✓ OK
[INFO] Enviando notificación al sistema de monitoreo...
[2024-01-15 10:35:02] ✓ Notificación enviada exitosamente al sistema (HTTP 201)
[2024-01-15 10:35:02] ════════════════════════════════════════════════
[2024-01-15 10:35:02] ✓ HEALTH CHECK COMPLETADO - ESTADO: SALUDABLE
[2024-01-15 10:35:02] ════════════════════════════════════════════════
[2024-01-15 10:35:02] Tablas verificadas: 3
[2024-01-15 10:35:02]   ✓ OK: 3
[2024-01-15 10:35:02] Tiempo de conexión: 15ms
[2024-01-15 10:35:02] Tiempo de consulta: 120ms
[2024-01-15 10:35:02] Duración total: 2000ms
[2024-01-15 10:35:02] ════════════════════════════════════════════════
```

### 4.3 Verificar en el Sistema de Monitoreo

Ve a la interfaz web del sistema y verifica que:
- ✅ Se creó un registro en **Backup Logs**
- ✅ Se creó un registro en **Health Logs**
- ✅ La base de datos muestra `lastBackupAt` actualizado
- ✅ La base de datos muestra `healthStatus` actualizado

---

## 🕐 Paso 5: Configurar Ejecución Automática (CRON)

**⚠️ IMPORTANTE:** Solo configura CRON después de verificar que los scripts funcionan correctamente en modo manual.

### 5.1 Instalar cron en el contenedor (si no está instalado)

```bash
docker exec -it <NOMBRE_CONTENEDOR> bash

# Actualizar repositorios e instalar cron
apt-get update
apt-get install -y cron

# Iniciar servicio cron
service cron start
```

### 5.2 Crear crontab

```bash
# Dentro del contenedor
crontab -e

# Agregar las siguientes líneas:
# Backup diario a las 2:00 AM
0 2 * * * source /etc/monitor.env && /usr/local/bin/backup-notify.sh sistemasadn >> /var/log/backup.log 2>&1

# Health check diario a las 8:00 AM
0 8 * * * source /etc/monitor.env && /usr/local/bin/health-check-notify.sh sistemasadn >> /var/log/health.log 2>&1
```

### 5.3 Verificar crontab

```bash
# Ver crontab configurado
crontab -l

# Verificar que cron está corriendo
service cron status
```

### 5.4 Hacer que cron inicie automáticamente

```bash
# Agregar inicio de cron al entrypoint
docker exec -it <NOMBRE_CONTENEDOR> bash -c 'echo "service cron start" >> /root/.bashrc'
```

---

## 📊 Paso 6: Monitorear Logs

### 6.1 Ver logs de backup

```bash
# Desde el host
docker exec <NOMBRE_CONTENEDOR> tail -f /var/log/backup.log

# O entrar al contenedor
docker exec -it <NOMBRE_CONTENEDOR> bash
tail -f /var/log/backup.log
```

### 6.2 Ver logs de health check

```bash
docker exec <NOMBRE_CONTENEDOR> tail -f /var/log/health.log
```

### 6.3 Listar backups creados

```bash
docker exec <NOMBRE_CONTENEDOR> ls -lh /backups/
```

---

## 🔍 Troubleshooting

### Problema: "Invalid API Key"

**Solución:**
```bash
# Verificar que la API Key esté correctamente configurada
docker exec <NOMBRE_CONTENEDOR> bash -c 'source /etc/monitor.env && echo $MONITOR_API_KEY'

# Debe mostrar: sk_live_...
```

### Problema: "Database not found"

**Solución:**
```bash
# Verificar que el databaseId sea correcto
docker exec <NOMBRE_CONTENEDOR> bash -c 'source /etc/monitor.env && echo $MONITOR_DATABASE_ID'

# Verificar en el sistema que la base de datos existe con ese ID
```

### Problema: No se envía notificación (HTTP 401)

**Causas posibles:**
1. API Key incorrecta o expirada
2. Servidor no está registrado en el sistema
3. Servidor está inactivo (`status != 'active'`)

**Solución:**
```bash
# Verificar en el backend que el servidor existe y está activo
# GET /database-servers/:serverId
```

### Problema: Backup falla con "Access denied"

**Solución:**
```bash
# Verificar password de root
docker exec <NOMBRE_CONTENEDOR> bash -c 'source /etc/monitor.env && echo $MYSQL_ROOT_PASSWORD'

# Probar conexión manual
docker exec <NOMBRE_CONTENEDOR> mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1"
```

---

## 📝 Resumen de Comandos Rápidos

```bash
# 1. Copiar scripts
docker cp scripts/backup-notify.sh <CONTENEDOR>:/usr/local/bin/
docker cp scripts/health-check-notify.sh <CONTENEDOR>:/usr/local/bin/
docker exec <CONTENEDOR> chmod +x /usr/local/bin/*.sh

# 2. Configurar variables (editar con tus valores)
docker exec -it <CONTENEDOR> bash -c 'cat > /etc/monitor.env << EOF
MONITOR_API_URL=https://api.adnsistemas.com/api/v1
MONITOR_API_KEY=sk_live_TU_KEY
MONITOR_SERVER_ID=tu-server-uuid
MONITOR_DATABASE_ID=tu-database-uuid
MYSQL_ROOT_PASSWORD=tu_password
BACKUP_DIR=/backups
BACKUP_RETENTION_DAYS=7
DB_HOST=localhost
DB_PORT=3306
EOF'

# 3. Probar manualmente
docker exec -it <CONTENEDOR> bash
source /etc/monitor.env
/usr/local/bin/backup-notify.sh sistemasadn
/usr/local/bin/health-check-notify.sh sistemasadn

# 4. Configurar cron (después de probar)
docker exec -it <CONTENEDOR> bash
apt-get update && apt-get install -y cron
service cron start
crontab -e
# Agregar:
# 0 2 * * * source /etc/monitor.env && /usr/local/bin/backup-notify.sh sistemasadn >> /var/log/backup.log 2>&1
# 0 8 * * * source /etc/monitor.env && /usr/local/bin/health-check-notify.sh sistemasadn >> /var/log/health.log 2>&1
```

---

## ✅ Checklist de Instalación

- [ ] Contenedor MariaDB identificado
- [ ] Scripts copiados al contenedor
- [ ] Permisos de ejecución configurados
- [ ] Variables de entorno configuradas
- [ ] Backup manual ejecutado exitosamente
- [ ] Health check manual ejecutado exitosamente
- [ ] Notificaciones recibidas en el sistema
- [ ] Cron instalado (opcional)
- [ ] Crontab configurado (opcional)
- [ ] Logs monitoreados

---

## 📞 Soporte

Si encuentras problemas, verifica:
1. Logs del contenedor: `docker logs <CONTENEDOR>`
2. Logs de backup: `docker exec <CONTENEDOR> cat /var/log/backup.log`
3. Logs de health: `docker exec <CONTENEDOR> cat /var/log/health.log`
4. Estado del backend: Verifica que el endpoint `/backup-logs` esté disponible
