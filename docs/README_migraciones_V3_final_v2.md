# Migraciones — Estado Final (V3_final actualizado)

Este documento actualiza el V3_final previo, incorporando cambios recientes:
- Proveedor principal con trazabilidad **UNICO/VALIDADO** (dominante opcional).
- Modalidad **FIRME** incluye también prefijo **NA** además de AFF/AF/F/FF.
- Rebuild del puente **articulo_proveedor** directamente desde **CSV**.
- Limpieza de residuos (prefijo vs prefijo+ceros) y cuarentena de claves raras.
- Vistas finales V5 basadas en **articulo_clave** y resúmenes por familia/proveedor.

## Diferencias clave vs. README anterior
- Antes: modalidad por `AFF|AF|F|FF|C+`; ahora **`NA` también es FIRME**.
- Antes: proveedor inferido por parseo en algunos parches; ahora **siempre del CSV** y solo se parsea **familia** (cuando aplique).

## Aplicación en BD fresh
1. Verifica `stg_existencias` (claves como TEXT, proveedor correcto).
2. Ejecuta `V3_final__modelo_dimensional_y_carga.sql`.
3. Ejecuta `V5_final_vistas.sql` para publicar las vistas de UI.
4. Corre los checks de higiene (multi-proveedor, claves raras).

## Notas operativas
- Orígenes de proveedor principal:
  - **UNICO**: único proveedor por clave en CSV (confiable).
  - **VALIDADO**: el proveedor de CSV “calza” visualmente en la clave (permite ceros) (confiable).
  - **DOMINANTE**: opcional, por frecuencia (menos confiable).
