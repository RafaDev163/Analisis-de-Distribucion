-- V3_final__modelo_dimensional_y_carga.sql
-- Consolidado final del modelo dimensional + carga desde staging (CSV)
-- Integra las decisiones de V3e..V3j: proveedor desde CSV, proveedor principal (UNICO/VALIDADO),
-- tolerancia a ceros, correcciones puntuales en staging y soporte de modalidad 'NA' como FIRME.

BEGIN;

------------------------------------------------------------
-- 0) Normalización mínima de staging
------------------------------------------------------------
-- (Opcional) Mantener pr_clave/proveedor como TEXT evita problemas de formato científico.
-- CREATE TEMP TABLE stg_norm AS
-- SELECT
--   btrim(pr_clave)   AS pr_clave,
--   btrim(proveedor)  AS proveedor,
--   btrim(pr_almacen) AS pr_almacen,
--   pr_costo::numeric AS pr_costo
-- FROM stg_existencias;

------------------------------------------------------------
-- 1) Dimensiones
------------------------------------------------------------
-- 1.1 Proveedor
CREATE TABLE IF NOT EXISTS dim_proveedor (
  proveedor_sk     BIGSERIAL PRIMARY KEY,
  proveedor_codigo TEXT UNIQUE,
  proveedor_nombre TEXT,
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now()
);

-- 1.2 Artículo
CREATE TABLE IF NOT EXISTS dim_articulo (
  articulo_sk           BIGSERIAL PRIMARY KEY,
  articulo_clave        TEXT UNIQUE,
  descripcion           TEXT,
  modalidad             TEXT,        -- FIRME | CONSIGNACION
  linea_familia         INT,
  proveedor_codigo      TEXT,        -- principal (conveniencia)
  proveedor_cod_origen  TEXT,        -- UNICO | VALIDADO | DOMINANTE | REVISION
  proveedor_confiable   BOOLEAN,
  pseudo                BOOLEAN DEFAULT FALSE,
  activo                BOOLEAN DEFAULT TRUE,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);

-- 1.3 Puente Artículo-Proveedor (con costo promedio)
CREATE TABLE IF NOT EXISTS articulo_proveedor (
  articulo_sk     BIGINT REFERENCES dim_articulo(articulo_sk),
  proveedor_sk    BIGINT REFERENCES dim_proveedor(proveedor_sk),
  costo_unitario  NUMERIC,
  fuente          TEXT,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (articulo_sk, proveedor_sk)
);

------------------------------------------------------------
-- 2) Carga de Proveedores desde CSV (staging)
------------------------------------------------------------
WITH src AS (
  SELECT DISTINCT NULLIF(btrim(proveedor), '') AS proveedor, NULLIF(btrim(ps_nombre), '') AS ps_nombre
  FROM stg_existencias
)
INSERT INTO dim_proveedor (proveedor_codigo, proveedor_nombre)
SELECT s.proveedor, s.ps_nombre
FROM src s
WHERE s.proveedor IS NOT NULL
ON CONFLICT (proveedor_codigo) DO UPDATE
SET proveedor_nombre = COALESCE(EXCLUDED.proveedor_nombre, dim_proveedor.proveedor_nombre),
    updated_at = now();

------------------------------------------------------------
-- 3) Carga de Artículos desde CSV
------------------------------------------------------------
-- Modalidad: FIRME = NA|AFF|AF|F|FF ; CONSIGNACION = C (uno o más C)
WITH raw AS (
  SELECT DISTINCT
    NULLIF(btrim(pr_clave),'') AS pr_clave,
    NULLIF(btrim(descripcion),'') AS descripcion
  FROM stg_existencias
  WHERE pr_clave IS NOT NULL
),
parsed AS (
  SELECT
    r.pr_clave AS articulo_clave,
    r.descripcion,
    CASE
      WHEN r.pr_clave ~* '^(NA|AFF|AF|F{1,2})' THEN 'FIRME'
      WHEN r.pr_clave ~* '^C+'                     THEN 'CONSIGNACION'
      ELSE NULL
    END AS modalidad,
    -- Familia: primeros 1 o 2 dígitos después del prefijo
    NULLIF(
      CASE
        WHEN r.pr_clave ~* '^(NA|AFF|AF|F{1,2}|C+)(0?)(\d{1,2})' THEN
          CAST ( REGEXP_REPLACE(r.pr_clave, '^(NA|AFF|AF|F{1,2}|C+)(0?)(\d{1,2}).*$', '\3') AS INT )
        ELSE NULL
      END, 0
    ) AS linea_familia
  FROM raw r
)
INSERT INTO dim_articulo (articulo_clave, descripcion, modalidad, linea_familia)
SELECT p.articulo_clave, p.descripcion, p.modalidad, p.linea_familia
FROM parsed p
WHERE p.articulo_clave IS NOT NULL
ON CONFLICT (articulo_clave) DO UPDATE
SET descripcion   = COALESCE(EXCLUDED.descripcion, dim_articulo.descripcion),
    modalidad     = COALESCE(EXCLUDED.modalidad, dim_articulo.modalidad),
    linea_familia = COALESCE(EXCLUDED.linea_familia, dim_articulo.linea_familia),
    updated_at    = now();

------------------------------------------------------------
-- 4) Puente Artículo-Proveedor desde CSV (promedio costo)
------------------------------------------------------------
INSERT INTO articulo_proveedor (articulo_sk, proveedor_sk, costo_unitario, fuente)
SELECT
  a.articulo_sk,
  p.proveedor_sk,
  NULLIF(AVG(NULLIF(s.pr_costo, 0)), NULL) AS costo_prom,
  'stg_existencias (proveedor CSV, V3_final)' AS fuente
FROM stg_existencias s
JOIN dim_articulo  a ON a.articulo_clave  = s.pr_clave
JOIN dim_proveedor p ON p.proveedor_codigo IS NOT DISTINCT FROM s.proveedor
WHERE s.proveedor IS NOT NULL
GROUP BY a.articulo_sk, p.proveedor_sk
ON CONFLICT (articulo_sk, proveedor_sk) DO UPDATE
SET costo_unitario = EXCLUDED.costo_unitario,
    fuente         = EXCLUDED.fuente,
    updated_at     = now();

------------------------------------------------------------
-- 5) Proveedor principal en dim_articulo (UNICO / VALIDADO)
------------------------------------------------------------
UPDATE dim_articulo
SET proveedor_codigo     = NULL,
    proveedor_cod_origen = NULL,
    proveedor_confiable  = NULL;

-- 5.A UNICO
WITH d AS (
  SELECT DISTINCT s.pr_clave, NULLIF(btrim(s.proveedor),'') AS proveedor
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
  FROM d JOIN c USING (pr_clave)
  WHERE c.n_prov_dist = 1 AND d.proveedor IS NOT NULL
)
UPDATE dim_articulo a
SET proveedor_codigo     = o.proveedor,
    proveedor_cod_origen = 'UNICO',
    proveedor_confiable  = TRUE
FROM only_one o
WHERE a.articulo_clave = o.pr_clave;

-- 5.C VALIDADO
WITH base AS (
  SELECT DISTINCT s.pr_clave, NULLIF(btrim(s.proveedor),'') AS proveedor
  FROM stg_existencias s
  WHERE s.pr_clave IS NOT NULL AND s.proveedor IS NOT NULL
),
resto AS (
  SELECT b.*, regexp_match(b.pr_clave, '(?i)^(NA|AFF|AF|F{1,2}|C+)?0?([0-9]+)$') AS rx
  FROM base b
),
val AS (
  SELECT r.pr_clave, r.proveedor, CASE WHEN r.rx IS NULL THEN NULL ELSE r.rx[2] END AS rest
  FROM resto r
),
ok AS (
  SELECT v.pr_clave, v.proveedor,
         ( ltrim(substring(v.rest from 2), '0') LIKE (v.proveedor || '%')
           OR ltrim(substring(v.rest from 3), '0') LIKE (v.proveedor || '%') ) AS coincide
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

COMMIT;
