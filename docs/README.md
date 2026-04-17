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
# NOTA: El registro en el servidor de monitoreo debe hacerse manualmente

# 3. Iniciar contenedor
docker compose up -d
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
│ │ - Configuración de cron para backups y health checks     │ │
│ │ - Inicialización de MariaDB                              │ │
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

1. **Configuración Inicial (Manual)**
   - Crear Database Server en el sistema de monitoreo
   - Obtener `serverId` y `apiKey` del sistema
   - Configurar variables en el `.env` del contenedor

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

# Sistema de Monitoreo (configuración manual requerida)
MONITOR_API_URL=https://qa.sm-api.apps-adn.com/api
MONITOR_API_KEY=sk_live_...  # Obtener del sistema de monitoreo
MONITOR_SERVER_ID=uuid        # Obtener del sistema de monitoreo

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

## 📊 Monitoreo

### Configuración Manual (Requerida)

El registro del contenedor debe realizarse manualmente en el sistema de monitoreo:

1. Crear un Database Server en `https://qa.sm.apps-adn.com/backup-manager`
2. Configurar las credenciales en el archivo `.env` del contenedor:

```env
MONITOR_API_URL=https://qa.sm-api.apps-adn.com/api
MONITOR_API_KEY=sk_live_...  # Generado por el sistema
MONITOR_SERVER_ID=uuid        # Asignado por el sistema
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
```

### Configuración Manual

**El registro del contenedor debe realizarse manualmente.**

```bash
# 1. Crear Database Server en el sistema de monitoreo y obtener credenciales

# 2. Configurar en el .env del contenedor
cd /var/docker-data/mariadb/mariadb-3309-cliente1
nano .env
# Agregar:
# MONITOR_API_URL=https://qa.sm-api.apps-adn.com/api
# MONITOR_API_KEY=sk_live_...
# MONITOR_SERVER_ID=uuid-...

# 3. Reiniciar contenedor
docker compose restart
```

**Nota:** Los IDs de bases de datos se obtienen **dinámicamente** en cada ejecución de backup/health-check. No se almacenan en el `.env`.

---

## 🔧 Troubleshooting

### El contenedor no aparece en el dashboard

**Síntoma:** No aparece en el dashboard del sistema de monitoreo

**Solución:**
```bash
# 1. Verificar que el Database Server fue creado en el sistema de monitoreo
# 2. Verificar credenciales en .env
cat .env | grep MONITOR

# 3. Probar conectividad con el API
docker compose exec mariadb curl -I https://qa.sm-api.apps-adn.com/api

# 4. Verificar que MONITOR_API_KEY y MONITOR_SERVER_ID estén configurados
docker compose exec mariadb env | grep MONITOR
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
