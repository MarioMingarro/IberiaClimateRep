# =============================================================================
# ClimaRep - Configuración global
# =============================================================================
# Editar este archivo para adaptar las rutas y parámetros al análisis concreto.
# En todos los demás scripts este archivo se carga con source("config.R").

# ── Rutas de entrada ──────────────────────────────────────────────────────────

DIR_PRESENT_CLIMATE  <- "data/climate/present"    # Ruta a la carpeta con variables bioclimáticas recientes (*.tif).
DIR_FUTURE_CLIMATE   <- "data/climate/future"     #  Ruta a las sub-carpetas con variables bioclimáticas futuras. Una por por modelo: GFDL/, IPSL/, etc. (*.tif)
PATH_STUDY_AREA      <- "data/spatial/study_area.shp"      # Ruta al .shp que contiene el poligono delimitante el area de estudio.
PATH_PROTECTED_AREAS <- "data/spatial/protected_areas.shp" # Ruta al .shp que contiene el poligono de las Áreas Protegidas.

# ── Rutas de salida ───────────────────────────────────────────────────────────

DIR_OUT_CLIMATE  <- "results/01_climate"       # Ruta para almacenar los datos climáticos procesados
DIR_OUT_APS      <- "results/02_aps"           # Ruta para almacenar los resultados de representatividad por AP (N2000CRS)
DIR_OUT_GRID     <- "results/02_grid"          # Ruta para almacenar los resultados de representatividad de la cuadrícula (EUCRS)
DIR_OUT_CHANGE   <- "results/03_change"        # Ruta para almacenar los resultados de trayectorias de cambio (stable/lost/novel)
DIR_OUT_METRICS  <- "results/04_metrics"       #  Ruta para almacenar los resultados de métricas finales: rásteres y tablas

# ── Modelos de clima futuro ───────────────────────────────────────────────────

FUTURE_MODELS  <- c("GFDL", "IPSL", "MRI", "MPI", "UKESM1")
FUTURE_PERIOD  <- "2070"   # Etiqueta temporal del escenario futuro

# ── Parámetros del análisis ───────────────────────────────────────────────────

VIF_THRESHOLD   <- 5     # Umbral VIF para eliminar variables colineales
REP_THRESHOLD   <- 0.95  # Percentil de Mahalanobis para definir análogos en APs (P95)
EUCRS_THRESHOLD <- 1.00  # Percentil de Mahalanobis para definir análogos en la cuadrícula EUCRS (P100: rango completo)

# ── Filtro de calidad de polígonos ────────────────────────────────────────────

MIN_AREA_M2 <- 10e6   # Área mínima: 10 km²
MIN_IPQ     <- 0.01   # Cociente isoperimétrico mínimo

# ── Columnas identificadoras en el shapefile de APs ──────────────────────────

COL_AP_ID   <- "SITECODE"   # Identificador único
COL_AP_NAME <- "SITENAME"   # Nombre legible

# ── Variables bioclimáticas a excluir antes del VIF ──────────────────────────

EXCLUDE_BIOCLIM <- c("bio8", "bio9", "bio18", "bio19")

# ── Cuadrícula para EUCRS ─────────────────────────────────────────────────────
# Factor de agregación sobre el ráster de referencia para generar la cuadrícula.
# Ejemplo: factor 10 sobre un ráster de 1 km → cuadrícula de 10 km.

GRID_AGG_FACTOR <- 10

# ── Procesamiento paralelo ────────────────────────────────────────────────────
# Número de cores a utilizar en el procesamiento.
NUM_CORES <- 4