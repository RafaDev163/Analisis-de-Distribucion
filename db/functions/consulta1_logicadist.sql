\copy (
WITH ultima_fecha AS (
  SELECT MAX(fecha_corte) AS fecha_corte
  FROM fact_inventario
),
existencias_ultima AS (
  SELECT
    fi.articulo_sk,
    SUM(fi.existencia) AS existencia_total
  FROM fact_inventario fi
  JOIN ultima_fecha u ON fi.fecha_corte = u.fecha_corte
  GROUP BY fi.articulo_sk
  HAVING SUM(fi.existencia) > 0
),
muestra AS (
  SELECT
    f.familia_codigo                            AS clasificacion_codigo,
    f.familia_nombre                          AS clasificacion_nombre,
    a.articulo_sk,
    a.articulo_clave,
    a.descripcion,
    e.existencia_total,
    ROW_NUMBER() OVER (
      PARTITION BY f.familia_id
      ORDER BY random()        -- usa a.articulo_sk si prefieres orden determinista
    ) AS rn
  FROM existencias_ultima e
  JOIN dim_articulo a ON a.articulo_sk = e.articulo_sk
  JOIN dim_familia  f ON f.familia_id  = a.familia_id
)
SELECT
  clasificacion_codigo,
  clasificacion_nombre,
  articulo_sk,
  articulo_clave,
  descripcion,
  existencia_total,
  (SELECT fecha_corte FROM ultima_fecha) AS fecha_corte
FROM muestra
WHERE rn <= 10
ORDER BY clasificacion_codigo, rn
)TO './ejemplo_familias_articulos.csv' WITH CSV HEADER DELIMITER ','