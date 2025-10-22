# Changelog

## [V3_final] - 2025-08-28

### Added
- Script consolidado `V3_final__modelo_dimensional_y_carga.sql` (modelo dimensional + carga desde CSV).
- Script `V5_final_vistas.sql` con todas las vistas por `articulo_clave` (DROP CASCADE + CREATE).
- Nuevos README:
  - `README_migraciones_V3_final_v2.md`
  - `README_vistas_UI.md`
  - `README_instalacion_fresh.md`

### Changed
- Modalidad FIRME ahora incluye prefijo `NA` (además de AFF, AF, F, FF).
- Proveedor principal siempre tomado del CSV (reglas UNICO/VALIDADO).
- Rebuild completo del puente `articulo_proveedor` desde staging.
- Limpieza de residuos (prefijos con ceros).

### Fixed
- Claves con múltiples proveedores por ceros extra (ej. 200/2000).
- Inconsistencias viejas en CSV (ej. clave con proveedor distinto por almacén).
## [V4] - 2025-09-01

### Added
- Script `V4__fact_inventario_y_snapshot.sql` para creación de tabla `fact_inventario` y snapshots.
- Script `V4b__snapshot_replace.sql` para reemplazos consistentes en snapshots.

### Changed
- Ajustes en modelo dimensional para permitir fact tables vinculadas a inventario histórico.

---

## [V5] - 2025-09-05

### Added
- Scripts de vistas extendidas:
  - `V5__vistas_inventario.sql`
  - `V5b__vistas_inventario_ext.sql`
  - `V5c__vista_inventario_por_articulo.sql`
  - `V5d__drop_and_create_vistas_por_clave.sql`
  - `V5e__vistas_derivadas_familia_y_proveedor.sql`
- Script consolidado `V5__final_vistas.sql`.

### Changed
- Se unificaron vistas en un solo entrypoint para consultas por `articulo_clave`.
- Mayor claridad en derivadas por familia y proveedor.

---

## [V6] - 2025-09-07

### Added
- Script `V6__dim_familia_y_fk.sql` para crear dimensión familia con llaves foráneas.
- Script `V6a__stg_existencias_familia.sql` para staging de existencias por familia.

### Changed
- Reestructuración de la relación `dim_articulo` ↔ `dim_familia`.
- Integración del CSV `clasif_masivo.csv` como fuente de clasificación.

---

## [Dataset Demo] - 2025-09-08

### Changed
- Sustituido `existencias_demo.csv` por `existencias_clasificacion_demo.csv` (incluye columna de clasificación).
- Actualizados ejemplos de carga en RUNBOOK.

---

## [Ventas] - 2025-09-09

### Added
- Procedimiento en RUNBOOK para carga de **reportes de ventas** con periodos dinámicos (2, 6, 12 meses).
- Uso de dataset demo de ventas para pruebas E2E en CLI MVP-1.
