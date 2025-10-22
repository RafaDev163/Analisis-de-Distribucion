-- V7a__fact_ventas.sql
-- Fact por TIENDA (granularidad tienda) con mapeo CLAVE → dim_articulo.articulo_clave

-- ==========================================
-- DDL fact_ventas
-- ==========================================
CREATE TABLE IF NOT EXISTS fact_ventas (
  venta_id        bigserial PRIMARY KEY,
  periodo_inicio  date NOT NULL,
  periodo_fin     date NOT NULL,
  nivel_agregacion text NOT NULL DEFAULT 'tienda'
    CHECK (nivel_agregacion IN ('empresa','tienda')),
  almacen_id      integer NOT NULL,
  articulo_id     integer NOT NULL,
  proveedor_id    integer NULL,
  unidades_netas  numeric(18,2) NOT NULL,
  importe_neto    numeric(18,2) NOT NULL,
  stg_venta_id    bigint NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uidx_fact_periodo_articulo_tienda
    UNIQUE (periodo_inicio, periodo_fin, articulo_id, almacen_id)
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_fact_ventas_articulo ON fact_ventas (articulo_id);
CREATE INDEX IF NOT EXISTS idx_fact_ventas_periodo  ON fact_ventas (periodo_inicio, periodo_fin);

-- ==========================================
-- Insert desde staging
--   MAPEANDO:
--     stg_ventas.clave = dim_articulo.articulo_clave   (← lo que pidió Rafa)
--     stg_ventas.almacen_codigo = dim_almacen.almacen_codigo
-- ==========================================
WITH x AS (
  SELECT
    s.stg_venta_id,
    s.periodo_inicio,
    s.periodo_fin,
    s.almacen_codigo,
    s.clave,
    s.proveedor_id,
    s.unidades_neto,
    s.importe_neto
  FROM stg_ventas s
)
INSERT INTO fact_ventas (
  periodo_inicio, periodo_fin, nivel_agregacion,
  almacen_id, articulo_id, proveedor_id,
  unidades_netas, importe_neto, stg_venta_id
)
SELECT
  x.periodo_inicio,
  x.periodo_fin,
  'tienda' AS nivel_agregacion,
  a.almacen_id,
  da.articulo_id,
  x.proveedor_id,
  x.unidades_neto,
  x.importe_neto,
  x.stg_venta_id
FROM x
JOIN dim_articulo da
  ON da.articulo_clave = x.clave
JOIN dim_almacen a
  ON a.almacen_codigo = x.almacen_codigo
ON CONFLICT (periodo_inicio, periodo_fin, articulo_id, almacen_id) DO UPDATE
SET
  proveedor_id   = EXCLUDED.proveedor_id,
  unidades_netas = EXCLUDED.unidades_netas,
  importe_neto   = EXCLUDED.importe_neto;
