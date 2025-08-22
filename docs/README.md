# 📊 Análisis de Inventario Predictivo  

Este proyecto busca desarrollar un sistema de análisis y distribución de inventario con enfoque predictivo.  
El sistema integrará reportes de **existencias actuales**, **ventas históricas por tienda** y **rotación de inventarios** para generar **sugerencias automáticas de distribución y adquisición** de productos.  

Se utilizará la metodología **Agile Kanban con cadencia semanal** y el enfoque **Dual-Track (Descubrimiento + Entrega en paralelo)** para asegurar un desarrollo ágil, iterativo y orientado al valor.  

---

## 🚀 Objetivos  
- Desarrollar un sistema que **automatice sugerencias de distribución** de inventario.  
- Aplicar **modelos predictivos** basados en ventas históricas y rotación.  
- Permitir la **priorización de artículos críticos** (ejemplo: artículos F deben distribuirse primero).  
- Integrar los reportes en un flujo claro para la toma de decisiones.  
- Practicar y consolidar el uso de **metodologías ágiles** en el desarrollo de software.  

---

## 📌 Metodología de Trabajo  
- **Kanban (GitHub Projects):**  
  - Cadencia semanal.  
  - Columnas: *Backlog*, *In Progress*, *Review*, *Done*.  
- **Dual-Track Agile:**  
  - **Descubrimiento:** Definición de requerimientos, validación de hipótesis, análisis de datos (Python).  
  - **Entrega:** Implementación en código, conexión a base de datos, pruebas y documentación (C y PostgreSQL).  

---

## 📂 Estructura del Proyecto (inicial)  
/db
  /migrations/        # Flyway OR Sqitch (elige una)
  /seed/              # CSVs ejemplo, loaders
  /functions/         # SQL de funciones/vistas (opcional, si no va en migrations)
  schema.sql          # snapshot referencia (solo lectura)
/src
  /py
    /etl/             # carga CSV → DB (psycopg)
    /logic/           # reglas (F/C), prototipos ML
    /ui/              # app mínima (CLI/API)
    __init__.py
  /c
    /logic/           # reglas críticas, libpq
    /bindings/        # (opcional) interfaz C↔Python si aplica
    Makefile
/tests
  /sql/               # pgTAP
  /python/            # pytest
  /c/                 # cmocka/Unity (opcional)
/docs
  ADR-0001-docker-vs-vm.md
  ADR-0002-sku-base.md
  RUNBOOK.md
  README.md
/infra
  docker-compose.yml
  Dockerfile.app      # imagen para src/py
  Dockerfile.db       # imagen postgres si personalizas
  flyway.conf         # o sqitch.conf, según elección
/config
  app.example.toml    # config de la app
  db.example.toml
.env.example
Makefile              # orquesta: lint, test, migrate, seed
.github/workflows/ci.yml

---

## 🛠️ Tecnologías y Herramientas  
- **Lenguajes:**  
  - **Python** → Prototipado rápido y análisis predictivo (`pandas`, `psycopg2`).  
  - **C** → Implementación robusta y eficiente (`libpq`).  
- **Base de datos:** PostgreSQL.  
- **Gestión de proyecto:** GitHub Projects + Issues.  
- **Metodología:** Agile Kanban + Dual-Track.  
- **Control de versiones:** Git.  

---

## 🤝 Contribución  
1. Clonar el repositorio.  
2. Crear una rama con la convención `feature/nombre-funcionalidad`.  
3. Hacer commit siguiendo buenas prácticas.  
4. Crear Pull Request para revisión.  

---

## 📅 Avance Semanal  
El progreso se registrará en el tablero Kanban de GitHub Projects.  
Cada semana se revisarán los objetivos alcanzados y se planearán los siguientes pasos.  
