# Proyecto: Contenedor Docker con MariaDB para Modelo SaaS

## Objetivo

Crear un proyecto Docker estandarizado con MariaDB 10.5 que pueda ser distribuido a clientes para instalación en sus propios servidores.

## Contexto del Modelo de Negocio

- **Arquitectura**: Modelo SaaS con bases de datos localizadas por cliente
- **Escalabilidad**: Múltiples clientes, cada uno con su propia instancia de MariaDB
- **Despliegue**: Cada cliente tendrá su contenedor Docker independiente con su base de datos dedicada

## Requisitos Técnicos

### Base de Datos
- **Motor**: MariaDB 10.5
- **Acceso externo**: La base de datos debe ser accesible desde aplicaciones externas
- **Conectividad**: Inicialmente se probará con HTTPS

### Entorno de Desarrollo
- **Sistema operativo local**: macOS
- **Herramientas**: Docker instalado
- **Plataforma de pruebas**: Railway (para validación antes de entrega a clientes)

## Estrategia de Implementación

1. **Fase de desarrollo local**:
   - Configurar y validar el contenedor Docker en macOS
   - Asegurar que la configuración funcione correctamente

2. **Fase de pruebas**:
   - Desplegar en Railway para validación en entorno cloud
   - Verificar accesibilidad externa y conectividad

3. **Fase de entrega**:
   - Documentar instrucciones completas de despliegue
   - Proporcionar al cliente el proyecto estandarizado listo para instalar

## Entregables

- Proyecto Docker configurado y funcional
- Base de datos MariaDB 10.5 lista para uso
- Documentación detallada de instalación y despliegue
- Instrucciones para configuración en servidores del cliente