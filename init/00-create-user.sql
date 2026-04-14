-- ============================================
-- Script de Inicialización - Usuario, Permisos y Bases de Datos
-- ============================================

-- Crear usuario 'sistemas' con contraseña 'adn'
CREATE USER IF NOT EXISTS 'sistemas'@'%' IDENTIFIED BY 'adn';
CREATE USER IF NOT EXISTS 'sistemas'@'localhost' IDENTIFIED BY 'adn';

-- Otorgar todos los permisos en todas las bases de datos
GRANT ALL PRIVILEGES ON *.* TO 'sistemas'@'%' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'sistemas'@'localhost' WITH GRANT OPTION;

-- Crear las bases de datos
-- CREATE DATABASE IF NOT EXISTS `sistemasadn`;
-- CREATE DATABASE IF NOT EXISTS `gcreport`;
-- CREATE DATABASE IF NOT EXISTS `componentes`;
-- CREATE DATABASE IF NOT EXISTS `auditor`;
-- CREATE DATABASE IF NOT EXISTS `adn`;

-- Aplicar cambios
FLUSH PRIVILEGES;

-- Verificación
SELECT User, Host FROM mysql.user WHERE User = 'sistemas';
SHOW DATABASES;
