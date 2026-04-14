# 🐳 ADN Docker MariaDB Template

Plantilla Docker de MariaDB 10.5 para **ADN Software** - Sistema de gestión de bases de datos multi-contenedor desplegado en múltiples servidores Linux.

## 📋 Descripción

Esta plantilla proporciona un contenedor Docker de MariaDB 10.5 completamente configurado y optimizado para alto tráfico, con soporte para:

- **Gestión masiva** de múltiples contenedores en servidores Netcup
- **Backups automáticos** con retención configurable y upload a Wasabi S3
- **Monitoreo integrado** con notificaciones al sistema ADN
- **Health checks** automáticos con alertas
- **Alta disponibilidad** con configuraciones optimizadas para producción

## 🚀 Inicio Rápido

```bash
# 1. Clonar repositorio
git clone <repository-url>
cd adn-docker-mariadb-template

# 2. Configurar variables de entorno
cp .env.example .env
nano .env  # Editar contraseñas y configuración

# 3. Iniciar contenedor
docker compose up -d

# 4. Verificar
docker compose ps
```

## ⚙️ Configuración

### Variables de Entorno Principales

Edita el archivo `.env`:

```env
# Contenedor
CONTAINER_NAME=mariadb-client-001
VOLUME_NAME=mariadb_client_001_data
NETWORK_NAME=mariadb_client_001_network

# MariaDB
MYSQL_ROOT_PASSWORD=cambiar_por_password_seguro
MYSQL_DATABASE=sistemasadn
MYSQL_USER=sistemas
MYSQL_PASSWORD=adn
MYSQL_PORT=3306
TIMEZONE=America/Caracas
```

### Configuración de Backups y Wasabi S3 (Opcional)

```env
# Backups
BACKUP_ENABLED=true
BACKUP_SCHEDULE=0 2 * * *
BACKUP_RETENTION_DAYS=7

# Wasabi S3
WASABI_UPLOAD_ENABLED=true
WASABI_ACCESS_KEY=tu_access_key
WASABI_SECRET_KEY=tu_secret_key
WASABI_BUCKET=tu-bucket-backups
WASABI_REGION=us-east-1
WASABI_ENDPOINT=https://s3.us-east-1.wasabisys.com

# Formato de nombre de backup
SERVER_NAME=servidor-produccion
CLIENT_NAME=cliente-001
```

**⚠️ Importante:** Cambia todas las contraseñas y credenciales antes de usar en producción.

## 📁 Estructura del Proyecto

```
📦 adn-docker-mariadb-template/
├── docker-compose.yml          # Configuración Docker Compose
├── Dockerfile                  # Dockerfile personalizado
├── .env.example                # Plantilla de configuración
├── .env.monitor.example      # Configuración de monitoreo
├── config/
│   └── my.cnf                  # Configuración optimizada de MariaDB
├── init/
│   └── 00-create-user.sql      # Script de inicialización (usuario 'sistemas')
├── scripts/                    # Scripts de gestión
│   ├── backup-all.sh           # Backup de todas las BDs + Wasabi
│   ├── backup-notify.sh        # Backup con notificación al sistema ADN
│   ├── check-repair.sh         # Verificación y reparación de tablas
│   ├── configure-cron.sh       # Configuración masiva de cron
│   ├── entrypoint.sh           # Entrypoint personalizado
│   ├── health-check.sh         # Verificación de salud básica
│   ├── health-check-notify.sh  # Health check con notificación
│   ├── install.sh              # Instalación en un contenedor
│   ├── install-all.sh          # Instalación masiva en todos los contenedores
│   ├── restore.sh              # Restauración de backups
│   ├── test-manual.sh          # Pruebas manuales
│   ├── update-scripts.sh       # Actualización masiva de scripts
│   └── wasabi-upload.sh        # Upload a Wasabi S3
├── docs/                       # Documentación detallada
│   ├── CONFIGURACION-CONTENEDORES.md
│   ├── INICIO-RAPIDO.md
│   ├── INSTALACION.md
│   ├── RESUMEN-EJECUTIVO.md
│   ├── WORKFLOW.md
│   └── requerimiento.md
└── README.md                   # Este archivo
```

## 🛠️ Scripts de Gestión

### Scripts de Nivel Servidor (Gestión Masiva)

| Script | Descripción | Uso |
|--------|-------------|-----|
| `install-all.sh` | Instala scripts en **todos** los contenedores del servidor | Primera instalación |
| `update-scripts.sh` | Actualiza scripts en todos los contenedores | Después de `git pull` |
| `configure-cron.sh` | Configura cron en todos los contenedores | Programar tareas |

### Scripts de Nivel Contenedor (Copiados a cada contenedor)

| Script | Descripción |
|--------|-------------|
| `backup-all.sh` | Backup de todas las bases de datos + upload a Wasabi |
| `backup-notify.sh` | Backup con notificación al sistema de monitoreo ADN |
| `health-check.sh` | Verificación básica de salud del contenedor |
| `health-check-notify.sh` | Health check con notificación al sistema |
| `wasabi-upload.sh` | Subida de backups a Wasabi S3 |
| `check-repair.sh` | Verificación y reparación automática de tablas |
| `restore.sh` | Restauración de backups desde archivo |

## � Gestión de Contenedores

### Instalación Masiva (en servidor)

```bash
# Instalar en TODOS los contenedores del servidor
./scripts/install-all.sh

# Actualizar scripts después de cambios
git pull
./scripts/update-scripts.sh

# Configurar cron en todos los contenedores
./scripts/configure-cron.sh sistemasadn
```

### Comandos Docker Compose

```bash
# Gestión básica
docker compose up -d              # Iniciar
docker compose stop               # Detener
docker compose restart            # Reiniciar
docker compose down               # Eliminar (mantiene datos)
docker compose down -v            # Eliminar TODO (incluyendo datos)
docker compose ps                 # Ver estado
docker compose logs -f            # Ver logs en tiempo real

# Acceso
docker compose exec mariadb mysql -u root -p
docker compose exec mariadb mysql -u sistemas -p
```

### Scripts de Utilidad (requieren variables de entorno)

```bash
# Cargar variables y ejecutar scripts
export $(cat .env | xargs)

./scripts/health-check.sh              # Verificar salud
./scripts/backup-all.sh                # Backup de todas las BDs
./scripts/backup-all.sh [nombre_bd]    # Backup de una BD específica
./scripts/restore.sh [archivo.sql.gz]   # Restaurar backup
```

## � Backups y Wasabi S3

### Backup Automático

Los backups se ejecutan automáticamente según la programación configurada:

```bash
# Formato del archivo: backup_[nombre_bd]_[YYYYMMDD_HHMMSS].sql.gz
# Ejemplo: backup_sistemasadn_20240115_020000.sql.gz
```

### Configuración de Wasabi S3

1. Configura tus credenciales Wasabi en `.env`
2. El nombre del backup en S3 seguirá el formato:
   `SERVIDOR-PUERTO-CLIENTE-BASEDATOS-FECHAHORA.sql.gz`

### Retención de Backups

- **Local**: Se mantienen por el número de días configurado en `BACKUP_RETENTION_DAYS`
- **Wasabi S3**: Se mantienen los últimos 7 backups por base de datos

## 🔧 Configuración de MariaDB

### Optimizaciones Incluidas (`config/my.cnf`)

- **Buffer Pool**: 2GB optimizado para bases de datos de ~1.5GB
- **Conexiones**: 200 conexiones máximas
- **NVMe Optimizado**: I/O capacity ajustada para discos rápidos
- **Sin replicación**: Logs binarios desactivados para ahorrar recursos
- **lower_case_table_names=1**: Compatibilidad con migraciones desde Windows

### Usuario Predeterminado

- **Usuario**: `sistemas`
- **Contraseña**: `adn` (cambiar en producción)
- **Permisos**: Acceso completo a todas las bases de datos

## 📚 Documentación

Para información detallada, consulta la carpeta `docs/`:

| Documento | Contenido |
|-----------|-----------|
| `RESUMEN-EJECUTIVO.md` | Visión general del sistema |
| `WORKFLOW.md` | Proceso completo paso a paso |
| `INSTALACION.md` | Guía detallada de instalación |
| `CONFIGURACION-CONTENEDORES.md` | Configuración de contenedores |
| `INICIO-RAPIDO.md` | Guía rápida para pruebas |

## 🔒 Seguridad

- `.gitignore` protege archivos `.env` y credenciales
- Credenciales almacenadas en variables de entorno
- No se exponen contraseñas en logs
- Backups comprimidos y cifrados en tránsito a Wasabi

## ⚡ Características

- ✅ MariaDB 10.5 optimizado para producción
- ✅ Configuración de alto rendimiento para NVMe
- ✅ Health checks automáticos con notificaciones
- ✅ Backups automáticos con retención configurable
- ✅ Integración con Wasabi S3 para almacenamiento seguro
- ✅ Sistema de monitoreo ADN integrado
- ✅ Gestión masiva de múltiples contenedores
- ✅ Zona horaria: Caracas, Venezuela
- ✅ Soporte para migraciones desde Windows

## 📝 Requisitos

- Docker 20.10+
- Docker Compose 2.0+
- Linux (optimizado para servidores Netcup)
- 4GB RAM mínimo recomendado por contenedor

---

**ADN Software** | **Versión**: 2.0.0 | **MariaDB**: 10.5 | **Optimizado para**: Producción y modelo SaaS multi-cliente
