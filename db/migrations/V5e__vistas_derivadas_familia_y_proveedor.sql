-- V5e__vistas_derivadas_familia_y_proveedor.sql
-- Recrea vistas derivadas que cayeron con CASCADE, usando articulo_clave.

BEGIN;

-- 1) Inventario principal por FAMILIA y MODALIDAD (almacenes 101/102)
CREATE OR REPLACE VIEW v_inv_principal_familia_mod AS
SELECT
  da.linea_familia,
  da.modalidad,
  SUM(fi.existencia)::int AS existencia
FROM fact_inventario fi
JOIN dim_almacen  al ON al.almacen_sk  = fi.almacen_sk
JOIN dim_articulo da ON da.articulo_sk = fi.articulo_sk
WHERE fi.fecha_corte = (SELECT fecha_corte FROM v_fecha_corte_max)
  AND al.almacen_codigo IN ('101','102')
  AND COALESCE(da.pseudo,FALSE) = FALSE
GROUP BY da.linea_familia, da.modalidad;

-- 2) Total principal por FAMILIA (F + C)
CREATE OR REPLACE VIEW v_inv_principal_familia_total AS
SELECT linea_familia, SUM(existencia)::int AS existencia_total
FROM v_inv_principal_familia_mod
GROUP BY linea_familia;

-- 3) Inventario principal por PROVEEDOR y MODALIDAD (almacenes 101/102)
CREATE OR REPLACE VIEW v_inv_principal_proveedor_mod AS
SELECT
  da.proveedor_codigo,
  da.modalidad,
  SUM(fi.existencia)::int AS existencia
FROM fact_inventario fi
JOIN dim_almacen  al ON al.almacen_sk  = fi.almacen_sk
JOIN dim_articulo da ON da.articulo_sk = fi.articulo_sk
WHERE fi.fecha_corte = (SELECT fecha_corte FROM v_fecha_corte_max)
  AND al.almacen_codigo IN ('101','102')
  AND COALESCE(da.pseudo,FALSE) = FALSE
GROUP BY da.proveedor_codigo, da.modalidad;

-- 4) Inventario en TIENDAS por FAMILIA y MODALIDAD (103/105/106)
CREATE OR REPLACE VIEW v_inv_tiendas_familia_mod AS
SELECT
  da.linea_familia,
  da.modalidad,
  al.almacen_codigo AS tienda,
  SUM(fi.existencia)::int AS existencia
FROM fact_inventario fi
JOIN dim_almacen  al ON al.almacen_sk  = fi.almacen_sk
JOIN dim_articulo da ON da.articulo_sk = fi.articulo_sk
WHERE fi.fecha_corte = (SELECT fecha_corte FROM v_fecha_corte_max)
  AND al.almacen_codigo IN ('103','105','106')
  AND COALESCE(da.pseudo,FALSE) = FALSE
GROUP BY da.linea_familia, da.modalidad, al.almacen_codigo;

-- 5) Total tiendas por FAMILIA
CREATE OR REPLACE VIEW v_inv_tiendas_familia_total AS
SELECT linea_familia, SUM(existencia)::int AS existencia_tiendas
FROM v_inv_tiendas_familia_mod
GROUP BY linea_familia;

COMMIT;
