BEGIN;
CREATE TABLE IF NOT EXISTS public.stg_existencias_familia (
  pr_almacen      TEXT,
  pr_clave        TEXT,
  pr_descripcion  TEXT,
  pr_costo        NUMERIC(12,4),
  pr_existencia   INTEGER,
  proveedor       TEXT,
  ps_nombre       TEXT,
  clasificacion   TEXT,
  source          TEXT DEFAULT 'familia',
  load_ts         TIMESTAMPTZ DEFAULT now()
);
COMMIT;
