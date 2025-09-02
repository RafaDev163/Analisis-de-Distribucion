## Carga semanal de existencias (MVP-1) <!-- NUEVO -->

Este procedimiento se ejecuta **cada lunes** para cargar el reporte de existencias que incluye la columna de clasificación.

### Pasos

1. **Subir archivo CSV al contenedor**
   ```powershell
   docker cp .\db\seed\existencias_con_clasificacion.csv pg16:/csv/existencias_con_clasificacion.csv

2. **Convertir a UTF-8**

    docker exec -it pg16 bash -lc "iconv -f WINDOWS-1252 -t UTF-8 /csv/existencias_con_clasificacion.   csv > /sql/existencias_clasif_utf8.csv"

3. **Truncar staging y cargar datos**
    Asegúrate de que el orden de columnas en el COPY coincida con el header del CSV.
    TRUNCATE stg_existencias_familia;

    \copy stg_existencias_familia (
        pr_almacen,
        pr_clave,
        pr_descripcion,
        pr_costo,
        pr_existencia,
        clasificacion,  -- código de familia
        proveedor,
        ps_nombre
    )
    FROM '/sql/existencias_clasif_utf8.csv' CSV HEADER;

4. **Normalizar datos**

    UPDATE stg_existencias_familia
        SET pr_almacen     = NULLIF(btrim(pr_almacen),''),
            pr_clave       = upper(NULLIF(btrim(pr_clave),'')),
            pr_descripcion = NULLIF(btrim(pr_descripcion),''),
            proveedor      = NULLIF(btrim(proveedor),''),
            ps_nombre      = NULLIF(btrim(ps_nombre),''),
            clasificacion  = NULLIF(btrim(clasificacion),'');

5. **Ejecutar QA checks**

    \i /db/migrations/R_qa__checks_mvp1.sql

6. **Actualizar dimensiones**
    * dim_almacen (altas de almacenes nuevos)

    * dim_proveedor (altas/actualización de proveedores)

    * dim_articulo (altas/actualización de artículos)

    * dim_familia (mapeo por código de familia)

7. **Generar snapshot de inventario**

    Insertar en fact_inventario con deduplicación por (fecha_corte, almacen_sk, articulo_sk):

    WITH params AS (SELECT CURRENT_DATE::date AS fecha_corte),
        src AS (
        SELECT (SELECT fecha_corte FROM params) AS fecha_corte,
            al.almacen_sk,
            a.articulo_sk,
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
    SET existencia = EXCLUDED.existencia;

8. **Validaciones finales**
    * Conteo de filas en staging 
        SELECT COUNT(*) FROM stg_existencias_familia;
    
    * Artículos con familia asignada:
        SELECT COUNT(*) FROM dim_articulo WHERE familia_id IS NOT NULL;
    
    * Códigos de familia faltantes en catálogo:
        SELECT clasificacion, COUNT(*)
        FROM stg_existencias_familia s
        LEFT JOIN dim_familia df ON df.familia_codigo = TRIM(s.clasificacion)
        WHERE df.familia_id IS NULL
        GROUP BY 1 ORDER BY 2 DESC;
    
    * Resumen del snapshot:
        SELECT fecha_corte, COUNT(*) AS filas, SUM(existencia) AS total_unidades
        FROM fact_inventario
        GROUP BY 1 ORDER BY 1 DESC LIMIT 5;

