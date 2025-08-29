-- V3i__rebuild_puente_desde_csv.sql
-- Rebuild TOTAL del puente articulo_proveedor exclusivamente desde staging (CSV)
-- Úsalo cuando quieras garantizar que el puente refleje 1:1 lo que hay en stg_existencias.
-- No toca dim_articulo ni dim_proveedor.

BEGIN;

-- 1) Borrar puente actual (solo datos)
DELETE FROM articulo_proveedor;

-- 2) Reconstruir desde CSV (staging)
INSERT INTO articulo_proveedor (articulo_sk, proveedor_sk, costo_unitario, fuente)
SELECT
  a.articulo_sk,
  p.proveedor_sk,
  NULLIF(AVG(NULLIF(s.pr_costo, 0)), NULL) AS costo_prom,
  'stg_existencias (proveedor CSV)'        AS fuente
FROM stg_existencias s
JOIN dim_articulo  a ON a.articulo_clave  = s.pr_clave
JOIN dim_proveedor p ON p.proveedor_codigo IS NOT DISTINCT FROM s.proveedor
WHERE a.pseudo IS FALSE
  AND s.proveedor IS NOT NULL
GROUP BY a.articulo_sk, p.proveedor_sk
ON CONFLICT (articulo_sk, proveedor_sk) DO UPDATE
SET costo_unitario = EXCLUDED.costo_unitario,
    fuente         = EXCLUDED.fuente,
    updated_at     = now();

COMMIT;

-- Sugerido después:
-- ANALYZE articulo_proveedor;
