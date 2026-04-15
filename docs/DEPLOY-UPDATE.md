# Script de Actualización Masiva - deploy-update.sh

## Descripción

Script para actualizar automáticamente todos los contenedores MariaDB de un servidor o uno específico cuando se realizan cambios en la plantilla base.

## Características

- ✅ Backup automático antes de actualizar
- ✅ Actualiza Dockerfile, docker-compose.yml, .dockerignore y carpeta scripts
- ✅ Detecta automáticamente contenedores MariaDB válidos
- ✅ Respeta el estado de los contenedores (no inicia los que estaban detenidos)
- ✅ Protege los volúmenes de datos
- ✅ Modo individual o masivo

## Configuración

### Variables de Entorno (.env)

```bash
# Ruta donde están los contenedores MariaDB en el servidor
MARIADB_CONTAINERS_PATH=/var/docker-data/mariadb

# Ruta donde se guardarán los backups de contenedores
BACKUP_PATH=/home/adn/backup/contenedores
```

## Uso

### Actualizar todos los contenedores

```bash
./scripts/deploy-update.sh
```

**Proceso:**
1. Crea backup comprimido de toda la carpeta `/var/docker-data/mariadb/`
2. Detecta todos los contenedores MariaDB válidos
3. Para cada contenedor:
   - Detiene el contenedor (solo si estaba corriendo)
   - Actualiza archivos y scripts
   - Reconstruye e inicia (solo si estaba corriendo antes)

### Actualizar un contenedor específico

```bash
./scripts/deploy-update.sh 3313-mora-y-garcia
```

**Proceso:**
1. Crea backup comprimido solo de ese contenedor
2. Detiene el contenedor (solo si estaba corriendo)
3. Actualiza archivos y scripts
4. Reconstruye e inicia (solo si estaba corriendo antes)

## Archivos que se Actualizan

### Archivos Individuales
- `Dockerfile`
- `docker-compose.yml`
- `.dockerignore`

### Directorios Completos
- `scripts/` (todo el contenido)

## Detección de Contenedores

El script detecta automáticamente contenedores MariaDB válidos verificando:
- Existencia de `docker-compose.yml`
- Existencia de `Dockerfile`

**Estructura esperada:**
```
/var/docker-data/mariadb/
├── 3313-mora-y-garcia/
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── .dockerignore
│   ├── scripts/
│   └── ...
├── 3314-comercializadora-choco-gourmet/
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── ...
```

## Protección de Datos

### ✅ Lo que SÍ se actualiza:
- Archivos de configuración (Dockerfile, docker-compose.yml)
- Scripts de la carpeta `scripts/`
- Archivos de ignorar (.dockerignore)

### ❌ Lo que NO se toca:
- Volúmenes de datos (`mariadb_data`)
- Volúmenes de backups (`mariadb_backups`)
- Archivo `.env` del contenedor
- Carpetas `init/` y `config/`

## Backups

### Backup Masivo
```bash
# Archivo generado
/home/adn/backup/contenedores/all_mariadb_containers_20260414_230500.tar.gz
```

### Backup Individual
```bash
# Archivo generado
/home/adn/backup/contenedores/3313-mora-y-garcia_20260414_230500.tar.gz
```

## Flujo de Trabajo Recomendado

### 1. Desarrollo en Template
```bash
cd /home/aleguizamon/ADN/adn-servers-manager/adn-docker-mariadb-template
# Hacer cambios en Dockerfile, scripts, etc.
git add .
git commit -m "feat: nueva funcionalidad"
git push
```

### 2. Actualizar en Servidor de Producción
```bash
# Conectar al servidor
ssh adn@db-netcup3

# Ir a la plantilla
cd /ruta/a/adn-docker-mariadb-template

# Actualizar template desde git
git pull

# Probar en un contenedor específico primero
./scripts/deploy-update.sh 3313-mora-y-garcia

# Si todo funciona bien, actualizar todos
./scripts/deploy-update.sh
```

## Ejemplo de Salida

```
[10:30:15] ════════════════════════════════════════════════════════════════
[10:30:15] ACTUALIZACIÓN DE CONTENEDORES MARIADB
[10:30:15] ════════════════════════════════════════════════════════════════
[10:30:15] Template: /home/aleguizamon/ADN/adn-servers-manager/adn-docker-mariadb-template
[10:30:15] Contenedores: /var/docker-data/mariadb
[10:30:15] Backups: /home/adn/backup/contenedores
[10:30:15] ════════════════════════════════════════════════════════════════

[10:30:15] Creando backup de todos los contenedores MariaDB...
[✓] Backup completo creado: /home/adn/backup/contenedores/all_mariadb_containers_20260414_103015.tar.gz

[10:30:20] ═══════════════════════════════════════════════════════════════
[10:30:20] Procesando contenedor: 3313-mora-y-garcia
[10:30:20] ═══════════════════════════════════════════════════════════════
[INFO] Contenedor está corriendo, será detenido temporalmente
[10:30:20] Deteniendo contenedor...
[✓] Contenedor detenido
[10:30:22] Actualizando archivos en: 3313-mora-y-garcia
[INFO]   Copiando Dockerfile...
[INFO]   Copiando docker-compose.yml...
[INFO]   Copiando .dockerignore...
[INFO]   Actualizando directorio scripts...
[✓] Archivos actualizados en: 3313-mora-y-garcia
[10:30:25] Reconstruyendo e iniciando contenedor...
[✓] Contenedor reconstruido e iniciado
[✓] Actualización completada: 3313-mora-y-garcia

[10:30:30] ════════════════════════════════════════════════════════════════
[10:30:30] RESUMEN DE ACTUALIZACIÓN
[10:30:30] ════════════════════════════════════════════════════════════════
[INFO] Total procesados: 37
[✓] Exitosos: 37
[10:30:30] ════════════════════════════════════════════════════════════════
[✓] Proceso completado
```

## Casos de Uso

### Actualizar scripts de backup
```bash
# 1. Modificar scripts/backup-complete.sh en template
# 2. Desplegar a todos los contenedores
./scripts/deploy-update.sh
```

### Cambiar configuración de cron
```bash
# 1. Modificar scripts/entrypoint.sh en template
# 2. Probar en un contenedor
./scripts/deploy-update.sh 3313-mora-y-garcia
# 3. Si funciona, desplegar a todos
./scripts/deploy-update.sh
```

### Actualizar Dockerfile (nueva versión de MariaDB)
```bash
# 1. Modificar Dockerfile en template
# 2. Probar en contenedor de prueba primero
./scripts/deploy-update.sh 3313-mora-y-garcia
# 3. Verificar que funciona correctamente
# 4. Desplegar gradualmente o a todos
./scripts/deploy-update.sh
```

## Solución de Problemas

### El script no encuentra contenedores
```bash
# Verificar que la ruta es correcta
ls -l /var/docker-data/mariadb/

# Verificar variables en .env
cat .env | grep MARIADB_CONTAINERS_PATH
```

### Error al detener contenedor
```bash
# Detener manualmente
cd /var/docker-data/mariadb/3313-mora-y-garcia
docker-compose down

# Luego ejecutar actualización
./scripts/deploy-update.sh 3313-mora-y-garcia
```

### Restaurar desde backup
```bash
# Detener contenedor
cd /var/docker-data/mariadb/3313-mora-y-garcia
docker-compose down

# Restaurar desde backup
cd /var/docker-data/mariadb
rm -rf 3313-mora-y-garcia
tar -xzf /home/adn/backup/contenedores/3313-mora-y-garcia_20260414_103015.tar.gz

# Iniciar contenedor
cd 3313-mora-y-garcia
docker-compose up -d
```

## Seguridad

- ✅ Los backups se crean ANTES de cualquier modificación
- ✅ Los volúmenes de datos nunca se tocan
- ✅ El script verifica archivos necesarios antes de comenzar
- ✅ Si un contenedor falla, los demás continúan (modo masivo)
- ✅ Los contenedores detenidos no se inician automáticamente

## Notas Importantes

1. **Siempre probar primero en un contenedor**: Usa el modo individual antes de actualizar todos
2. **Verificar backups**: Los backups se guardan en `BACKUP_PATH`
3. **Espacio en disco**: Asegúrate de tener suficiente espacio para los backups
4. **Permisos**: El script debe ejecutarse con permisos para acceder a Docker
5. **Estado de contenedores**: El script respeta el estado original (corriendo/detenido)
