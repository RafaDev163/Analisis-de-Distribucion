-- V3e__proveedor_por_csv_familia_parse_explicit.sql
-- Objetivo:
--  1) Proveedor se toma del CSV (stg_existencias.proveedor) para el puente.
--  2) dim_articulo NO infiere proveedor; sólo parsea familia (1–2 dígitos).
--  3) Prefijo explícito: (AFF|AF|F{1,2}|C+) + '0' opcional antes de los números.
--  4) Idempotente: no altera esquema; sólo (re)carga datos con UPSERT.

BEGIN;

-- 0) Índices útiles en staging (por si no existen aún)
CREATE INDEX IF NOT EXISTS ix_stg_existencias_pr_clave  ON stg_existencias(pr_clave);
CREATE INDEX IF NOT EXISTS ix_stg_existencias_proveedor ON stg_existencias(proveedor);

-- 1) (Re)carga de proveedores desde CSV (idempotente)
INSERT INTO dim_proveedor (proveedor_codigo, proveedor_nombre)
SELECT DISTINCT NULLIF(btrim(s.proveedor),''), NULLIF(btrim(s.ps_nombre),'')
FROM stg_existencias s
WHERE s.proveedor IS NOT NULL OR s.ps_nombre IS NOT NULL
ON CONFLICT (proveedor_codigo, proveedor_nombre) DO NOTHING;

-- 2) (Re)carga de artículos: modalidad + familia (1–2 dígitos). Sin inferir proveedor.
WITH base AS (
  SELECT
    s.pr_clave,
    (ARRAY_AGG(s.pr_descripcion ORDER BY length(coalesce(s.pr_descripcion,'')) DESC))[1] AS descripcion,
    NULLIF(AVG(NULLIF(s.pr_costo,0)),NULL) AS costo_ref,
    -- Regex explícito con AFF|AF|F{1,2}|C+, y '0' opcional antes de dígitos
    regexp_match(s.pr_clave, '(?i)^(AFF|AF|F{1,2}|C+)?0?([0-9]+)$') AS rx
  FROM stg_existencias s
  WHERE s.pr_clave IS NOT NULL
  GROUP BY s.pr_clave
),
pre AS (
  SELECT
    b.pr_clave,
    b.descripcion,
    b.costo_ref,
    CASE
      WHEN b.rx IS NULL THEN 'DESCONOCIDA'
      WHEN b.rx[1] ~* '^(AFF|AF|F{1,2})$' THEN 'FIRME'
      WHEN b.rx[1] ~* '^C+$'              THEN 'CONSIGNACION'
      ELSE 'DESCONOCIDA'
    END AS modalidad,
    CASE WHEN b.rx IS NULL THEN NULL ELSE b.rx[2] END AS rest
  FROM base b
),
familias AS (
  -- Genera candidatos de familia 1 y 2 dígitos
  SELECT pr_clave, descripcion, costo_ref, modalidad,
         (substring(rest from 1 for 1))::int AS linea_familia
  FROM pre
  WHERE rest IS NOT NULL AND length(rest) >= 1
  UNION ALL
  SELECT pr_clave, descripcion, costo_ref, modalidad,
         (substring(rest from 1 for 2))::int AS linea_familia
  FROM pre
  WHERE rest IS NOT NULL AND length(rest) >= 2
),
elegidos AS (
  -- Ajusta el rango si tu universo de familias cambia (1..23 ahora)
  SELECT DISTINCT ON (pr_clave)
         pr_clave, descripcion, costo_ref, modalidad, linea_familia
  FROM familias
  WHERE linea_familia BETWEEN 1 AND 23
  ORDER BY pr_clave, linea_familia DESC  -- preferimos 2 dígitos si aplica
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
  NULL                                  AS proveedor_codigo,  -- dejamos de inferir proveedor
  NULL                                  AS sku_base,          -- opcional: dejamos de calcular sku_base
  (e.pr_clave IN ('DESCUENTO','DEVOLUCIONES','EMPAQUE')) AS pseudo
FROM elegidos e
ON CONFLICT (articulo_clave) DO UPDATE
SET descripcion       = COALESCE(EXCLUDED.descripcion,       dim_articulo.descripcion),
    costo_ref         = COALESCE(EXCLUDED.costo_ref,         dim_articulo.costo_ref),
    modalidad         = COALESCE(EXCLUDED.modalidad,         dim_articulo.modalidad),
    linea_familia     = COALESCE(EXCLUDED.linea_familia,     dim_articulo.linea_familia),
    proveedor_codigo  = NULL,   -- neutraliza lo inferido por parches previos
    sku_base          = NULL,   -- neutraliza lo inferido por parches previos
    pseudo            = COALESCE(EXCLUDED.pseudo,            dim_articulo.pseudo);

-- 3) (Re)carga del puente artículo-proveedor usando EL PROVEEDOR DEL CSV
INSERT INTO articulo_proveedor (articulo_sk, proveedor_sk, costo_unitario, fuente)
SELECT
  a.articulo_sk,
  p.proveedor_sk,
  NULLIF(AVG(NULLIF(s.pr_costo, 0)), NULL) AS costo_prom,
  'stg_existencias (proveedor CSV)'        AS fuente
FROM stg_existencias s
JOIN dim_articulo  a ON a.articulo_clave = s.pr_clave
JOIN dim_proveedor p ON p.proveedor_codigo IS NOT DISTINCT FROM s.proveedor
WHERE a.pseudo IS FALSE
  AND s.pr_costo > 0
GROUP BY a.articulo_sk, p.proveedor_sk
ON CONFLICT (articulo_sk, proveedor_sk) DO UPDATE
SET costo_unitario = EXCLUDED.costo_unitario,
    fuente         = EXCLUDED.fuente,
    updated_at     = now();

COMMIT;
