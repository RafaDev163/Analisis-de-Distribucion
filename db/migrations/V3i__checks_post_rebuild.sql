-- V3i__checks_post_rebuild.sql
-- Checks después de V3i (rebuild del puente)

-- 1) ¿Quedaron casos prefijo vs prefijo+0...? (debe dar 0 filas)
WITH pares AS (
  SELECT DISTINCT
    a.articulo_clave,
    p1.proveedor_codigo AS prov_corto,
    p2.proveedor_codigo AS prov_largo
  FROM articulo_proveedor ap1
  JOIN dim_articulo  a  ON a.articulo_sk    = ap1.articulo_sk
  JOIN dim_proveedor p1 ON p1.proveedor_sk  = ap1.proveedor_sk
  JOIN articulo_proveedor ap2 ON ap2.articulo_sk = ap1.articulo_sk
  JOIN dim_proveedor p2 ON p2.proveedor_sk  = ap2.proveedor_sk
  WHERE p2.proveedor_codigo LIKE p1.proveedor_codigo || '0%'
    AND p2.proveedor_codigo <> p1.proveedor_codigo
)
SELECT * FROM pares LIMIT 50;

-- 2) Claves con múltiples proveedores (para inspección)
SELECT a.articulo_clave,
       COUNT(*) AS n_proveedores,
       string_agg(p.proveedor_codigo, ', ' ORDER BY p.proveedor_codigo) AS codigos_proveedores
FROM articulo_proveedor ap
JOIN dim_articulo  a USING (articulo_sk)
JOIN dim_proveedor p USING (proveedor_sk)
GROUP BY a.articulo_clave
HAVING COUNT(*) > 1
ORDER BY n_proveedores DESC
LIMIT 30;

-- 3) Resumen simple del puente
SELECT COUNT(*) AS filas_puente FROM articulo_proveedor;
