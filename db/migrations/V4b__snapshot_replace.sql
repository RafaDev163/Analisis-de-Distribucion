-- V4c__snapshot_replace.sql
-- Reemplaza completamente la foto de :fc (borra y vuelve a insertar).

\echo 'Reemplazando snapshot en fact_inventario para fecha_corte = :fc'

BEGIN;

DELETE FROM fact_inventario
WHERE fecha_corte = to_date(:'fc','YYYY-MM-DD');

INSERT INTO fact_inventario (fecha_corte, almacen_sk, articulo_sk, existencia)
SELECT
  to_date(:'fc','YYYY-MM-DD') AS fecha_corte,
  a.almacen_sk,
  d.articulo_sk,
  SUM(GREATEST(s.pr_existencia, 0))::int AS existencia
FROM stg_existencias s
JOIN dim_almacen  a ON a.almacen_codigo = s.pr_almacen
JOIN dim_articulo d ON d.articulo_clave = s.pr_clave
GROUP BY a.almacen_sk, d.articulo_sk;

COMMIT;
