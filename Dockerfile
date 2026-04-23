FROM mariadb:10.5

# Instalar cron, AWS CLI y jq para backups y uploads a Wasabi
RUN apt-get update && apt-get install -y \
    cron \
    curl \
    unzip \
    python3 \
    python3-pip \
    jq \
    && pip3 install awscli \
    && rm -rf /var/lib/apt/lists/*
    
# Configurar variables de entorno usando ARG para build-time
ARG MYSQL_ROOT_PASSWORD
ARG MYSQL_DATABASE
ARG MYSQL_USER
ARG MYSQL_PASSWORD
ARG TIMEZONE=America/Caracas

# MariaDB 10.5+ requiere MARIADB_* en runtime
ENV MARIADB_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
ENV MARIADB_DATABASE=${MYSQL_DATABASE}
ENV MARIADB_USER=${MYSQL_USER}
ENV MARIADB_PASSWORD=${MYSQL_PASSWORD}
ENV TZ=${TIMEZONE}

# Copiar archivos de configuración
COPY config/my.cnf /etc/mysql/conf.d/custom.cnf

# Copiar scripts de inicialización
COPY init/*.sql /docker-entrypoint-initdb.d/

# Copiar scripts esenciales
COPY scripts/entrypoint.sh /usr/local/bin/custom-entrypoint.sh
COPY scripts/backup-complete.sh /usr/local/bin/backup-complete.sh
COPY scripts/health-check-complete.sh /usr/local/bin/health-check-complete.sh
COPY scripts/wasabi-upload.sh /usr/local/bin/wasabi-upload.sh
RUN chmod +x /usr/local/bin/custom-entrypoint.sh /usr/local/bin/backup-complete.sh /usr/local/bin/health-check-complete.sh /usr/local/bin/wasabi-upload.sh

# Exponer puerto
EXPOSE 3306

# Healthcheck
HEALTHCHECK --interval=10s --timeout=5s --retries=5 --start-period=30s \
  CMD mysqladmin ping -h localhost -u root -p${MYSQL_ROOT_PASSWORD} || exit 1

# Usar entrypoint personalizado que configura cron automáticamente
ENTRYPOINT ["/usr/local/bin/custom-entrypoint.sh"]
