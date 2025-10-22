-- A) QA del staging stg_existencias_familia
-- A1) Volumen total
SELECT COUNT(*) AS rows_stg FROM stg_existencias_familia;

-- A2) Nulos o vacíos en campos clave
SELECT
  COUNT(*) FILTER (WHERE pr_almacen IS NULL OR btrim(pr_almacen)='') AS alm_vacios,
  COUNT(*) FILTER (WHERE pr_clave   IS NULL OR btrim(pr_clave)  ='') AS clave_vacias
FROM stg_existencias_familia;

-- A3) Almacenes no reconocidos (que no están en dim_almacen)
SELECT TRIM(s.pr_almacen) AS alm, COUNT(*) AS n
FROM stg_existencias_familia s
LEFT JOIN dim_almacen d ON d.almacen_codigo = TRIM(s.pr_almacen)
WHERE TRIM(s.pr_almacen) IS NOT NULL AND d.almacen_sk IS NULL
GROUP BY 1 ORDER BY n DESC;

-- A4) SKUs en notación científica (origen Excel) o inválidos
SELECT pr_clave, COUNT(*) AS n
FROM stg_existencias_familia
WHERE pr_clave ~* 'e[+-]?[0-9]' OR btrim(pr_clave)='0'
GROUP BY 1 ORDER BY n DESC;

-- A5) Duplicados por (almacén, clave)
SELECT TRIM(pr_almacen) AS alm, TRIM(pr_clave) AS clave, COUNT(*) AS n
FROM stg_existencias_familia
GROUP BY 1,2 HAVING COUNT(*)>1 ORDER BY n DESC LIMIT 50;

-- A6) Descripciones conflictivas para la misma clave
SELECT TRIM(pr_clave) AS clave, COUNT(DISTINCT NULLIF(TRIM(pr_descripcion),'')) AS descripciones_distintas
FROM stg_existencias_familia
GROUP BY 1 HAVING COUNT(DISTINCT NULLIF(TRIM(pr_descripcion),''))>1
ORDER BY descripciones_distintas DESC, clave LIMIT 50;

-- A7) Existencias o costos fuera de rango
SELECT
  COUNT(*) FILTER (WHERE pr_existencia < 0) AS existencias_negativas,
  COUNT(*) FILTER (WHERE pr_costo      < 0) AS costos_negativos
FROM stg_existencias_familia;

-- A8) Clasificación vacía o dudosa (debería ser CÓDIGO, no nombre de proveedor)
SELECT
  COUNT(*) FILTER (WHERE clasificacion IS NULL OR btrim(clasificacion)='') AS clasif_vacia,
  COUNT(*) FILTER (WHERE clasificacion ~* '[A-Za-z]{3,}' ) AS clasif_textual_larga -- heurística
FROM stg_existencias_familia;

-- B) QA de dimensiones
-- B1) Unicidad (deberían ser 0 siempre)
SELECT
  (SELECT COUNT(*) - COUNT(DISTINCT almacen_codigo) FROM dim_almacen)   AS alm_duplicados,
  (SELECT COUNT(*) - COUNT(DISTINCT proveedor_codigo) FROM dim_proveedor) AS prov_duplicados,
  (SELECT COUNT(*) - COUNT(DISTINCT articulo_clave) FROM dim_articulo)    AS art_duplicados;

-- B2) Proveedores sin nombre (para limpieza posterior)
SELECT COUNT(*) AS proveedores_sin_nombre
FROM dim_proveedor WHERE proveedor_nombre IS NULL OR btrim(proveedor_nombre)='';

-- B3) Artículos sin familia (tras el mapeo)
SELECT COUNT(*) AS articulos_sin_familia
FROM dim_articulo WHERE familia_id IS NULL;

-- B4) Familias sin parámetros “custom” (usando defaults)
SELECT
  COUNT(*) AS familias_total,
  COUNT(*) FILTER (WHERE doi_min=7 AND doi_max=14 AND multiplo_empaque=1) AS familias_en_default
FROM dim_familia;

-- C) QA del mapeo por articulo --> familia (por codigo)
-- C1) Códigos de clasificación presentes en staging pero AUSENTES en dim_familia
SELECT TRIM(s.clasificacion) AS cod_familia_faltante, COUNT(*) AS ocurrencias
FROM stg_existencias_familia s
LEFT JOIN dim_familia df ON df.familia_codigo = TRIM(s.clasificacion)
WHERE s.clasificacion IS NOT NULL AND df.familia_id IS NULL
GROUP BY 1 ORDER BY 2 DESC LIMIT 50;

-- C2) Cobertura de mapeo por familia (artículos mapeados por cada familia)
SELECT df.familia_codigo, df.familia_nombre, COUNT(*) AS articulos
FROM dim_articulo da
JOIN dim_familia df ON df.familia_id = da.familia_id
GROUP BY 1,2 ORDER BY articulos DESC LIMIT 50;

-- D) QA del snapshot en fact_inventario
-- D1) Conteo por fecha de corte
SELECT fecha_corte, COUNT(*) AS filas, SUM(existencia) AS total_unidades
FROM fact_inventario
GROUP BY 1 ORDER BY 1 DESC LIMIT 5;

-- D2) Confirmar que una fecha no tenga duplicados (PK lo evita, pero validamos la fuente)
-- (Si devuelve filas, toca deduplicar mejor el staging antes del INSERT)
WITH ultima AS (SELECT MAX(fecha_corte) AS f FROM fact_inventario)
SELECT fi.fecha_corte, fi.almacen_sk, fi.articulo_sk, COUNT(*) AS n
FROM fact_inventario fi, ultima u
WHERE fi.fecha_corte = u.f
GROUP BY 1,2,3 HAVING COUNT(*)>1;

-- D3) Distribución por tipo de almacén (útil para DC vs Tiendas)
WITH ultima AS (SELECT MAX(fecha_corte) AS f),
agg AS (
  SELECT al.tipo, SUM(fi.existencia) AS unidades
  FROM fact_inventario fi
  JOIN dim_almacen al ON al.almacen_sk = fi.almacen_sk
  JOIN ultima u ON u.f = fi.fecha_corte
  GROUP BY al.tipo
)
SELECT * FROM agg ORDER BY unidades DESC;

-- D4) Top 20 artículos por unidades en el último corte (para spot check)
WITH ultima AS (SELECT MAX(fecha_corte) AS f)
SELECT a.articulo_clave, SUM(fi.existencia) AS unidades
FROM fact_inventario fi
JOIN dim_articulo a ON a.articulo_sk = fi.articulo_sk
JOIN ultima u ON u.f = fi.fecha_corte
GROUP BY 1 ORDER BY 2 DESC LIMIT 20;

-- D5) Deltas vs corte previo (si tienes al menos 2 fechas)
WITH cortes AS (
  SELECT DISTINCT fecha_corte FROM fact_inventario ORDER BY 1 DESC LIMIT 2
),
r AS (
  SELECT fi.fecha_corte, fi.articulo_sk, fi.almacen_sk, fi.existencia
  FROM fact_inventario fi
  JOIN cortes c ON c.fecha_corte = fi.fecha_corte
),
piv AS (
  SELECT articulo_sk, almacen_sk,
         MAX(existencia) FILTER (WHERE fecha_corte=(SELECT MIN(fecha_corte) FROM cortes)) AS prev,
         MAX(existencia) FILTER (WHERE fecha_corte=(SELECT MAX(fecha_corte) FROM cortes)) AS curr
  FROM r GROUP BY 1,2
)
SELECT a.articulo_clave, al.almacen_codigo,
       COALESCE(prev,0) AS prev, COALESCE(curr,0) AS curr,
       COALESCE(curr,0)-COALESCE(prev,0) AS delta
FROM piv
JOIN dim_articulo a ON a.articulo_sk = piv.articulo_sk
JOIN dim_almacen al ON al.almacen_sk = piv.almacen_sk
ORDER BY ABS(COALESCE(curr,0)-COALESCE(prev,0)) DESC, a.articulo_clave
LIMIT 30;

-- E) Listas de remediacion (para corregir datos en origen)
-- E1) SKUs rechazados por formato (guardar para pedir corrección al área origen)
SELECT pr_almacen, pr_clave, pr_descripcion
FROM stg_existencias_familia
WHERE pr_clave ~* 'e[+-]?[0-9]' OR btrim(pr_clave)='0';

-- E2) Almacenes desconocidos en el staging (faltan en catálogo)
SELECT DISTINCT TRIM(pr_almacen) AS alm
FROM stg_existencias_familia s
LEFT JOIN dim_almacen d ON d.almacen_codigo = TRIM(s.pr_almacen)
WHERE TRIM(s.pr_almacen) IS NOT NULL AND d.almacen_sk IS NULL
ORDER BY 1;

-- E3) Códigos de familia que no están en el catálogo (hay que agregar al dim_familia)
SELECT TRIM(s.clasificacion) AS familia_codigo, COUNT(*) AS n
FROM stg_existencias_familia s
LEFT JOIN dim_familia df ON df.familia_codigo = TRIM(s.clasificacion)
WHERE s.clasificacion IS NOT NULL AND df.familia_id IS NULL
GROUP BY 1 ORDER BY n DESC;

-- E4) Proveedores sin nombre (para mejorar legibilidad en reportes)
SELECT proveedor_codigo
FROM dim_proveedor
WHERE proveedor_nombre IS NULL OR btrim(proveedor_nombre)='';

-- F) Checks de parametros para el sugerido (DOI/multiplo)
-- F1) Familias con DOI/múltiplo inválidos (debería devolver 0 filas)
SELECT familia_codigo, familia_nombre, doi_min, doi_max, multiplo_empaque
FROM dim_familia
WHERE doi_min <= 0 OR doi_max < doi_min OR multiplo_empaque <= 0;

-- F2) Cobertura de artículos por familia (útil para elegir un DOI realista)
SELECT df.familia_codigo, df.familia_nombre, COUNT(*) AS articulos
FROM dim_articulo da
JOIN dim_familia df ON df.familia_id = da.familia_id
GROUP BY 1,2 ORDER BY articulos DESC;

