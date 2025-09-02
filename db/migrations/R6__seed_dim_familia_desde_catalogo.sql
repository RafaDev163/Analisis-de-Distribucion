-- R6__seed_dim_familia_desde_catalogo.sql
-- Carga catálogo de familias desde CSV.
-- Soporta CSV con 2 columnas (familia_codigo,familia_nombre)
-- o con 5 columnas (familia_codigo,familia_nombre,doi_min,doi_max,multiplo_empaque).

BEGIN;

-- 1) Staging
DROP TABLE IF EXISTS stg_familia_catalogo;
CREATE TABLE stg_familia_catalogo (
  familia_codigo     TEXT,
  familia_nombre     TEXT,
  doi_min            INT,
  doi_max            INT,
  multiplo_empaque   INT
);

-- 2) COPY flexible
-- Opción A (CSV con SOLO 2 columnas: familia_codigo,familia_nombre)
--   -> Descomenta este COPY si tu archivo tiene SOLO esas 2 columnas:
COPY stg_familia_catalogo (familia_codigo, familia_nombre)
FROM '/sql/clasif_masivo.csv'
WITH (FORMAT csv, HEADER true, NULL '');

-- Opción B (CSV con 5 columnas: incluye doi/multiplo)
--   -> Si tuvieras las 5 columnas, comenta el COPY de arriba y descomenta este:
-- COPY stg_familia_catalogo (familia_codigo, familia_nombre, doi_min, doi_max, multiplo_empaque)
-- FROM '/sql/clasif_masivo_utf8.csv'
-- WITH (FORMAT csv, HEADER true, NULL '');

-- 3) Normalización y defaults
WITH base AS (
  SELECT DISTINCT
         NULLIF(TRIM(familia_codigo),'')                        AS familia_codigo,
         NULLIF(TRIM(familia_nombre),'')                        AS familia_nombre,
         COALESCE(NULLIF(doi_min,0), 7)                         AS doi_min,
         COALESCE(NULLIF(doi_max,0), 14)                        AS doi_max,
         COALESCE(NULLIF(multiplo_empaque,0), 1)                AS multiplo_empaque
  FROM stg_familia_catalogo
)
INSERT INTO dim_familia (familia_codigo, familia_nombre, doi_min, doi_max, multiplo_empaque, updated_at)
SELECT b.familia_codigo, b.familia_nombre, b.doi_min, b.doi_max, b.multiplo_empaque, now()
FROM base b
WHERE b.familia_codigo IS NOT NULL AND b.familia_nombre IS NOT NULL
ON CONFLICT (familia_codigo) DO UPDATE
  SET familia_nombre   = EXCLUDED.familia_nombre,
      doi_min          = EXCLUDED.doi_min,
      doi_max          = EXCLUDED.doi_max,
      multiplo_empaque = EXCLUDED.multiplo_empaque,
      updated_at       = now();

-- 4) Asegurar constraints si venías de una V6 sin UNIQUE/NOT NULL en familia_codigo
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'dim_familia_familia_codigo_key'
  ) THEN
    ALTER TABLE dim_familia ADD CONSTRAINT dim_familia_familia_codigo_key UNIQUE (familia_codigo);
  END IF;
END$$;

COMMIT;
