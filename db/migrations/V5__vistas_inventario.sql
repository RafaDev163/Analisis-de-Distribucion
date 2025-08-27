-- V5__vistas_inventario.sql
-- Vistas base para foto de inventario (último snapshot), agrupado por sku_base y modalidad.

-- 1) ÚLTIMA FECHA
CREATE OR REPLACE VIEW v_fecha_corte_max AS
SELECT MAX(fecha_corte) AS fecha_corte
FROM fact_inventario;

-- 2) INVENTARIO EN ALMACÉN PRINCIPAL (101/102) POR MODALIDAD
CREATE OR REPLACE VIEW v_inv_principal_mod AS
SELECT
  da.sku_base,
  da.modalidad,
  SUM(fi.existencia)::int AS existencia
FROM fact_inventario fi
JOIN dim_almacen  al ON al.almacen_sk  = fi.almacen_sk
JOIN dim_articulo da ON da.articulo_sk = fi.articulo_sk
WHERE fi.fecha_corte = (SELECT fecha_corte FROM v_fecha_corte_max)
  AND al.almacen_codigo IN ('101','102')
  AND COALESCE(da.pseudo, FALSE) = FALSE
GROUP BY da.sku_base, da.modalidad;

-- 3) INVENTARIO EN ALMACÉN PRINCIPAL (101/102) TOTAL (F + C)
CREATE OR REPLACE VIEW v_inv_principal_total AS
SELECT sku_base, SUM(existencia)::int AS existencia_total
FROM v_inv_principal_mod
GROUP BY sku_base;

-- 4) INVENTARIO EN TIENDAS (103/105/106) POR TIENDA Y MODALIDAD
CREATE OR REPLACE VIEW v_inv_tiendas_mod AS
SELECT
  da.sku_base,
  da.modalidad,
  al.almacen_codigo AS tienda,
  SUM(fi.existencia)::int AS existencia
FROM fact_inventario fi
JOIN dim_almacen  al ON al.almacen_sk  = fi.almacen_sk
JOIN dim_articulo da ON da.articulo_sk = fi.articulo_sk
WHERE fi.fecha_corte = (SELECT fecha_corte FROM v_fecha_corte_max)
  AND al.almacen_codigo IN ('103','105','106')
  AND COALESCE(da.pseudo, FALSE) = FALSE
GROUP BY da.sku_base, da.modalidad, al.almacen_codigo;

-- 5) INVENTARIO EN TIENDAS TOTAL (F + C, todas las tiendas)
CREATE OR REPLACE VIEW v_inv_tiendas_total AS
SELECT sku_base, SUM(existencia)::int AS existencia_tiendas
FROM v_inv_tiendas_mod
GROUP BY sku_base;

-- 6) (Opcional) ALIAS “DISPONIBLE PARA DISTRIBUIR”
--    Por ahora, disponible = stock del principal (101/102).
CREATE OR REPLACE VIEW v_inv_disponible_mod AS
SELECT * FROM v_inv_principal_mod;

CREATE OR REPLACE VIEW v_inv_disponible_total AS
SELECT * FROM v_inv_principal_total;
