# ADN MariaDB Docker - Documentación

Sistema de contenedores MariaDB con monitoreo, backups y health checks automáticos.

## 📚 Índice

1. [Inicio Rápido](#inicio-rápido)
2. [Arquitectura del Sistema](#arquitectura-del-sistema)
3. [Configuración](#configuración)
4. [Monitoreo Automático](#monitoreo-automático)
5. [Despliegue Masivo](#despliegue-masivo)

---

## 🚀 Inicio Rápido

### Crear un nuevo contenedor

```bash
# 1. Clonar template
cp -r adn-docker-mariadb-template mariadb-3309-cliente1
cd mariadb-3309-cliente1

# 2. Configurar .env
nano .env
# Editar: CONTAINER_NAME, MYSQL_PORT, MYSQL_ROOT_PASSWORD, etc.

# 3. Iniciar contenedor
docker compose up -d

# 4. El contenedor se auto-registra en el servidor de monitoreo
# (espera 30 segundos después del inicio)
```

### Verificar auto-registro

```bash
# Ver logs del contenedor
docker compose logs | grep "Auto-registrando"

# Debería mostrar:
# [Entrypoint] Auto-registrando contenedor en el servidor de monitoreo...
# [Entrypoint] ✓ Contenedor registrado exitosamente
```

---

## 🏗️ Arquitectura del Sistema

### Componentes

```
┌─────────────────────────────────────────────────────────────┐
│ SERVIDOR CENTRAL (Backup Manager)                           │
│ https://qa.sm.apps-adn.com                                  │
│                                                              │
│ - Registra servidores y bases de datos                       │
│ - Genera API Keys únicos por servidor                       │
│ - Asigna UUIDs a cada base de datos                         │
│ - Recibe notificaciones de backups y health checks          │
└─────────────────────────────────────────────────────────────┘
                            ▲
                            │ HTTP/JSON
                            │
┌─────────────────────────────────────────────────────────────┐
│ CONTENEDOR MARIADB                                           │
│                                                              │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ ENTRYPOINT (Al iniciar)                                  │ │
│ │ - Auto-registro en servidor central                      │ │
│ │ - Descubrimiento de bases de datos                       │ │
│ │ - Actualización de credenciales                          │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                              │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ CRON JOBS                                                │ │
│ │                                                          │ │
│ │ backup-complete.sh (diario 2:00 AM)                     │ │
│ │ - Obtiene IDs dinámicamente del servidor                │ │
│ │ - Backup de todas las BDs                               │ │
│ │ - Upload a Wasabi S3                                    │ │
│ │ - Notifica al servidor central                          │ │
│ │                                                          │ │
│ │ health-check-complete.sh (cada 6 horas)                 │ │
│ │ - Obtiene IDs dinámicamente del servidor                │ │
│ │ - Verifica todas las BDs                                │ │
│ │ - Repara tablas con problemas                           │ │
│ │ - Notifica al servidor central                          │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Flujo de Datos

1. **Inicio del Contenedor**
   - Entrypoint llama a `POST /api/database-servers/register`
   - Servidor crea/actualiza registro
   - Descubre bases de datos automáticamente
   - Devuelve: `serverId`, `apiKey`, `databases[]`

2. **Ejecución de Backup/Health Check**
   - Script llama a `POST /api/database-servers/get-config`
   - Obtiene lista actualizada de bases de datos con sus IDs
   - Procesa cada BD local
   - Notifica resultado al servidor con el ID correcto

---

## ⚙️ Configuración

### Variables Principales (.env)

```env
# Configuración del Contenedor
CONTAINER_NAME=mariadb-3309-cliente1
MYSQL_PORT=3309
MYSQL_ROOT_PASSWORD=tu_password_seguro

# Sistema de Monitoreo (auto-configurado por entrypoint)
MONITOR_API_URL=https://qa.sm-api.apps-adn.com/api
MONITOR_API_KEY=sk_live_...  # Generado automáticamente
MONITOR_SERVER_ID=uuid        # Generado automáticamente

# Backups Automáticos
BACKUP_ENABLED=true
BACKUP_SCHEDULE=0 2 * * *     # 2:00 AM diario

# Health Checks Automáticos
HEALTH_CHECK_ENABLED=true
HEALTH_SCHEDULE=0 */6 * * *   # Cada 6 horas

# Wasabi S3 (opcional)
WASABI_UPLOAD_ENABLED=true
WASABI_ACCESS_KEY=tu_access_key
WASABI_SECRET_KEY=tu_secret_key
WASABI_BUCKET=tu_bucket
```

### ⚠️ Importante: IDs de Bases de Datos

**Ya NO se requieren variables `DBID_*` en el `.env`**

Los scripts obtienen los IDs dinámicamente en cada ejecución:

```bash
# ❌ ANTES (obsoleto)
DBID_sistemasadn=uuid-1
DBID_produccion=uuid-2
DBID_auditor=uuid-3

# ✅ AHORA (automático)
# Los scripts llaman al endpoint y obtienen los IDs actualizados
```

**Ventajas:**
- ✅ Auto-detección de nuevas bases de datos
- ✅ No requiere reiniciar al crear/eliminar BDs
- ✅ Siempre sincronizado con el servidor

---

## 📊 Monitoreo Automático

### Auto-Registro (Entrypoint)

El contenedor se registra automáticamente al iniciar:

```bash
# En entrypoint.sh (ejecutado automáticamente)
POST /api/database-servers/register
{
  "host": "172.18.0.2",
  "port": 3309,
  "rootPassword": "***",
  "containerName": "mariadb-3309-cliente1",
  "mariadbVersion": "10.11.6"
}

# Respuesta:
{
  "serverId": "uuid-servidor",
  "apiKey": "sk_live_...",
  "isNew": true,
  "databases": [
    { "name": "sistemasadn", "id": "uuid-1", "envVar": "DBID_sistemasadn" },
    { "name": "produccion", "id": "uuid-2", "envVar": "DBID_produccion" }
  ]
}
```

### Backups Automáticos

```bash
# backup-complete.sh (ejecutado por cron)

# 1. Obtener IDs actualizados
POST /api/database-servers/get-config
{ "host": "172.18.0.2", "port": 3309 }

# 2. Para cada BD local:
#    - Ejecutar mysqldump
#    - Comprimir con gzip
#    - Subir a Wasabi S3
#    - Notificar al servidor

POST /api/backup-logs
{
  "databaseId": "uuid-de-la-bd",
  "serverId": "uuid-del-servidor",
  "status": "success",
  "backupSize": 1024000,
  "duration": 45,
  ...
}
```

### Health Checks Automáticos

```bash
# health-check-complete.sh (ejecutado por cron)

# 1. Obtener IDs actualizados (igual que backup)
# 2. Para cada BD local:
#    - Verificar todas las tablas
#    - Reparar si es necesario
#    - Notificar al servidor

POST /api/health-check-logs
{
  "databaseId": "uuid-de-la-bd",
  "serverId": "uuid-del-servidor",
  "status": "healthy",
  "tablesChecked": 45,
  "tablesRepaired": 0,
  ...
}
```

---

## 🚀 Despliegue Masivo

### Script de Despliegue

Para actualizar múltiples contenedores:

```bash
# deploy-update.sh
./scripts/deploy-update.sh

# Proceso:
# 1. Lista todos los contenedores MariaDB
# 2. Para cada contenedor:
#    - Detiene el contenedor
#    - Actualiza scripts
#    - Reinicia el contenedor
#    - Contenedor se auto-registra nuevamente
```

### Configuración Manual (Opcional)

**El entrypoint se auto-configura automáticamente. Este script es solo para casos especiales.**

```bash
# ✅ RECOMENDADO: Dejar que el entrypoint se auto-configure automáticamente
docker compose up -d
# Esperar 30 segundos → Contenedor se registra automáticamente

# ⚠️ OPCIONAL: Si necesitas re-configurar credenciales manualmente
cd /var/docker-data/mariadb/mariadb-3309-cliente1

# Solo actualiza MONITOR_API_KEY y MONITOR_SERVER_ID (sin DBID_*)
/home/adn/adn-docker-mariadb-template/scripts/auto-configure.sh 159.195.57.30 3309

docker compose restart
```

**Nota:** Los IDs de bases de datos se obtienen **dinámicamente** en cada ejecución de backup/health-check. No se almacenan en el `.env`.

---

## 🔧 Troubleshooting

### El contenedor no se auto-registra

**Síntoma:** No aparece en el dashboard después de 30 segundos

**Solución:**
```bash
# 1. Verificar logs
docker compose logs | grep "Auto-registrando"

# 2. Verificar MONITOR_API_URL en .env
cat .env | grep MONITOR_API_URL

# 3. Probar conectividad
docker compose exec mariadb curl -I https://qa.sm-api.apps-adn.com/api

# 4. Re-registrar manualmente
docker compose exec mariadb bash
/usr/local/bin/auto-configure.sh $(hostname -i) 3309
```

### Los backups no se notifican

**Síntoma:** Backups se crean pero no aparecen en el dashboard

**Solución:**
```bash
# 1. Verificar credenciales
docker compose exec mariadb env | grep MONITOR

# 2. Ejecutar backup manualmente
docker compose exec mariadb /usr/local/bin/backup-complete.sh

# 3. Ver logs
docker compose logs | grep "Obteniendo IDs de bases de datos"
```

### Nueva BD no aparece en monitoreo

**Síntoma:** Creaste una BD pero no se monitorea

**Solución:**
```bash
# ✅ NO HACER NADA
# El próximo backup/health-check la detectará automáticamente

# Para forzar actualización inmediata:
docker compose exec mariadb /usr/local/bin/backup-complete.sh
```

---

## 📖 Documentos Relacionados

- `CONFIGURACION-CONTENEDORES.md` - Detalles de configuración
- `INSTALACION.md` - Instalación paso a paso
- `DEPLOY-UPDATE.md` - Despliegue masivo

---

## 🆘 Soporte

Para problemas o preguntas:
- Dashboard: https://qa.sm.apps-adn.com
- Logs del contenedor: `docker compose logs -f`
- Logs de backup: `docker compose exec mariadb tail -f /var/log/backup.log`
- Logs de health: `docker compose exec mariadb tail -f /var/log/health.log`
