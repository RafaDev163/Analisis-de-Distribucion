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
