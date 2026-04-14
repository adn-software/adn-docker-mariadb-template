# 🐳 MariaDB 10.5 Docker - Proyecto SaaS

Contenedor Docker con MariaDB 10.5 optimizado para alto tráfico y modelo SaaS con bases de datos localizadas por cliente.

## 🚀 Inicio Rápido

```bash
# 1. Clonar repositorio
git clone <repository-url>
cd adn-test-docker-mariadb

# 2. Configurar variables de entorno
cp .env.example .env
nano .env  # Editar contraseñas

# 3. Iniciar contenedor
docker compose up -d

# 4. Verificar
docker compose ps
```

## ⚙️ Configuración

Edita el archivo `.env`:

```env
# Contenedor
CONTAINER_NAME=mariadb-client-001
VOLUME_NAME=mariadb_client_001_data
NETWORK_NAME=mariadb_client_001_network

# Base de datos
MYSQL_ROOT_PASSWORD=tu_password_seguro
MYSQL_DATABASE=sistemasadn
MYSQL_USER=sistemas
MYSQL_PASSWORD=adn

# Puerto y zona horaria
MYSQL_PORT=3306
TIMEZONE=America/Caracas
```

**⚠️ Importante:** Cambia las contraseñas antes de usar en producción.

## 🗄️ Bases de Datos Incluidas

Al iniciar el contenedor, se crean automáticamente las siguientes bases de datos:

1. **sistemasadn** - Sistema principal
2. **gcreport** - Reportes
3. **componentes** - Componentes del sistema
4. **auditor** - Auditoría
5. **new_aquazul** - Base de datos ADN

**Usuario:** `sistemas` con contraseña `adn` tiene acceso completo a todas las bases de datos.

## 📁 Estructura

```
📦 mariadb-docker/
├── docker-compose.yml      # Configuración Docker
├── .env.example            # Plantilla de configuración
├── config/my.cnf           # Configuración MySQL (alto tráfico)
├── init/                   # Scripts de inicialización (se ejecutan en orden)
│   ├── 00-create-user.sql  # Crea usuario 'sistemas' y bases de datos
│   ├── 01-SISTEMASADN.sql  # Tablas para sistemasadn
│   ├── 02-GCREPORT.sql     # Tablas para gcreport
│   ├── 03-COMPONENTES.sql  # Tablas para componentes
│   ├── 04-AUDITOR.sql      # Tablas para auditor
│   └── 05-ADN.sql          # Tablas para new_aquazul
└── scripts/
    ├── backup.sh           # Backup automático
    ├── restore.sh          # Restauración
    └── health-check.sh     # Verificación de salud
```

## 🛠️ Comandos Útiles

```bash
# Gestión del contenedor
docker compose up -d          # Iniciar
docker compose stop           # Detener
docker compose restart        # Reiniciar
docker compose down           # Eliminar (mantiene datos)
docker compose down -v        # Eliminar todo (incluyendo datos)
docker compose ps             # Ver estado
docker compose logs -f        # Ver logs

# Acceso a MySQL
docker compose exec mariadb mysql -u sistemas -p

# Ver bases de datos creadas
docker compose exec mariadb mysql -u sistemas -padn -e "SHOW DATABASES;"

# Scripts de utilidad
export $(cat .env | xargs) && ./scripts/health-check.sh  # Verificar salud
export $(cat .env | xargs) && ./scripts/backup.sh        # Crear backup
export $(cat .env | xargs) && ./scripts/restore.sh [archivo]  # Restaurar
```

## 📊 Backups Automáticos

```bash
# Crear script de backup
cat > /opt/backup-mariadb.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/opt/backups/mariadb"
DATE=$(date +%Y%m%d_%H%M%S)
docker exec mariadb-client-001 mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" client_database | gzip > $BACKUP_DIR/backup_$DATE.sql.gz
find $BACKUP_DIR -name "backup_*.sql.gz" -mtime +7 -delete
EOF

chmod +x /opt/backup-mariadb.sh

# Programar con cron (diario a las 2 AM)
crontab -e
# Agregar: 0 2 * * * /opt/backup-mariadb.sh
```

## ⚡ Características

- ✅ MariaDB 10.5 optimizado para alto tráfico (500 conexiones)
- ✅ Buffer pool de 2GB (ajustable según RAM)
- ✅ Acceso externo habilitado (bind-address 0.0.0.0)
- ✅ Health checks automáticos
- ✅ Zona horaria: Caracas, Venezuela
- ✅ 5 bases de datos pre-configuradas (sistemasadn, gcreport, componentes, auditor, new_aquazul)
- ✅ Usuario 'sistemas' con acceso completo
- ✅ Scripts de backup/restore incluidos

---

**Versión**: 1.0.0 | **MariaDB**: 10.5 | **Optimizado para**: Alto tráfico y modelo SaaS
