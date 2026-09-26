# Roadmap de BodegaFlow (Scanflow)

Decisiones de producto que no se deducen del código y que conviene dejar escritas
para que una iteración futura no las vuelva a abrir por inercia.

Estado actual: **v1.0.1** en producción. La siguiente iteración es **v1.1**.

---

## v1.1 — Impresión de etiquetas (`PrinterScreen`)

**Decisión: la impresión de etiquetas se mantiene en el plan gratuito. No se
aplica `ProGate`.**

### Contexto

Durante el QA del PR #24 (restricción de métricas OSA y exportación PDF) se
planteó si `PrinterScreen` ("Imprimir (PDF)" / etiquetas) debía pasar también
detrás de `ProGate.allowPrintLabels` en la v1.1, para no regalar una función de
impresión a la versión gratuita.

### Argumento

- La impresión de etiquetas es el flujo con el que la bodega **entra** a la
  aplicación: es lo primero que necesita hacer después de cargar el inventario.
  Cobrarla obliga a que el usuario Nuevo se suscriba antes de probar el producto.
- Es una función de **margen cero**: la app no paga por cada impresión, así que
  no protege un coste de servidor.
- El modelo Freemium ya se apoya en funciones cuyo valor sí crece con el tamaño
  de la operación (catálogo ilimitado, OSA, exportación PDF). Las etiquetas no
  compiten con ninguna de ellas: el plan gratuito puede ofrecerlas sin erosionar
  el argumento de venta de PRO.

### Consecuencias asumidas

- `PrinterScreen` **no** consulta `ProProvider` ni abre el paywall.
- La fila "Impresión de etiquetas" aparece en la tabla comparativa del paywall
  como **incluida en ambos planes** y **sin** destacar con el icono de PRO, para
  que la diferencia entre planes sea explícita y no haya que deducirla.
- Está cubierto por tests de widget que fallarían si alguien añadiera un
  `ProGate` a esta pantalla.

### Cuándo reconsiderarlo

Solo si aparece un coste de impresión asociado (consumo de papel, licencias de
proveedor) o si el uso se vuelve abusivo. En ese caso, la vía sería
`ProGate.allowPrintLabels` y marcar la fila como `highlight` en el paywall.
