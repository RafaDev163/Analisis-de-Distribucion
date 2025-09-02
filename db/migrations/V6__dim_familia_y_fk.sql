--Mantiene linea_familia (el dígito de la clave) y agrega familia_id sin romper nada de lo previo

BEGIN;

CREATE EXTENSION IF NOT EXISTS unaccent;

CREATE TABLE IF NOT EXISTS dim_familia (
  familia_id        BIGSERIAL PRIMARY KEY,
  familia_codigo    TEXT NOT NULL UNIQUE,     -- ← clave oficial de familia
  familia_nombre    TEXT NOT NULL,
  doi_min           INT  NOT NULL DEFAULT 7,
  doi_max           INT  NOT NULL DEFAULT 14,
  multiplo_empaque  INT  NOT NULL DEFAULT 1,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ
);

ALTER TABLE dim_familia
  ADD CONSTRAINT chk_doi_rango CHECK (doi_min > 0 AND doi_max >= doi_min),
  ADD CONSTRAINT chk_multiplo  CHECK (multiplo_empaque > 0);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='dim_articulo' AND column_name='familia_id'
  ) THEN
    ALTER TABLE dim_articulo
      ADD COLUMN familia_id BIGINT NULL REFERENCES dim_familia(familia_id);
  END IF;
END$$;

CREATE INDEX IF NOT EXISTS idx_dim_familia_codigo ON dim_familia (familia_codigo);
CREATE INDEX IF NOT EXISTS idx_dim_articulo_familia ON dim_articulo (familia_id);

COMMIT;
