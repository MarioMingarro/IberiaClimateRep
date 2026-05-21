# =============================================================================
# ClimaRep - Configuración global
# =============================================================================
# Editar este archivo para adaptar las rutas y parámetros al análisis concreto.
# En todos los demás scripts este archivo se carga con source("config.R").

# Rutas de entrada----
DIR_PRESENT_CLIMATE <- "C:/A_TRABAJO/IberiaClimateRep_RES/BIOCLIM/1981-2010/1981-2010"
#DIR_PRESENT_CLIMATE  <- "C:/A_TRABAJO/IberiaClimateRep_RES/BIOCLIM/1981-2010" #"C:/A_TRABAJO/DATA/CHELSA/CLIMATOLOGIAS_IBERIA/bioclim"# C:/A_TRABAJO/DATA/CHELSA/PRESENT"    # Ruta a la carpeta con variables bioclimáticas recientes (*.tif).
DIR_FUTURE_CLIMATE   <- "C:/A_TRABAJO/DATA/CHELSA/FUTURE/2041_2070/SSP370"     #  Ruta a las sub-carpetas con variables bioclimáticas futuras. Una por por modelo: GFDL/, IPSL/, etc. (*.tif)
PATH_STUDY_AREA      <- "C:/A_TRABAJO/IberiaClimateRep_RES/DATA/Peninsula_Iberica_89.shp"      # Ruta al .shp que contiene el poligono delimitante el area de estudio.
PATH_PROTECTED_AREAS <- "C:/A_TRABAJO/IberiaClimateRep_RES/DATA/national_parks.shp" # Ruta al .shp que contiene el poligono de las Áreas Protegidas.

# "C:/A_TRABAJO/A_CLIMAREP_TEST/DATA/MURCIA.shp"  
# "C:/A_TRABAJO/A_CLIMAREP_TEST/DATA/PAS_murcia.shp"
DIR_CHELSA_MONTHLY <- "C:/A_TRABAJO/DATA/CHELSA/MONTHLY_1980_2022"
YEAR_START         <- 1981   # Año inicial (inclusive)
YEAR_END           <- 2010   # Año final  (inclusive)
CHELSA_TARGET_CRS  <- "EPSG:3035"   # CRS de salida (ETRS89-LAEA)
# Rutas de salida----

DIR_OUT_CLIMATE  <- "C:/A_TRABAJO/IberiaClimateRep_RES/01_climate"       # Ruta para almacenar los datos climáticos procesados
DIR_OUT_APS      <- "C:/A_TRABAJO/IberiaClimateRep_RES/02_aps"           # Ruta para almacenar los resultados de representatividad por AP (N2000CRS)
DIR_OUT_GRID     <- "C:/A_TRABAJO/IberiaClimateRep_RES/02_grid"          # Ruta para almacenar los resultados de representatividad de la cuadrícula (EUCRS)
DIR_OUT_CHANGE   <- "C:/A_TRABAJO/IberiaClimateRep_RES/SSP_370/03_change"        # Ruta para almacenar los resultados de trayectorias de cambio (stable/lost/novel)
DIR_OUT_METRICS  <- "C:/A_TRABAJO/IberiaClimateRep_RES/SSP_370/04_metrics"       #  Ruta para almacenar los resultados de métricas finales: rásteres y tablas

# Modelos de clima futuro----

FUTURE_MODELS  <- c("GFDL", "IPSL", "MRI", "MPI", "UKESM1")
FUTURE_PERIOD  <- "2041_2070"   # Etiqueta temporal del escenario futuro

# Parámetros del análisis----

VIF_THRESHOLD   <- 5     # Umbral VIF para eliminar variables colineales
REP_THRESHOLD   <- 0.95  # Percentil de Mahalanobis para definir análogos en APs (P95)
EUCRS_THRESHOLD <- 1.00  # Percentil de Mahalanobis para definir análogos en la cuadrícula EUCRS (P100: rango completo)

# Filtro de calidad de polígonos----

MIN_AREA_M2 <- 10e6   # Área mínima: 10 km²
MIN_IPQ     <- 0.01   # Cociente isoperimétrico mínimo

# Columnas identificadoras en el shapefile de APs----

COL_AP_ID   <-  "WDPA_PID"  # Identificador único "FinCode"
COL_AP_NAME <- "NAME"   # Nombre legible

# Variables bioclimáticas a excluir antes del VIF----

EXCLUDE_BIOCLIM <- c("bio8", "bio9", "bio18", "bio19")

# Cuadrícula para EUCRS----
# Factor de agregación sobre el ráster de referencia para generar la cuadrícula.
# Ejemplo: factor 10 sobre un ráster de 1 km → cuadrícula de 10 km.

GRID_AGG_FACTOR <- 10

# Procesamiento paralelo----
# Número de cores a utilizar en el procesamiento.
NUM_CORES <- 8