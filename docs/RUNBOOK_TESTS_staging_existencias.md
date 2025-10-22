-- A QA del staging stg_existencias_familia 
-- A1 Volumen total
SELECT COUNT(*) AS rows_stg FROM stg_existencias_familia;

-- A2 Nulos o vacíos en campos clave
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