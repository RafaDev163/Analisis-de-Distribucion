**Cargamos reporte** 
    docker cp .\db\seed\ventasproductosclasificacion.csv pg16:/csv/ventasproductosclasificacion.csv
**Convertimos a UTF8**
    docker cp .\db\seed\ventasproductosclasificacion.csv pg16:/csv/ventasproductosclasificacion.csv
**Actualizamos periodos y almacen**
    
**Corremos stg_ventas**
    docker exec -it pg16 psql -U rafa -d Inventario_TMAP -f /sql/V7__stg_ventas.run.sql
**Corremos fact_ventas**
    docker exec -it pg16 psql -U rafa -d Inventario_TMAP -f /sql/V7a__fact_ventas.run.sql

