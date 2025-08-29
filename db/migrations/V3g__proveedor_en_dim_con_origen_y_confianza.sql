BEGIN;

-- 0) Metadatos para trazar el origen y confianza
ALTER TABLE dim_articulo
  ADD COLUMN IF NOT EXISTS proveedor_cod_origen TEXT    -- 'UNICO','VALIDADO','DOMINANTE'
, ADD COLUMN IF NOT EXISTS proveedor_confiable  BOOLEAN -- TRUE si origen es UNICO o VALIDADO;

-- 1) Limpieza previa (opcional): sólo si quieres rehacer asignaciones
-- UPDATE dim_articulo
-- SET proveedor_codigo = NULL, proveedor_cod_origen = NULL, proveedor_confiable = NULL;

-- 2) Opción A: ÚNICO proveedor por clave (confiable)
WITH prov_x_clave AS (
  SELECT
    s.pr_clave,
    NULLIF(btrim(s.proveedor),'') AS proveedor,
    COUNT(DISTINCT NULLIF(btrim(s.proveedor),'')) OVER (PARTITION BY s.pr_clave) AS n_prov_dist
  FROM stg_existencias s
  WHERE s.pr_clave IS NOT NULL
)
UPDATE dim_articulo a
SET proveedor_codigo    = p.proveedor,
    proveedor_cod_origen= 'UNICO',
    proveedor_confiable = TRUE
FROM (
  SELECT pr_clave, proveedor
  FROM prov_x_clave
  WHERE n_prov_dist = 1 AND proveedor IS NOT NULL
  GROUP BY pr_clave, proveedor
) p
WHERE a.articulo_clave = p.pr_clave;

-- 3) Opción C: VALIDADO visualmente con la clave (para los que aún estén NULL)
--    Prefijo (AFF|AF|F|FF|C+), '0' opcional, resto numérico; permitimos 0..n ceros entre familia y proveedor.
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
      -- familia 1 dígito → cola a partir de pos 2
      ltrim(substring(v.rest from 2), '0') LIKE (v.proveedor || '%')
      OR
      -- familia 2 dígitos → cola a partir de pos 3
      ltrim(substring(v.rest from 3), '0') LIKE (v.proveedor || '%')
    ) AS coincide
  FROM val v
  WHERE v.rest IS NOT NULL AND length(v.rest) >= 1
)
UPDATE dim_articulo a
SET proveedor_codigo    = o.proveedor,
    proveedor_cod_origen= 'VALIDADO',
    proveedor_confiable = TRUE
FROM ok o
WHERE a.articulo_clave = o.pr_clave
  AND o.coincide = TRUE
  AND a.proveedor_codigo IS NULL;  -- no pisa lo ya 'UNICO'

-- 4) (OPCIONAL) Opción B: Dominante por frecuencia para el resto (menos confiable)
--    Úsalo sólo si necesitas cobertura casi total para dashboards rápidos.
WITH dom AS (
  SELECT
    s.pr_clave,
    NULLIF(btrim(s.proveedor),'') AS proveedor,
    ROW_NUMBER() OVER (
      PARTITION BY s.pr_clave
      ORDER BY COUNT(*) DESC
    ) AS rn
  FROM stg_existencias s
  WHERE s.pr_clave IS NOT NULL AND s.proveedor IS NOT NULL
  GROUP BY s.pr_clave, NULLIF(btrim(s.proveedor),'')
)
UPDATE dim_articulo a
SET proveedor_codigo    = d.proveedor,
    proveedor_cod_origen= 'DOMINANTE',
    proveedor_confiable = FALSE
FROM dom d
WHERE a.articulo_clave = d.pr_clave
  AND d.rn = 1
  AND a.proveedor_codigo IS NULL;  -- sólo completa huecos

COMMIT;
