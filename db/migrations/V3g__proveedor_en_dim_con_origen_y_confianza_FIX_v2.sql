-- V3g__proveedor_en_dim_con_origen_y_confianza_FIX_v2.sql
-- Corregido: evita COUNT(DISTINCT ...) OVER (...) (no soportado en ventana)
-- Usa subconsultas con GROUP BY para contar proveedores distintos por clave.
-- Estrategia: A) UNICO, C) VALIDADO (B DOMINANTE opcional, comentada)

BEGIN;

-- 0) Asegurar metadatos en dim_articulo
ALTER TABLE dim_articulo
  ADD COLUMN IF NOT EXISTS proveedor_codigo     TEXT,
  ADD COLUMN IF NOT EXISTS proveedor_cod_origen TEXT,    -- 'UNICO' | 'VALIDADO' | 'DOMINANTE'
  ADD COLUMN IF NOT EXISTS proveedor_confiable  BOOLEAN; -- TRUE cuando origen es UNICO o VALIDADO

-- 1) Opción A: ÚNICO proveedor por clave (confiable)
WITH d AS (
  SELECT DISTINCT
    s.pr_clave,
    NULLIF(btrim(s.proveedor),'') AS proveedor
  FROM stg_existencias s
  WHERE s.pr_clave IS NOT NULL
),
c AS (
  SELECT pr_clave, COUNT(*) AS n_prov_dist
  FROM d
  GROUP BY pr_clave
),
only_one AS (
  SELECT d.pr_clave, d.proveedor
  FROM d
  JOIN c USING (pr_clave)
  WHERE c.n_prov_dist = 1 AND d.proveedor IS NOT NULL
)
UPDATE dim_articulo a
SET proveedor_codigo     = o.proveedor,
    proveedor_cod_origen = 'UNICO',
    proveedor_confiable  = TRUE
FROM only_one o
WHERE a.articulo_clave = o.pr_clave;

-- 2) Opción C: VALIDADO visualmente con la clave (para los que aún estén NULL)
WITH base AS (
  SELECT DISTINCT
    s.pr_clave,
    NULLIF(btrim(s.proveedor),'') AS proveedor
  FROM stg_existencias s
  WHERE s.pr_clave IS NOT NULL AND s.proveedor IS NOT NULL
),
resto AS (
  SELECT
    b.*,
    regexp_match(b.pr_clave, '(?i)^(AFF|AF|F{1,2}|C+)?0?([0-9]+)$') AS rx
  FROM base b
),
val AS (
  SELECT
    r.pr_clave,
    r.proveedor,
    CASE WHEN r.rx IS NULL THEN NULL ELSE r.rx[2] END AS rest
  FROM resto r
),
ok AS (
  SELECT
    v.pr_clave,
    v.proveedor,
    (
      ltrim(substring(v.rest from 2), '0') LIKE (v.proveedor || '%')
      OR
      ltrim(substring(v.rest from 3), '0') LIKE (v.proveedor || '%')
    ) AS coincide
  FROM val v
  WHERE v.rest IS NOT NULL AND length(v.rest) >= 1
)
UPDATE dim_articulo a
SET proveedor_codigo     = o.proveedor,
    proveedor_cod_origen = 'VALIDADO',
    proveedor_confiable  = TRUE
FROM ok o
WHERE a.articulo_clave = o.pr_clave
  AND o.coincide = TRUE
  AND a.proveedor_codigo IS NULL;

-- 3) (OPCIONAL) Opción B: Dominante por frecuencia
-- WITH d2 AS (
--   SELECT s.pr_clave, NULLIF(btrim(s.proveedor),'') AS proveedor, COUNT(*) AS cnt
--   FROM stg_existencias s
--   WHERE s.pr_clave IS NOT NULL AND s.proveedor IS NOT NULL
--   GROUP BY s.pr_clave, NULLIF(btrim(s.proveedor),'')
-- ),
-- dom AS (
--   SELECT pr_clave, proveedor
--   FROM (
--     SELECT pr_clave, proveedor,
--            ROW_NUMBER() OVER (PARTITION BY pr_clave ORDER BY cnt DESC) AS rn
--     FROM d2
--   ) x
--   WHERE rn = 1
-- )
-- UPDATE dim_articulo a
-- SET proveedor_codigo     = d.proveedor,
--     proveedor_cod_origen = 'DOMINANTE',
--     proveedor_confiable  = FALSE
-- FROM dom d
-- WHERE a.articulo_clave = d.pr_clave
--   AND a.proveedor_codigo IS NULL;

COMMIT;

-- Checks rápidos:
-- SELECT proveedor_cod_origen, COUNT(*) FROM dim_articulo GROUP BY 1 ORDER BY 2 DESC;
-- SELECT COUNT(*) AS sin_proveedor_principal FROM dim_articulo WHERE proveedor_codigo IS NULL;
