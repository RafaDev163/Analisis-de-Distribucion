-- V3d__parseo_zeros_intermedios.sql
-- Extiende V3c: permite 0..n ceros entre familia y proveedor
-- para prefijos C, AF y AFF, eligiendo el mejor match de proveedor.

BEGIN;

WITH base AS (
  SELECT
    s.pr_clave,
    (ARRAY_AGG(s.pr_descripcion ORDER BY length(coalesce(s.pr_descripcion,'')) DESC))[1] AS descripcion,
    NULLIF(AVG(NULLIF(s.pr_costo,0)),NULL) AS costo_ref,
    -- Mismo enfoque que V3c: prefijo (AF|F|FF|C...), 0 opcional, resto dígitos
    regexp_match(s.pr_clave, '(?i)^(AF|F{1,2}|C+)?0?([0-9]+)$') AS rx
  FROM stg_existencias s
  WHERE s.pr_clave IS NOT NULL
  GROUP BY s.pr_clave
),
pre AS (
  SELECT
    b.pr_clave, b.descripcion, b.costo_ref,
    CASE
      WHEN b.rx IS NULL THEN 'DESCONOCIDA'
      WHEN b.rx[1] ~* '^AF$' OR b.rx[1] ~* '^F+$' THEN 'FIRME'
      WHEN b.rx[1] ~* '^C+$'                     THEN 'CONSIGNACION'
      ELSE 'DESCONOCIDA'
    END AS modalidad,
    CASE WHEN b.rx IS NULL THEN NULL ELSE b.rx[2] END AS rest,
    CASE WHEN b.rx IS NULL THEN NULL ELSE coalesce(b.rx[1],'') END AS prefijo
  FROM base b
),
candidatos AS (
  -- familia 1 dígito
  SELECT pr_clave, descripcion, costo_ref, modalidad, prefijo,
         (substring(rest from 1 for 1))::int AS fam,
         substring(rest from 2)              AS cola
  FROM pre
  WHERE rest IS NOT NULL AND length(rest) >= 1

  UNION ALL

  -- familia 2 dígitos
  SELECT pr_clave, descripcion, costo_ref, modalidad, prefijo,
         (substring(rest from 1 for 2))::int AS fam,
         substring(rest from 3)              AS cola
  FROM pre
  WHERE rest IS NOT NULL AND length(rest) >= 2
),
cand_filtrados AS (
  -- Conserva el mismo rango que has venido usando; ajusta si cambia tu universo
  SELECT *
  FROM candidatos
  WHERE fam BETWEEN 1 AND 23
),
-- A) Match normal con cola tal cual
match_normal AS (
  SELECT
    c.pr_clave, c.descripcion, c.costo_ref, c.modalidad, c.prefijo,
    c.fam AS linea_familia,
    c.cola,
    p.proveedor_codigo,
    length(p.proveedor_codigo) AS provlen,
    FALSE AS usó_drop0
  FROM cand_filtrados c
  LEFT JOIN LATERAL (
    SELECT dp.proveedor_codigo
    FROM dim_proveedor dp
    WHERE c.cola LIKE dp.proveedor_codigo || '%'
    ORDER BY length(dp.proveedor_codigo) DESC
    LIMIT 1
  ) p ON TRUE
),
-- B) Match alterno quitando ceros a la izquierda en la cola
match_drop0 AS (
  SELECT
    c.pr_clave, c.descripcion, c.costo_ref, c.modalidad, c.prefijo,
    c.fam AS linea_familia,
    c.cola,
    p.proveedor_codigo,
    length(p.proveedor_codigo) AS provlen,
    TRUE AS usó_drop0
  FROM cand_filtrados c
  LEFT JOIN LATERAL (
    SELECT dp.proveedor_codigo
    FROM dim_proveedor dp
    WHERE ltrim(c.cola,'0') LIKE dp.proveedor_codigo || '%'
    ORDER BY length(dp.proveedor_codigo) DESC
    LIMIT 1
  ) p ON TRUE
),
-- Unimos ambas rutas y elegimos la mejor por clave
candidatos_tot AS (
  SELECT * FROM match_normal
  UNION ALL
  SELECT * FROM match_drop0
),
elegidos AS (
  SELECT DISTINCT ON (pr_clave)
    pr_clave, descripcion, costo_ref, modalidad, prefijo,
    linea_familia,
    cola,
    proveedor_codigo,
    provlen,
    usó_drop0
  FROM candidatos_tot
  ORDER BY pr_clave,
           (proveedor_codigo IS NOT NULL) DESC,  -- preferimos las que sí matchean proveedor
           provlen DESC,                          -- y el prefijo de proveedor más largo
           linea_familia DESC                     -- desempate: familia de 2 dígitos
)
INSERT INTO dim_articulo (
  articulo_clave, descripcion, costo_ref, modalidad,
  linea_familia, proveedor_codigo, sku_base, pseudo
)
SELECT
  e.pr_clave                           AS articulo_clave,
  e.descripcion,
  e.costo_ref,
  -- Modalidad queda como en V3b/V3c (por prefijo), no cambia
  e.modalidad,
  e.linea_familia,
  e.proveedor_codigo,
  CASE
    WHEN e.proveedor_codigo IS NOT NULL AND e.cola IS NOT NULL THEN
      CASE
        WHEN e.usó_drop0 THEN substr(ltrim(e.cola,'0'), length(e.proveedor_codigo) + 1)
        ELSE substr(e.cola,            length(e.proveedor_codigo) + 1)
      END
    ELSE
      CASE WHEN e.usó_drop0 THEN ltrim(e.cola,'0') ELSE e.cola END
  END                                   AS sku_base,
  (e.pr_clave IN ('DESCUENTO','DEVOLUCIONES','EMPAQUE')) AS pseudo
FROM elegidos e
ON CONFLICT (articulo_clave) DO UPDATE
SET descripcion       = COALESCE(EXCLUDED.descripcion,       dim_articulo.descripcion),
    costo_ref         = COALESCE(EXCLUDED.costo_ref,         dim_articulo.costo_ref),
    modalidad         = COALESCE(EXCLUDED.modalidad,         dim_articulo.modalidad),
    linea_familia     = COALESCE(EXCLUDED.linea_familia,     dim_articulo.linea_familia),
    proveedor_codigo  = COALESCE(EXCLUDED.proveedor_codigo,  dim_articulo.proveedor_codigo),
    sku_base          = COALESCE(EXCLUDED.sku_base,          dim_articulo.sku_base),
    pseudo            = COALESCE(EXCLUDED.pseudo,            dim_articulo.pseudo);

COMMIT;
