-- V3b__patch_schema.sql
-- Parchea esquema creado por V3 original y recarga usando la lógica nueva de claves.

-- 0) Índices útiles en staging
CREATE INDEX IF NOT EXISTS ix_stg_existencias_pr_clave  ON stg_existencias(pr_clave);
CREATE INDEX IF NOT EXISTS ix_stg_existencias_proveedor ON stg_existencias(proveedor);

-- 1) dim_proveedor: constraint único por código + índice
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'dim_proveedor'::regclass
      AND conname  = 'u_dim_proveedor_codigo'
  ) THEN
    ALTER TABLE dim_proveedor
      ADD CONSTRAINT u_dim_proveedor_codigo UNIQUE (proveedor_codigo);
  END IF;
END$$;

CREATE INDEX IF NOT EXISTS ix_dim_proveedor_codigo ON dim_proveedor(proveedor_codigo);

-- 2) dim_articulo: columnas nuevas para la lógica de parseo
ALTER TABLE dim_articulo
  ADD COLUMN IF NOT EXISTS linea_familia    INT,
  ADD COLUMN IF NOT EXISTS proveedor_codigo TEXT;

-- índices solo para columnas nuevas (evitamos duplicar los que ya existían en V3)
CREATE INDEX IF NOT EXISTS ix_dim_articulo_prov  ON dim_articulo(proveedor_codigo);
CREATE INDEX IF NOT EXISTS ix_dim_articulo_linea ON dim_articulo(linea_familia);

-- 3) Puente: añadimos metadatos de costo (sin tocar columnas previas como moq/lead_time)
ALTER TABLE articulo_proveedor
  ADD COLUMN IF NOT EXISTS fuente     TEXT,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

-- check defensivo opcional
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'articulo_proveedor'::regclass
      AND conname  = 'ck_ap_costo_nonneg'
  ) THEN
    ALTER TABLE articulo_proveedor
      ADD CONSTRAINT ck_ap_costo_nonneg
      CHECK (costo_unitario IS NULL OR costo_unitario >= 0);
  END IF;
END$$;

-- Índices útiles del puente
CREATE INDEX IF NOT EXISTS ix_ap_articulo  ON articulo_proveedor(articulo_sk);
CREATE INDEX IF NOT EXISTS ix_ap_proveedor ON articulo_proveedor(proveedor_sk);

-- 4) Historial de costos (preparado para futuro)
CREATE TABLE IF NOT EXISTS articulo_proveedor_costo_hist (
  articulo_sk     BIGINT NOT NULL REFERENCES dim_articulo(articulo_sk),
  proveedor_sk    BIGINT NOT NULL REFERENCES dim_proveedor(proveedor_sk),
  costo_unitario  NUMERIC(12,4) NOT NULL,
  vigencia_desde  DATE NOT NULL,
  vigencia_hasta  DATE,
  fuente          TEXT,
  created_at      TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (articulo_sk, proveedor_sk, vigencia_desde)
);

-- 5) (Re)carga de proveedores desde staging (idempotente)
INSERT INTO dim_proveedor (proveedor_codigo, proveedor_nombre)
SELECT DISTINCT NULLIF(btrim(s.proveedor),''), NULLIF(btrim(s.ps_nombre),'')
FROM stg_existencias s
WHERE s.proveedor IS NOT NULL OR s.ps_nombre IS NOT NULL
ON CONFLICT (proveedor_codigo, proveedor_nombre) DO NOTHING;

-- 6) Carga/actualización de artículos con parseo avanzado
INSERT INTO dim_articulo (
  articulo_clave, descripcion, costo_ref,
  modalidad, linea_familia, proveedor_codigo, sku_base, pseudo
)
WITH partes AS (
  SELECT
    s.pr_clave,
    (ARRAY_AGG(s.pr_descripcion ORDER BY length(coalesce(s.pr_descripcion,'')) DESC))[1] AS descripcion,
    NULLIF(AVG(NULLIF(s.pr_costo,0)),NULL) AS costo_ref,
    regexp_match(
      s.pr_clave,
      '(?i)^(AF|F{1,2}|C+)?0?([0-9]{1,2})([0-9]+)$'
      -- 1: prefijo (AF/F/FF/C...) opcional; 0? ignora cero antes de familia
      -- 2: familia 1-2 dígitos
      -- 3: cola = proveedor + sku_base (proveedor por prefijo más largo)
    ) AS m
  FROM stg_existencias s
  WHERE s.pr_clave IS NOT NULL
  GROUP BY s.pr_clave
),
desglosada AS (
  SELECT
    p.pr_clave,
    p.descripcion,
    p.costo_ref,
    CASE
      WHEN p.m IS NULL THEN 'DESCONOCIDA'
      WHEN p.m[1] ~* '^AF$' OR p.m[1] ~* '^F+$' THEN 'FIRME'
      WHEN p.m[1] ~* '^C+$'                     THEN 'CONSIGNACION'
      ELSE 'DESCONOCIDA'
    END AS modalidad,
    CASE WHEN p.m IS NULL THEN NULL ELSE (p.m[2])::int END AS linea_familia,
    CASE WHEN p.m IS NULL THEN NULL ELSE p.m[3]        END AS cola_num
  FROM partes p
),
match_proveedor AS (
  -- Proveedor = prefijo más largo de la cola
  SELECT
    d.pr_clave,
    d.descripcion,
    d.costo_ref,
    d.modalidad,
    d.linea_familia,
    d.cola_num,
    pr.proveedor_codigo
  FROM desglosada d
  LEFT JOIN LATERAL (
    SELECT p.proveedor_codigo
    FROM dim_proveedor p
    WHERE d.cola_num LIKE p.proveedor_codigo || '%'
    ORDER BY length(p.proveedor_codigo) DESC
    LIMIT 1
  ) pr ON TRUE
)
SELECT
  mp.pr_clave                           AS articulo_clave,
  mp.descripcion,
  mp.costo_ref,
  mp.modalidad,
  mp.linea_familia,
  mp.proveedor_codigo,
  CASE
    WHEN mp.proveedor_codigo IS NOT NULL AND mp.cola_num IS NOT NULL
      THEN substr(mp.cola_num, length(mp.proveedor_codigo) + 1)
    ELSE mp.cola_num
  END                                   AS sku_base,
  (mp.pr_clave IN ('DESCUENTO','DEVOLUCIONES','EMPAQUE')) AS pseudo
FROM match_proveedor mp
ON CONFLICT (articulo_clave) DO UPDATE
SET descripcion       = COALESCE(EXCLUDED.descripcion,       dim_articulo.descripcion),
    costo_ref         = COALESCE(EXCLUDED.costo_ref,         dim_articulo.costo_ref),
    modalidad         = COALESCE(EXCLUDED.modalidad,         dim_articulo.modalidad),
    linea_familia     = COALESCE(EXCLUDED.linea_familia,     dim_articulo.linea_familia),
    proveedor_codigo  = COALESCE(EXCLUDED.proveedor_codigo,  dim_articulo.proveedor_codigo),
    sku_base          = COALESCE(EXCLUDED.sku_base,          dim_articulo.sku_base),
    pseudo            = COALESCE(EXCLUDED.pseudo,            dim_articulo.pseudo);

-- 7) Puente artículo-proveedor (join por código derivado + fallback a staging)
INSERT INTO articulo_proveedor (articulo_sk, proveedor_sk, costo_unitario, fuente)
SELECT
  a.articulo_sk,
  p.proveedor_sk,
  NULLIF(AVG(NULLIF(s.pr_costo, 0)), NULL) AS costo_prom,
  'stg_existencias promedio reciente'      AS fuente
FROM stg_existencias s
JOIN dim_articulo a
  ON a.articulo_clave = s.pr_clave
JOIN dim_proveedor p
  ON p.proveedor_codigo IS NOT DISTINCT FROM a.proveedor_codigo
   OR (a.proveedor_codigo IS NULL AND p.proveedor_codigo IS NOT DISTINCT FROM s.proveedor)
WHERE a.pseudo IS FALSE
  AND s.pr_costo > 0
GROUP BY a.articulo_sk, p.proveedor_sk
ON CONFLICT (articulo_sk, proveedor_sk) DO UPDATE
SET costo_unitario = EXCLUDED.costo_unitario,
    fuente         = EXCLUDED.fuente,
    updated_at     = now();
