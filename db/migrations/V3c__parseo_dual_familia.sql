-- V3c__parseo_dual_familia.sql
-- Patch para corregir el parseo de la clave para familia.
-- Recalcula dim_articulo usando estrategia de 1 o 2 dígitos para familia,
-- eligiendo la opción que produce el mejor match de proveedor (prefijo más largo).

WITH base AS (
  SELECT
    s.pr_clave,
    -- normalizamos y agregamos campos básicos
    (ARRAY_AGG(s.pr_descripcion ORDER BY length(coalesce(s.pr_descripcion,'')) DESC))[1] AS descripcion,
    NULLIF(AVG(NULLIF(s.pr_costo,0)),NULL) AS costo_ref,
    -- extraemos prefijo (AF/F/FF/C...), '0' opcional y el resto de dígitos
    regexp_match(s.pr_clave, '(?i)^(AF|F{1,2}|C+)?0?([0-9]+)$') AS rx
  FROM stg_existencias s
  WHERE s.pr_clave IS NOT NULL
  GROUP BY s.pr_clave
),
pre AS (
  SELECT
    b.pr_clave, b.descripcion, b.costo_ref,
    -- modalidad por prefijo
    CASE
      WHEN b.rx IS NULL THEN 'DESCONOCIDA'
      WHEN b.rx[1] ~* '^AF$' OR b.rx[1] ~* '^F+$' THEN 'FIRME'
      WHEN b.rx[1] ~* '^C+$'                     THEN 'CONSIGNACION'
      ELSE 'DESCONOCIDA'
    END AS modalidad,
    -- resto de dígitos (sin prefijo ni 0 opcional)
    CASE WHEN b.rx IS NULL THEN NULL ELSE b.rx[2] END AS rest
  FROM base b
),
candidatos AS (
  -- Genera 1 o 2 candidatos por clave: familia=1 dígito o 2 dígitos (si hay)
  SELECT
    p.pr_clave, p.descripcion, p.costo_ref, p.modalidad,
    -- candidato A: 1 dígito
    (substring(p.rest from 1 for 1))::int AS fam,
    substring(p.rest from 2)              AS cola
  FROM pre p
  WHERE p.rest IS NOT NULL AND length(p.rest) >= 1

  UNION ALL

  SELECT
    p.pr_clave, p.descripcion, p.costo_ref, p.modalidad,
    (substring(p.rest from 1 for 2))::int AS fam,
    substring(p.rest from 3)              AS cola
  FROM pre p
  WHERE p.rest IS NOT NULL AND length(p.rest) >= 2
),
cand_filtrados AS (
  -- Aceptamos solo familias en 1..23; descartamos raras (si quisieras, puedes permitir más)
  SELECT * FROM candidatos
  WHERE fam BETWEEN 1 AND 23
),
cand_match AS (
  -- Para cada candidato, buscamos el proveedor cuyo código es prefijo más largo de la cola
  SELECT
    c.pr_clave, c.descripcion, c.costo_ref, c.modalidad,
    c.fam AS linea_familia,
    c.cola,
    pr.proveedor_codigo,
    length(pr.proveedor_codigo) AS provlen
  FROM cand_filtrados c
  LEFT JOIN LATERAL (
    SELECT p.proveedor_codigo
    FROM dim_proveedor p
    WHERE c.cola LIKE p.proveedor_codigo || '%'
    ORDER BY length(p.proveedor_codigo) DESC
    LIMIT 1
  ) pr ON TRUE
),
elegidos AS (
  -- Elegimos 1 fila por clave: preferimos la que tenga proveedor matcheado y match más largo.
  SELECT DISTINCT ON (pr_clave)
    pr_clave, descripcion, costo_ref, modalidad,
    linea_familia,
    cola,
    proveedor_codigo
  FROM cand_match
  ORDER BY pr_clave,
           (proveedor_codigo IS NOT NULL) DESC,  -- primero las que sí matchean proveedor
           provlen DESC,                         -- luego la de prefijo más largo
           linea_familia DESC                    -- empate: familia de 2 dígitos por si aplica
)
INSERT INTO dim_articulo (
  articulo_clave, descripcion, costo_ref, modalidad, linea_familia, proveedor_codigo, sku_base, pseudo
)
SELECT
  e.pr_clave                           AS articulo_clave,
  e.descripcion,
  e.costo_ref,
  e.modalidad,
  e.linea_familia,
  e.proveedor_codigo,
  CASE
    WHEN e.proveedor_codigo IS NOT NULL AND e.cola IS NOT NULL
      THEN substr(e.cola, length(e.proveedor_codigo) + 1)
    ELSE e.cola
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
