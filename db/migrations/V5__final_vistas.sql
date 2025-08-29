-- V5_final_vistas.sql
-- Vistas finales para UI basadas en articulo_clave (DROP + CREATE con CASCADE).

BEGIN;

DROP VIEW IF EXISTS v_inv_disponible_total CASCADE;
DROP VIEW IF EXISTS v_inv_disponible_mod CASCADE;
DROP VIEW IF EXISTS v_inv_principal_total CASCADE;
DROP VIEW IF EXISTS v_inv_tiendas_total CASCADE;
DROP VIEW IF EXISTS v_inv_tiendas_mod CASCADE;
DROP VIEW IF EXISTS v_inv_principal_mod CASCADE;
DROP VIEW IF EXISTS v_inv_articulo_completo CASCADE;
DROP VIEW IF EXISTS v_inv_articulo CASCADE;
DROP VIEW IF EXISTS v_fecha_corte_max CASCADE;
DROP VIEW IF EXISTS v_inv_principal_familia_mod CASCADE;
DROP VIEW IF EXISTS v_inv_principal_familia_total CASCADE;
DROP VIEW IF EXISTS v_inv_principal_proveedor_mod CASCADE;
DROP VIEW IF EXISTS v_inv_tiendas_familia_mod CASCADE;
DROP VIEW IF EXISTS v_inv_tiendas_familia_total CASCADE;

-- 1) Fecha de corte
CREATE VIEW v_fecha_corte_max AS
SELECT MAX(fecha_corte) AS fecha_corte FROM fact_inventario;

-- 2) Inventario principal (101/102) por clave+modalidad+almacén
CREATE VIEW v_inv_principal_mod AS
SELECT
  da.articulo_clave,
  da.modalidad,
  al.almacen_codigo AS almacen,
  SUM(fi.existencia)::int AS existencia
FROM fact_inventario fi
JOIN dim_almacen  al ON al.almacen_sk  = fi.almacen_sk
JOIN dim_articulo da ON da.articulo_sk = fi.articulo_sk
WHERE fi.fecha_corte = (SELECT fecha_corte FROM v_fecha_corte_max)
  AND al.almacen_codigo IN ('101','102')
  AND COALESCE(da.pseudo, FALSE) = FALSE
GROUP BY da.articulo_clave, da.modalidad, al.almacen_codigo;

-- 3) Totales principales por clave
CREATE VIEW v_inv_principal_total AS
SELECT articulo_clave, SUM(existencia)::int AS existencia_total
FROM v_inv_principal_mod
GROUP BY articulo_clave;

-- 4) Inventario en tiendas (103/105/106) por clave+modalidad+tienda
CREATE VIEW v_inv_tiendas_mod AS
SELECT
  da.articulo_clave,
  da.modalidad,
  al.almacen_codigo AS tienda,
  SUM(fi.existencia)::int AS existencia
FROM fact_inventario fi
JOIN dim_almacen  al ON al.almacen_sk  = fi.almacen_sk
JOIN dim_articulo da ON da.articulo_sk = fi.articulo_sk
WHERE fi.fecha_corte = (SELECT fecha_corte FROM v_fecha_corte_max)
  AND al.almacen_codigo IN ('103','105','106')
  AND COALESCE(da.pseudo, FALSE) = FALSE
GROUP BY da.articulo_clave, da.modalidad, al.almacen_codigo;

-- 5) Totales tiendas por clave
CREATE VIEW v_inv_tiendas_total AS
SELECT articulo_clave, SUM(existencia)::int AS existencia_tiendas
FROM v_inv_tiendas_mod
GROUP BY articulo_clave;

-- 6) Disponible para distribución
CREATE VIEW v_inv_disponible_mod AS
SELECT articulo_clave, modalidad, existencia, almacen
FROM v_inv_principal_mod;

CREATE VIEW v_inv_disponible_total AS
SELECT * FROM v_inv_principal_total;

-- 7) Detalle por artículo/almacén (>0)
CREATE VIEW v_inv_articulo AS
SELECT
  da.articulo_clave,
  da.descripcion,
  da.modalidad,
  da.linea_familia,
  da.proveedor_codigo,
  al.almacen_codigo,
  fi.fecha_corte,
  fi.existencia
FROM fact_inventario fi
JOIN dim_articulo da ON da.articulo_sk = fi.articulo_sk
JOIN dim_almacen  al ON al.almacen_sk  = fi.almacen_sk
WHERE fi.fecha_corte = (SELECT fecha_corte FROM v_fecha_corte_max)
  AND COALESCE(da.pseudo, FALSE) = FALSE
  AND fi.existencia > 0
  AND al.almacen_codigo IN ('101','102','103','105','106');

-- 8) Completo (incluye existencia=0)
CREATE VIEW v_inv_articulo_completo AS
WITH fc AS (SELECT fecha_corte FROM v_fecha_corte_max)
SELECT
  da.articulo_clave,
  da.descripcion,
  da.modalidad,
  da.linea_familia,
  da.proveedor_codigo,
  al.almacen_codigo,
  fc.fecha_corte,
  COALESCE(fi.existencia, 0)::int AS existencia
FROM dim_articulo da
CROSS JOIN fc
JOIN dim_almacen al
  ON al.almacen_codigo IN ('101','102','103','105','106')
LEFT JOIN fact_inventario fi
  ON fi.articulo_sk = da.articulo_sk
 AND fi.almacen_sk  = al.almacen_sk
 AND fi.fecha_corte = fc.fecha_corte
WHERE COALESCE(da.pseudo, FALSE) = FALSE;

-- 9) Derivadas por familia/proveedor
CREATE VIEW v_inv_principal_familia_mod AS
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

CREATE VIEW v_inv_principal_familia_total AS
SELECT linea_familia, SUM(existencia)::int AS existencia_total
FROM v_inv_principal_familia_mod
GROUP BY linea_familia;

CREATE VIEW v_inv_principal_proveedor_mod AS
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

CREATE VIEW v_inv_tiendas_familia_mod AS
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

CREATE VIEW v_inv_tiendas_familia_total AS
SELECT linea_familia, SUM(existencia)::int AS existencia_tiendas
FROM v_inv_tiendas_familia_mod
GROUP BY linea_familia;

COMMIT;
