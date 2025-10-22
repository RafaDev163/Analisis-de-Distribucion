## Carga semanal de existencias (MVP-1) <!-- NUEVO -->

Este procedimiento se ejecuta **cada lunes** para cargar el reporte de existencias que incluye la columna de clasificación.

### Pasos

1. **Subir archivo CSV al contenedor**
   ```powershell
   docker cp .\db\seed\existencias_con_clasificacion.csv pg16:/csv/existencias_con_clasificacion.csv

2. **Convertir a UTF-8**

    docker exec -it pg16 bash -lc "iconv -f WINDOWS-1252 -t UTF-8 /csv/existencias_con_clasificacion.csv > /csv/existencias_con_clasificacion_utf8.csv"

3. **Truncar staging y cargar datos**
    Asegúrate de que el orden de columnas en el COPY coincida con el header del CSV.
    docker exec -it pg16 psql -U rafa -d Inventario_TMAP -c "TRUNCATE stg_existencias_familia;"

    docker exec -it pg16 psql -U rafa -d Inventario_TMAP -c `
    "\copy stg_existencias_familia (
        pr_almacen, pr_clave, pr_descripcion, pr_costo, pr_existencia,
        clasificacion, proveedor, ps_nombre
    ) FROM '/csv/existencias_con_clasificacion_utf8.csv' CSV HEADER;"

4. **Normalizar datos**
    docker exec -it pg16 psql -U rafa -d Inventario_TMAP -c `
    "UPDATE stg_existencias_familia
        SET pr_almacen     = NULLIF(btrim(pr_almacen),''),
            pr_clave       = upper(NULLIF(btrim(pr_clave),'')),
            pr_descripcion = NULLIF(btrim(pr_descripcion),''),
            proveedor      = NULLIF(btrim(proveedor),''),
            ps_nombre      = NULLIF(btrim(ps_nombre),''),
            clasificacion  = NULLIF(btrim(clasificacion),'');"

5. **Ejecutar QA checks**

    \i /db/migrations/R_qa__checks_mvp1.sql

6. **Actualizar dimensiones**
    * dim_almacen (altas de almacenes nuevos)

    docker exec -it pg16 psql -U rafa -d Inventario_TMAP -c `
    "INSERT INTO dim_almacen (almacen_codigo, tipo, nombre, activo)
    SELECT DISTINCT TRIM(pr_almacen),
        CASE WHEN TRIM(pr_almacen) IN ('101','102') THEN 'PRINCIPAL'
              WHEN TRIM(pr_almacen) IN ('103','105','106') THEN 'TIENDA'
              ELSE 'DESCONOCIDO' END,
         NULL::TEXT, TRUE
    FROM stg_existencias_familia
    WHERE NULLIF(TRIM(pr_almacen),'') IS NOT NULL
    ON CONFLICT (almacen_codigo) DO UPDATE SET activo = TRUE;"

    * dim_proveedor (altas/actualización de proveedores)

    docker exec -it pg16 psql -U rafa -d Inventario_TMAP -c `
    "WITH src AS (
        SELECT TRIM(proveedor) AS proveedor_codigo,
           NULLIF(TRIM(ps_nombre),'') AS proveedor_nombre
        FROM stg_existencias_familia
        WHERE NULLIF(TRIM(proveedor),'') IS NOT NULL
    ),
    dedup AS (
        SELECT proveedor_codigo,
           COALESCE(MAX(proveedor_nombre), NULL) AS proveedor_nombre
        FROM src
        GROUP BY proveedor_codigo
    )
    INSERT INTO dim_proveedor (proveedor_codigo, proveedor_nombre)
    SELECT proveedor_codigo, proveedor_nombre
    FROM dedup
    ON CONFLICT (proveedor_codigo) DO UPDATE
    SET proveedor_nombre = COALESCE(EXCLUDED.proveedor_nombre, dim_proveedor.proveedor_nombre);"

    * dim_articulo (altas/actualización de artículos)

     docker exec -it pg16 psql -U rafa -d Inventario_TMAP -c `
    "WITH src AS (
        SELECT TRIM(pr_clave) AS articulo_clave,
          NULLIF(TRIM(pr_descripcion),'') AS descripcion
        FROM stg_existencias_familia
        WHERE NULLIF(TRIM(pr_clave),'') IS NOT NULL
    ),
    dedup AS (
        SELECT articulo_clave,
          -- elige una descripción no nula (puedes cambiar el criterio)
          COALESCE(MAX(descripcion), NULL) AS descripcion
        FROM src
        GROUP BY articulo_clave
    )
    INSERT INTO dim_articulo (articulo_clave, descripcion, activo)
    SELECT articulo_clave, descripcion, TRUE
    FROM dedup
    ON CONFLICT (articulo_clave) DO UPDATE
    SET descripcion = COALESCE(EXCLUDED.descripcion, dim_articulo.descripcion),
    activo = TRUE;"

    * dim_familia (mapeo por código de familia)
     docker exec -it pg16 psql -U rafa -d Inventario_TMAP -c `
         "BEGIN;

     -- Asegura que dim_familia ya está cargada con códigos (R6__seed_dim_familia_desde_catalogo.sql)
     -- Mapea por codigo de familia
     UPDATE dim_articulo da
     SET familia_id = df.familia_id
     FROM stg_existencias_familia s
     JOIN dim_familia df
        ON df.familia_codigo = TRIM(s.clasificacion)  -- ← aquí usamos el CÓDIGO
        WHERE da.articulo_clave = TRIM(s.pr_clave)
        AND s.clasificacion IS NOT NULL;

 COMMIT;"
    
    * limpieza de claves extrañas (notacion cientifica, no las usamos en este momento)

    docker exec -it pg16 psql -U rafa -d Inventario_TMAP -c `
    "DELETE FROM stg_existencias_familia
        WHERE pr_almacen IS NULL
            OR pr_clave   IS NULL
            OR btrim(pr_almacen) = '0'
            OR btrim(pr_clave)   = '0';

         -- 1B) Quitar filas con clave en notación científica (p.ej. '9.90E12')
        --     Si tu CSV ya viene así, NO se puede recuperar la clave correcta: hay que reexportar como texto desde origen.
         DELETE FROM stg_existencias_familia
         WHERE pr_clave ~* 'e[+-]?[0-9]';  -- detecta patrones tipo 9.90E12, 1E6, etc."
   

7. **Generar snapshot de inventario**

    Insertar en fact_inventario con deduplicación por (fecha_corte, almacen_sk, articulo_sk):
     $FECHA_CORTE = "especificar fecha que se usara para el corte formato: YYYY-MM-DD"
     
     docker exec -it pg16 psql -U rafa -d Inventario_TMAP -c `
     "WITH params AS (SELECT DATE '$FECHA_CORTE' AS fecha_corte),
     src AS (
        SELECT (SELECT fecha_corte FROM params) AS fecha_corte,
           al.almacen_sk, a.articulo_sk,
           GREATEST(COALESCE(s.pr_existencia,0),0) AS existencia
        FROM stg_existencias_familia s
        JOIN dim_almacen  al ON al.almacen_codigo = TRIM(s.pr_almacen)
        JOIN dim_articulo a  ON a.articulo_clave   = TRIM(s.pr_clave)
    ),
    dedup AS (
        SELECT fecha_corte, almacen_sk, articulo_sk, SUM(existencia)::INT AS existencia
        FROM src
        GROUP BY 1,2,3
    )
    INSERT INTO fact_inventario (fecha_corte, almacen_sk, articulo_sk, existencia)
    SELECT fecha_corte, almacen_sk, articulo_sk, existencia
    FROM dedup
    ON CONFLICT (fecha_corte, almacen_sk, articulo_sk) DO UPDATE
        SET existencia = EXCLUDED.existencia;"

8. **Validaciones finales**
    * Conteo de filas en staging
        docker exec -it pg16 psql -U rafa -d Inventario_TMAP -c `
        "SELECT COUNT(*) FROM stg_existencias_familia;"
    
    * Artículos con familia asignada:
        docker exec -it pg16 psql -U rafa -d Inventario_TMAP -c `
        "SELECT COUNT(*) FROM dim_articulo WHERE familia_id IS NOT NULL;"
    
    * Códigos de familia faltantes en catálogo:
        docker exec -it pg16 psql -U rafa -d Inventario_TMAP -c `
        "SELECT clasificacion, COUNT(*)
        FROM stg_existencias_familia s
        LEFT JOIN dim_familia df ON df.familia_codigo = TRIM(s.clasificacion)
        WHERE df.familia_id IS NULL
        GROUP BY 1 ORDER BY 2 DESC;"
    
    * Resumen del snapshot:
        docker exec -it pg16 psql -U rafa -d Inventario_TMAP -c `
        "SELECT fecha_corte, COUNT(*) AS filas, SUM(existencia) AS total_unidades
        FROM fact_inventario
        GROUP BY 1 ORDER BY 1 DESC LIMIT 5;"

