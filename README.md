# Task-Based Optimizer
 
      Este script optimiza temporalmente los recursos del sistema para una tarea específica y luego restaura
      el estado original. Es útil para compilar, renderizar, o ejecutar aplicaciones intensivas.

## Características Principales
 
*   **Optimización dinámica:** Ajusta CPU (governor), memoria (swappiness) e I/O (scheduler) según sea
      necesario.
*   **Restauración automática:** Devuelve el sistema a su estado original cuando se completa la tarea.
*   **Configuración de estado:** Guarda y restaura los valores originales de CPU, memoria, y disco.
*   **Uso de Wrapper:** Incluye un wrapper para facilitar la ejecución con privilegios de root.
 
## Archivos Incluidos
 
*   `task-optimizer.sh`: Script principal para la optimización y restauración.
*   `task-optimizer-wrapper.sh`: Script para ejecutar el optimizador con `sudo`.
*   `README.md`: Esta descripción.
 
## Uso
 
   1.  Clona o descarga el repositorio.
   2.  Haz los scripts ejecutables: `chmod +x task-optimizer*.sh`
   3.  (Opcional) Instala el script globalmente o ejecuta directamente.
   4.  Inicia la optimización para una tarea (requiere `sudo`):
              sudo ./task-optimizer-wrapper.sh start "Descripción de tu tarea intensiva"

   5.  Una vez terminada la tarea, restaura el sistema:
              sudo ./task-optimizer-wrapper.sh stop

   6.  Consulta el estado: `sudo ./task-optimizer-wrapper.sh status`
 
## Autor
 
*	**Marco Andre Yunge** 
 
## Notas Importantes
 
*   El script requiere privilegios de root para aplicar las optimizaciones.
*   Las optimizaciones son temporales y se deshacen con `task-optimizer stop`.


