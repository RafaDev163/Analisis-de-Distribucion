WITH params AS (
  SELECT
    DATE '2025-08-01' AS periodo_inicio,
    DATE '2025-08-31' AS periodo_fin,
    DATE '2025-09-03' AS fecha_corte,
    103::int          AS tienda_dest,              -- tienda destino
    ARRAY[101,102]    AS cedis_codigos,            -- CEDIS disponibles
    21::int           AS target_doi_days,
    3::int            AS safety_days,
    0::int            AS cedis_reserva_ud          -- reserva por SKU en CEDIS (0=sin reserva)
),
-- SK destino (tienda 103)
dest AS (
  SELECT a.almacen_sk
  FROM dim_almacen a, params p
  WHERE a.almacen_codigo::int = p.tienda_dest
),
-- SK de CEDIS
cedis AS (
  SELECT a.almacen_sk, a.almacen_codigo::int AS cedis_codigo
  FROM dim_almacen a, params p
  WHERE a.almacen_codigo::int = ANY(p.cedis_codigos)
),
-- Rotación (ventas) de la tienda 103 en el periodo
rot_dest AS (
  SELECT
    f.articulo_sk,
    SUM(f.unidades_netas) AS uds_periodo,
    (p.periodo_fin - p.periodo_inicio + 1) AS dias_periodo
  FROM fact_ventas f, params p, dest d
  WHERE f.nivel_agregacion='tienda'
    AND f.almacen_sk = d.almacen_sk
    AND f.periodo_inicio = p.periodo_inicio
    AND f.periodo_fin    = p.periodo_fin
  GROUP BY f.articulo_sk, dias_periodo
),
-- Inventario actual de la tienda 103 (fecha_corte)
inv_dest AS (
  SELECT i.articulo_sk, i.existencia::numeric AS on_hand
  FROM fact_inventario i, params p, dest d
  WHERE i.almacen_sk = d.almacen_sk
    AND i.fecha_corte = p.fecha_corte
),
-- Catálogo artículos (múltiplo=1 por ahora)
art AS (
  SELECT da.articulo_sk, da.articulo_clave, da.descripcion, 1::int AS multiplo_empaque
  FROM dim_articulo da
),
-- Faltante (sugerido) de 103
sug_103 AS (
  SELECT
    r.articulo_sk,
    a.articulo_clave,
    a.descripcion,
    ROUND(r.uds_periodo / NULLIF(r.dias_periodo,0), 6) AS uds_diarias,
    COALESCE(id.on_hand,0) AS on_hand,
    ROUND((r.uds_periodo / NULLIF(r.dias_periodo,0))*(p.target_doi_days+p.safety_days), 2) AS stock_objetivo,
    GREATEST(
      0,
      ROUND((r.uds_periodo / NULLIF(r.dias_periodo,0))*(p.target_doi_days+p.safety_days), 2) - COALESCE(id.on_hand,0)
    ) AS faltante_neto,
    a.multiplo_empaque
  FROM rot_dest r
  JOIN art a      ON a.articulo_sk = r.articulo_sk
  LEFT JOIN inv_dest id ON id.articulo_sk = r.articulo_sk
  JOIN params p ON TRUE
  WHERE (r.uds_periodo / NULLIF(r.dias_periodo,0)) > 0  -- opcional: sólo artículos con rotación > 0
),
-- Inventario disponible en CEDIS (con reserva fija por SKU)
inv_cedis AS (
  SELECT
    c.cedis_codigo,
    i.almacen_sk,
    i.articulo_sk,
    GREATEST(i.existencia::numeric - p.cedis_reserva_ud, 0) AS disponible_ud
  FROM fact_inventario i
  JOIN cedis c ON c.almacen_sk = i.almacen_sk
  JOIN params p ON TRUE
  WHERE i.fecha_corte = p.fecha_corte
),
-- Total disponible por artículo en todos los CEDIS
sum_cedis AS (
  SELECT articulo_sk, SUM(disponible_ud) AS disponible_total_ud
  FROM inv_cedis
  GROUP BY articulo_sk
),
-- Faltante topeado por lo que hay en CEDIS
necesidad AS (
  SELECT
    s.articulo_sk,
    s.articulo_clave,
    s.descripcion,
    s.multiplo_empaque,
    s.faltante_neto,
    sc.disponible_total_ud,
    LEAST( CEIL(s.faltante_neto / NULLIF(s.multiplo_empaque,1)) * s.multiplo_empaque,
           COALESCE(sc.disponible_total_ud,0) )::numeric AS asign_total_ud
  FROM sug_103 s
  LEFT JOIN sum_cedis sc ON sc.articulo_sk = s.articulo_sk
  WHERE s.faltante_neto > 0
    AND COALESCE(sc.disponible_total_ud,0) > 0
),
-- División proporcional por CEDIS (continuo)
proporcional AS (
  SELECT
    ic.cedis_codigo,
    n.articulo_sk,
    n.articulo_clave,
    n.descripcion,
    n.asign_total_ud,
    ic.disponible_ud,
    sc.disponible_total_ud,
    CASE
      WHEN sc.disponible_total_ud <= 0 THEN 0
      ELSE (ic.disponible_ud / sc.disponible_total_ud) * n.asign_total_ud
    END AS asign_ud_cont
  FROM necesidad n
  JOIN sum_cedis sc ON sc.articulo_sk = n.articulo_sk
  JOIN inv_cedis ic ON ic.articulo_sk = n.articulo_sk
  WHERE ic.disponible_ud > 0
),
-- Parte entera + fracción (para redondeo)
partes AS (
  SELECT
    p.cedis_codigo,
    p.articulo_sk,
    p.articulo_clave,
    p.descripcion,
    p.asign_total_ud,
    p.disponible_ud,
    p.asign_ud_cont,
    FLOOR(p.asign_ud_cont)::int AS asign_base,
    (p.asign_ud_cont - FLOOR(p.asign_ud_cont)) AS frac
  FROM proporcional p
),
-- Resto por artículo después del floor
resto AS (
  SELECT articulo_sk,
         (MAX(asign_total_ud) - SUM(asign_base))::int AS restante
  FROM partes
  GROUP BY articulo_sk
),
-- Distribuir el restante a los CEDIS con mayor fracción (uno a uno)
extras AS (
  SELECT
    pr.cedis_codigo,
    pr.articulo_sk,
    CASE
      WHEN r.restante > 0
       AND ROW_NUMBER() OVER (PARTITION BY pr.articulo_sk ORDER BY pr.frac DESC, pr.cedis_codigo) <= r.restante
      THEN 1 ELSE 0
    END AS extra
  FROM partes pr
  JOIN resto r ON r.articulo_sk = pr.articulo_sk
),
-- Transfer final por CEDIS, cap por disponible
transfer AS (
  SELECT
    pr.cedis_codigo AS desde_almacen,
    (SELECT tienda_dest FROM params)::int AS hacia_almacen,
    pr.articulo_clave,
    pr.descripcion,
    LEAST(pr.disponible_ud, pr.asign_base + COALESCE(ex.extra,0))::int AS ud_a_transferir
  FROM partes pr
  LEFT JOIN extras ex
    ON ex.cedis_codigo = pr.cedis_codigo
   AND ex.articulo_sk  = pr.articulo_sk
)
SELECT *
FROM transfer
WHERE ud_a_transferir > 0
ORDER BY articulo_clave, desde_almacen;
