-- V4__fact_inventario_y_snapshot.sql
-- Tabla de hechos de inventario + snapshot desde stg_existencias
-- Idempotente y parametrizable por fecha_corte (psql -v fc='YYYY-MM-DD').

-- 1) Tabla (si no existe)
CREATE TABLE IF NOT EXISTS fact_inventario (
  fecha_corte  DATE NOT NULL,
  almacen_sk   BIGINT NOT NULL REFERENCES dim_almacen(almacen_sk),
  articulo_sk  BIGINT NOT NULL REFERENCES dim_articulo(articulo_sk),
  existencia   INTEGER NOT NULL CHECK (existencia >= 0),
  PRIMARY KEY (fecha_corte, almacen_sk, articulo_sk)
);

-- Índices útiles
CREATE INDEX IF NOT EXISTS idx_inv_art_alm_fec  ON fact_inventario(articulo_sk, almacen_sk, fecha_corte);
CREATE INDEX IF NOT EXISTS idx_inv_alm_fec      ON fact_inventario(almacen_sk, fecha_corte);

-- 2) Snapshot (usa variable psql :fc)
--   Nota: tratamos negativos como 0 (GREATEST) y agregamos por almacén/artículo.
INSERT INTO fact_inventario (fecha_corte, almacen_sk, articulo_sk, existencia)
SELECT
  to_date(:'fc','YYYY-MM-DD') AS fecha_corte,
  a.almacen_sk,
  d.articulo_sk,
  SUM(GREATEST(s.pr_existencia, 0))::int AS existencia
FROM stg_existencias s
JOIN dim_almacen  a ON a.almacen_codigo = s.pr_almacen
JOIN dim_articulo d ON d.articulo_clave = s.pr_clave
GROUP BY a.almacen_sk, d.articulo_sk
ON CONFLICT (fecha_corte, almacen_sk, articulo_sk) DO UPDATE
SET existencia = EXCLUDED.existencia;
