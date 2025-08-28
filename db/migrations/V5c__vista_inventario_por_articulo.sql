-- V5c__vista_inventario_por_articulo.sql
-- Dos vistas filtradas por defecto a principal/tiendas: 101,102,103,105,106

-- 1) Solo artículos con stock (>0) en la última foto
CREATE OR REPLACE VIEW v_inv_articulo AS
SELECT
  da.articulo_clave,
  da.descripcion,
  da.modalidad,
  da.linea_familia,
  da.proveedor_codigo,
  da.sku_base,
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

-- 2) Catálogo completo por almacén, existencia 0 cuando aplique
CREATE OR REPLACE VIEW v_inv_articulo_completo AS
WITH fc AS (SELECT fecha_corte FROM v_fecha_corte_max)
SELECT
  da.articulo_clave,
  da.descripcion,
  da.modalidad,
  da.linea_familia,
  da.proveedor_codigo,
  da.sku_base,
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

-- Índice recomendado para acelerar joins por fecha + artículo + almacén
CREATE INDEX IF NOT EXISTS ix_inv_fecha_art_alm
  ON fact_inventario(fecha_corte, articulo_sk, almacen_sk);