-- V3__dim_articulo_y_proveedor.sql
-- Crea dimensiones de artículo y proveedor + tabla puente
-- y las puebla desde stg_existencias. Seguro de re-ejecutar.

-- 0) Normalización ligera de staging (evita strings vacíos)
UPDATE stg_existencias
SET
  pr_almacen     = NULLIF(btrim(pr_almacen),''),
  pr_clave       = upper(NULLIF(btrim(pr_clave),'')),
  pr_descripcion = NULLIF(btrim(pr_descripcion),''),
  proveedor      = NULLIF(btrim(proveedor),''),
  ps_nombre      = NULLIF(btrim(ps_nombre),'')
WHERE TRUE;

-- 1) Proveedores
CREATE TABLE IF NOT EXISTS dim_proveedor (
  proveedor_sk     BIGSERIAL PRIMARY KEY,
  proveedor_codigo TEXT,
  proveedor_nombre TEXT,
  activo           BOOLEAN DEFAULT TRUE,
  CONSTRAINT u_dim_proveedor UNIQUE (proveedor_codigo, proveedor_nombre)
);

-- 2) Artículos
CREATE TABLE IF NOT EXISTS dim_articulo (
  articulo_sk       BIGSERIAL PRIMARY KEY,
  articulo_clave    TEXT NOT NULL,
  descripcion       TEXT,
  costo_ref         NUMERIC(12,4),
  unidad_empaque    INTEGER,
  presentacion_min  INTEGER,
  familia           TEXT,
  subfamilia        TEXT,
  activo            BOOLEAN DEFAULT TRUE,
  -- extensiones C/F
  modalidad         TEXT CHECK (modalidad IN ('CONSIGNACION','FIRME','DESCONOCIDA')),
  sku_base          TEXT,
  pseudo            BOOLEAN DEFAULT FALSE,
  CONSTRAINT u_dim_articulo UNIQUE (articulo_clave)
);

CREATE INDEX IF NOT EXISTS idx_dim_articulo_clave     ON dim_articulo(articulo_clave);
CREATE INDEX IF NOT EXISTS idx_dim_articulo_sku_base  ON dim_articulo(sku_base);
CREATE INDEX IF NOT EXISTS idx_dim_articulo_modalidad ON dim_articulo(modalidad);
CREATE INDEX IF NOT EXISTS idx_dim_articulo_pseudo    ON dim_articulo(pseudo);

-- 3) Puente artículo↔proveedor
CREATE TABLE IF NOT EXISTS articulo_proveedor (
  articulo_sk     BIGINT NOT NULL REFERENCES dim_articulo(articulo_sk),
  proveedor_sk    BIGINT NOT NULL REFERENCES dim_proveedor(proveedor_sk),
  costo_unitario  NUMERIC(12,4),
  unidad_empaque  INTEGER,
  lead_time_dias  INTEGER,
  moq             INTEGER,
  PRIMARY KEY (articulo_sk, proveedor_sk)
);

-- 4) Carga dimensión proveedor (solo cuando hay algún dato)
INSERT INTO dim_proveedor (proveedor_codigo, proveedor_nombre)
SELECT DISTINCT s.proveedor, s.ps_nombre
FROM stg_existencias s
WHERE s.proveedor IS NOT NULL OR s.ps_nombre IS NOT NULL
ON CONFLICT (proveedor_codigo, proveedor_nombre) DO NOTHING;

-- 5) Carga dimensión artículo (derivando modalidad, sku_base y pseudo)
INSERT INTO dim_articulo (articulo_clave, descripcion, costo_ref, modalidad, sku_base, pseudo)
SELECT
  s.pr_clave,
  -- descripción más larga (mejor señal) entre las vistas
  (ARRAY_AGG(s.pr_descripcion ORDER BY length(coalesce(s.pr_descripcion,'')) DESC))[1],
  NULLIF(AVG(NULLIF(s.pr_costo,0)),NULL),
  CASE WHEN s.pr_clave ~* '^[C]' THEN 'CONSIGNACION'
       WHEN s.pr_clave ~* '^[F]' THEN 'FIRME'
       ELSE 'DESCONOCIDA' END AS modalidad,
  CASE WHEN s.pr_clave ~* '^[CF]' THEN substr(s.pr_clave,2) ELSE s.pr_clave END AS sku_base,
  (s.pr_clave IN ('DESCUENTO','DEVOLUCIONES','EMPAQUE')) AS pseudo
FROM stg_existencias s
WHERE s.pr_clave IS NOT NULL
GROUP BY s.pr_clave
ON CONFLICT (articulo_clave) DO UPDATE
SET descripcion = COALESCE(EXCLUDED.descripcion, dim_articulo.descripcion),
    costo_ref   = COALESCE(EXCLUDED.costo_ref,   dim_articulo.costo_ref),
    modalidad   = COALESCE(EXCLUDED.modalidad,   dim_articulo.modalidad),
    sku_base    = COALESCE(EXCLUDED.sku_base,    dim_articulo.sku_base),
    pseudo      = COALESCE(EXCLUDED.pseudo,      dim_articulo.pseudo);

-- 6) Carga puente artículo-proveedor (costo promedio cuando exista proveedor)
INSERT INTO articulo_proveedor (articulo_sk, proveedor_sk, costo_unitario)
SELECT
  a.articulo_sk,
  p.proveedor_sk,
  NULLIF(AVG(NULLIF(s.pr_costo,0)),NULL) AS costo_prom
FROM stg_existencias s
JOIN dim_articulo  a ON a.articulo_clave = s.pr_clave
JOIN dim_proveedor p ON (p.proveedor_codigo IS NOT DISTINCT FROM s.proveedor)
                    AND (p.proveedor_nombre IS NOT DISTINCT FROM s.ps_nombre)
GROUP BY a.articulo_sk, p.proveedor_sk
ON CONFLICT (articulo_sk, proveedor_sk) DO NOTHING;

-- 7) (Opcional) diagnósticos rápidos
-- SELECT modalidad, COUNT(*) FROM dim_articulo GROUP BY 1 ORDER BY 1;
-- SELECT sku_base, COUNT(*) FROM dim_articulo GROUP BY 1 HAVING COUNT(*)>1 ORDER BY 1; -- detectar variantes C/F del mismo sku_base
-- SELECT COUNT(*) FROM articulo_proveedor;