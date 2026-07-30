# =============================================================================
# ClimaRep - Configuración global
# =============================================================================
# Editar este archivo para adaptar las rutas y parámetros al análisis concreto.
# En todos los demás scripts este archivo se carga con source("0_configuracion.R").

# Rutas de entrada----
DIR_PRESENT_CLIMATE <- "C:/A_TRABAJO/DATA/CHELSA/BIOCLIM_1981_2010" ##a
DIR_FUTURE_CLIMATE   <- "C:/A_TRABAJO/DATA/CHELSA/FUTURE/2041_2070/SSP370"     #  Ruta a las sub-carpetas con variables bioclimáticas futuras. Una por por modelo: GFDL/, IPSL/, etc. (*.tif)
PATH_STUDY_AREA      <- "C:/A_TRABAJO/IberiaClimateRep_RES/DATA/ES_land_LAEA89_10km.shp"      # Ruta al .shp que contiene el poligono delimitante el area de estudio.
PATH_PROTECTED_AREAS <- "C:/A_TRABAJO/IberiaClimateRep_RES/DATA/N2000_ES_LAEA89.shp" # national_parks.shp  # Ruta al .shp que contiene el poligono de las Áreas Protegidas.

# Datos para el análisis del gradiente altitudinal (Paso 5)
PATH_DEM            <- "C:/A_TRABAJO/N2000_CLIMAREP/DATA/DEM/wc2.1_30s_elev_EU_LAEA.tif"   # Modelo Digital de Elevaciones
COL_BIOREGION       <- "code"        # Campo del shapefile con el código/nombre de la región

DIR_CHELSA_MONTHLY <- "C:/A_TRABAJO/DATA/CHELSA/MONTHLY_1980_2022"
YEAR_START         <- 1981   # Año inicial (inclusive)
YEAR_END           <- 2010   # Año final  (inclusive)
TARGET_CRS  <- "EPSG:4623"   # CRS de salida 

# Rutas de salida----

DIR_OUT_CLIMATE      <- "C:/A_TRABAJO/climarep_iberia/SSP370/01_climate"        # Ruta para almacenar los datos climáticos procesados
DIR_OUT_APS_CHANGE   <- "C:/A_TRABAJO/climarep_iberia/SSP370/02_aps"     # mh_rep_ch sobre APs (sustituye a 02_aps y 03_change)
DIR_OUT_GRID_CHANGE  <- "C:/A_TRABAJO/climarep_iberia/SSP370/03_grid"    # mh_rep_ch sobre la cuadrícula (sustituye al EUCRS clásico con mh_rep)
DIR_OUT_METRICS      <- "C:/A_TRABAJO/climarep_iberia/SSP370/04_metrics"        # Ruta para almacenar los resultados de métricas finales: rásteres y tablas
DIR_OUT_ELEVATION    <- "C:/A_TRABAJO/climarep_iberia/SSP370/05_elevation"      # Salidas del análisis de gradiente altitudinal (chi-cuadrado)

# Modelos de clima futuro----

FUTURE_MODELS  <- c("GFDL", "IPSL", "MRI", "MPI", "UKESM1")
FUTURE_PERIOD  <- "2040_2070"   # Etiqueta temporal del escenario futuro
ENSEMBLE_LABEL <- "ENSEMBLE"    # Etiqueta usada como argumento `model` en mh_rep_ch

# Parámetros del análisis----

VIF_THRESHOLD   <- 5    # Umbral VIF para eliminar variables colineales
REP_THRESHOLD   <- 0.95  # Percentil de Mahalanobis para definir análogos en APs (P95)
EUCRS_THRESHOLD <- 1.00  # Percentil de Mahalanobis para definir análogos en la cuadrícula EUCRS (P100: rango completo)

# Filtro de calidad de polígonos----

MIN_AREA_M2 <- 5e6   # Área mínima: 10 km²
MIN_IPQ     <- 0.01   # Cociente isoperimétrico mínimo

# Columnas identificadoras en el shapefile de APs----

COL_AP_ID   <- "site_code"  # "WDPA_PID"Identificador único "FinCode"
COL_AP_NAME <- "SITE_NAME"  #"NAME"   # Nombre legible

# Variables bioclimáticas a excluir antes del VIF----

EXCLUDE_BIOCLIM <- c("bio08" ,"bio09", "bio18", "bio19")

# Cuadrícula para EUCRS----
# Factor de agregación sobre el ráster de referencia para generar la cuadrícula.
# Ejemplo: factor 10 sobre un ráster de 1 km → cuadrícula de 10 km.

GRID_AGG_FACTOR <- 10

# Procesamiento paralelo----
# Número de cores a utilizar en el procesamiento.
NUM_CORES <- 10
