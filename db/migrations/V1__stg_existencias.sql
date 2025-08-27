-- V1__stg_existencias.sql
-- Crea la tabla de staging para existencias (seguro de re-ejecutar)
CREATE TABLE IF NOT EXISTS stg_existencias (
  pr_almacen      TEXT,
  pr_clave        TEXT,
  pr_descripcion  TEXT,
  pr_costo        NUMERIC(12,4),
  pr_existencia   INTEGER,
  proveedor       TEXT,
  ps_nombre       TEXT
);
