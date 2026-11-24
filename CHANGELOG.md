# Historial de cambios

## 1.4

- Interfaz nativa con navegación lateral, vista previa fija y secciones Monitoreo, Apariencia y General.
- Lecturas permanentes como barra de estado al final de la sidebar, recurso vigilado en primer lugar y vista previa compacta en el pie.
- Versión exclusivamente en el panel estándar Acerca de macOS; retirada la página separada de actividad.
- Corregido el recorte físico: vista de 1085 pt dentro de una región de 1004 pt; etiqueta y recorrido basados en visibleRect.
- Corregidos brillo y movimiento de Radar, Respiración y KITT doble con paleta Original; reloj común y pruebas temporales.
- Selección segmentada Aplicación/PID manual, actualización específica por modo y recurso/sensibilidad en Monitoreo.
- Animación, galería, color y etiqueta reunidos en Apariencia; lecturas permanentes en la sidebar.
- Cambios de controles síncronos para que las muestras del monitor no reviertan la etiqueta; prueba de integración con muestreo activo.
- Galería de 20 efectos; añadidos Ondas, Radar, Partículas, Respiración y KITT doble.
- Etiqueta flotante con margen de 14 pt, texto blanco y fondo oscuro. Su interruptor no modifica el ancho de la animación; funciona sin PID y en reposo.
- Migración compartida de la preferencia antigua de iniciales y restauración de preferencias de visualización.
- Item principal de Touch Bar flexible al ancho asignado por macOS.
- Pruebas de dibujo AppKit, capturas reproducibles claras/oscuras y workflow de macOS.
- Configuración de ARC habilitada en Xcode, como ya hacía build.sh.
- Fuentes de muestreo existentes conservadas.

## 1.3.1

- Corregidas dos llamadas a `ProcessScan(...)` tras introducir las métricas de hilos y cambios de contexto.
- Estado sin procesos: ambas métricas se inicializan a cero.
- Estado activo: se usan los valores agregados calculados durante el muestreo.

# Cambios

## v1.3

- Un solo proceso objetivo en Settings, reemplazo al vigilar otro PID y agregación de descendientes accesibles.
- Dos pestañas compactas: Monitoreo y Apariencia. Idioma, inicio automático, Acerca de y Fuentes de datos/Diagnóstico en el menú superior.
- Ancho preferido de Touch Bar de 920 a 1085 pt, cálculo geométrico para que el último segmento termine al final del área asignada y vista previa sin relleno lateral.
- Tres efectos: VU central, digital y pulsos de señal (15 en total).
- Dos métricas con `libproc`: hilos vivos y cambios de contexto por segundo (8 en total).
- API `/add` pasa a reemplazar el objetivo, como `/watch`, para mantener un único objetivo de interfaz.
- Nuevas pruebas de escala y geometría.
- Sin `nettop` y sin mediciones de red/GPU al elegir otros recursos.

## v1.2.1

- Corrección de los encabezados dinámicos de `Section`.
