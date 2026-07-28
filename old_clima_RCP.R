# =============================================================================
# ClimaRep - Configuración global  (escenario RCP 4.5, horizonte 2041-2070)
# =============================================================================
# Editar este archivo para adaptar rutas y parámetros al análisis concreto.
# En el resto de scripts se carga con source("0_configuracion.R").

# Rutas de entrada -----------------------------------------------------------

# Carpeta única que contiene tanto las variables del PRESENTE (sufijo _PRE)
# como las del FUTURO RCP 4.5 (sufijo _45_50).
DIR_RCP45_RAW <- "C:/A_TRABAJO/IberiaClimateRep_RES/RCP45"

# Por compatibilidad con el resto de scripts mantenemos las variables originales
# apuntando a la misma carpeta: la separación presente/futuro la hace el script
# de preparación (01_preparar_clima_RCP45.R) según el patrón del nombre.
DIR_PRESENT_CLIMATE <- DIR_RCP45_RAW
DIR_FUTURE_CLIMATE  <- DIR_RCP45_RAW

# Área de estudio y áreas protegidas (parques nacionales de la Península)
PATH_STUDY_AREA      <- "C:/A_TRABAJO/IberiaClimateRep_RES/DATA/Peninsula_Iberica_89.shp"
PATH_PROTECTED_AREAS <- "C:/A_TRABAJO/IberiaClimateRep_RES/DATA/national_parks.shp"

# CHELSA mensual (no se usa en este flujo simplificado, se mantiene por compatibilidad)
DIR_CHELSA_MONTHLY <- "C:/A_TRABAJO/DATA/CHELSA/MONTHLY_1980_2022"
YEAR_START         <- 1981
YEAR_END           <- 2010

# CRS de trabajo. ETRS89-LAEA (EPSG:3035) es el estándar EEA para Europa.
CHELSA_TARGET_CRS  <- "EPSG:3035"

# CRS de origen de los rásteres RCP45 si no traen CRS embebido --------------
# Los TIF con world file (.tfw) suelen carecer de CRS interno; aquí indicamos
# el CRS supuesto de origen. Ajustar si los datos están en otra proyección.
# Sospechas más probables para Iberia: EPSG:23030 (ED50/UTM30N),
# EPSG:25830 (ETRS89/UTM30N) o EPSG:4326 (WGS84 lat-long).
SOURCE_CRS_FALLBACK <- "EPSG:25830"

# Rutas de salida ------------------------------------------------------------
# Todas dentro de una carpeta específica del escenario para no mezclar resultados.

DIR_OUT_BASE     <- "C:/A_TRABAJO/IberiaClimateRep_RES/RCP45"
DIR_OUT_CLIMATE  <- file.path(DIR_OUT_BASE, "01_climate")   # stacks homogeneizados
DIR_OUT_APS      <- file.path(DIR_OUT_BASE, "02_aps")       # representatividad por AP
DIR_OUT_GRID     <- file.path(DIR_OUT_BASE, "02_grid")      # EUCRS
DIR_OUT_CHANGE   <- file.path(DIR_OUT_BASE, "03_change")    # stable/lost/novel
DIR_OUT_METRICS  <- file.path(DIR_OUT_BASE, "04_metrics")   # tablas y rásteres finales

# Modelo / escenario futuro --------------------------------------------------
# En este flujo solo hay un set de variables futuras (ya promediadas o un único
# modelo), así que no hay ensemble propiamente dicho. Se etiqueta como RCP45.
FUTURE_MODELS <- c("RCP45")
FUTURE_PERIOD <- "2041_2070"

# Parámetros del análisis ----------------------------------------------------

VIF_THRESHOLD   <- 5      # Umbral VIF (no se aplica con solo 5 variables)
REP_THRESHOLD   <- 0.95   # Percentil de Mahalanobis para APs (P95)
EUCRS_THRESHOLD <- 1.00   # Percentil de Mahalanobis para EUCRS (P100)

# Filtro de calidad de polígonos --------------------------------------------

MIN_AREA_M2 <- 10e6   # 10 km² mínimo
MIN_IPQ     <- 0.01   # Cociente isoperimétrico mínimo

# Columnas identificadoras en el shapefile de APs ---------------------------

COL_AP_ID   <- "WDPA_PID"
COL_AP_NAME <- "NAME"

# Variables bioclimáticas a excluir antes del VIF ---------------------------
# En este flujo no aplica porque solo hay bio1, bio3, bio5, bio7, bio13.
EXCLUDE_BIOCLIM <- c("bio8", "bio9", "bio18", "bio19")

# Cuadrícula para EUCRS ------------------------------------------------------

GRID_AGG_FACTOR <- 10

# Procesamiento paralelo ----------------------------------------------------
NUM_CORES <- 8


# =============================================================================
# ClimaRep - Paso 1: Homogeneización de capas climáticas (RCP4.5)
# =============================================================================
# Carga las 5 variables del PRESENTE (*_PRE.tif) y del FUTURO (*_45_50.tif)
# desde la misma carpeta RCP, las alinea (CRS, extent, resolución, máscara
# de NAs) y las guarda en DIR_OUT_CLIMATE como:
#   - present_climate_VIF.tif             (consumido por 02_ejecutar_climarep.R)
#   - future_climate_ensemble_MEAN.tif    (consumido por 02_ejecutar_climarep.R)
#
# Este paso DEBE ejecutarse antes que 02_ejecutar_climarep.R.
# Después, 02 funciona sin tocar nada porque los nombres de archivo coinciden
# con los que ya espera.
# -----------------------------------------------------------------------------

source("0_configuracion.R")

library(terra)
library(sf)

# -----------------------------------------------------------------------------
# Configuración local del paso de homogeneización
# -----------------------------------------------------------------------------

# Carpeta donde están las 10 capas (5 PRE + 5 _45_50). AJUSTAR si procede.
DIR_RCP45 <- "C:/A_TRABAJO/IberiaClimateRep_RES/RCP45"

# Pares de variables: nombre estandarizado + archivo presente + archivo futuro.
# El "name" es el que tendrán las bandas en AMBOS rásters (presente y futuro).
# Es CRÍTICO que coincidan: ClimaRep::mh_rep_ch() compara espacios climáticos
# pareando bandas por nombre.
VAR_PAIRS <- list(
  list(name = "tmed_anual",    pre = "TMEDANUAL_PRE.tif",  fut = "temp_med_anual_45_50.tif"),
  list(name = "rango_termico", pre = "CONTERMICO_PRE.tif", fut = "rango_temp_anual_45_50.tif"),
  list(name = "tmax_mescal",   pre = "TMYRMAXMES_PRE.tif", fut = "temp_max_mescal_45_50.tif"),
  list(name = "isotermal",     pre = "ISOTHERMAL_PRE.tif", fut = "isotermal_45_50.tif"),
  list(name = "prec_meshum",   pre = "PRMESHUM_PRE.tif",   fut = "prec_meshum_45_50.tif")
)

# Cuál de los rásters usar como TEMPLATE geométrico (extent + res + CRS).
# Opciones: "present" (usa el primer PRE) o "future" (usa el primer _45_50).
# Recomendado: el de MAYOR resolución (celda más pequeña). Por defecto presente.
TEMPLATE_SOURCE <- "present"

# Método de remuestreo para variables continuas (clima).
RESAMPLE_METHOD <- "bilinear"

# -----------------------------------------------------------------------------
# Comprobaciones previas
# -----------------------------------------------------------------------------

dir.create(DIR_OUT_CLIMATE, recursive = TRUE, showWarnings = FALSE)

# Verificar que existen los 10 archivos antes de empezar
all_files <- c(
  vapply(VAR_PAIRS, \(v) file.path(DIR_RCP45, v$pre), character(1)),
  vapply(VAR_PAIRS, \(v) file.path(DIR_RCP45, v$fut), character(1))
)
missing <- all_files[!file.exists(all_files)]
if (length(missing) > 0) {
  stop("No se encuentran estos archivos:\n  ", paste(missing, collapse = "\n  "))
}
message("Encontrados ", length(all_files), " archivos en ", DIR_RCP45)

# -----------------------------------------------------------------------------
# 1. Construir el TEMPLATE geométrico
# -----------------------------------------------------------------------------

template_file <- if (TEMPLATE_SOURCE == "future") {
  file.path(DIR_RCP45, VAR_PAIRS[[1]]$fut)
} else {
  file.path(DIR_RCP45, VAR_PAIRS[[1]]$pre)
}
template <- terra::rast(template_file)

# Si el CRS estuviera vacío en el TIF (suele pasar cuando solo hay .tfw),
# descoméntese la siguiente línea con el EPSG que corresponda al dato:
# terra::crs(template) <- "EPSG:25830"   # ETRS89 / UTM 30N (típico Iberia)

if (is.na(terra::crs(template)) || terra::crs(template) == "") {
  stop("El ráster template no tiene CRS definido. Asignalo manualmente con\n",
       "  terra::crs(template) <- \"EPSG:xxxxx\"   # p.ej. 25830 o 3035")
}

message("Template: ", basename(template_file))
print(template)

# -----------------------------------------------------------------------------
# 2. Cargar el área de estudio en el CRS del template (para máscara común)
# -----------------------------------------------------------------------------

study_area <- sf::read_sf(PATH_STUDY_AREA) |>
  sf::st_transform(terra::crs(template))
study_vect <- terra::vect(study_area)

# -----------------------------------------------------------------------------
# 3. Función auxiliar: alinea cualquier ráster al template
# -----------------------------------------------------------------------------

align_to_template <- function(path, template, layer_name,
                              method = RESAMPLE_METHOD) {
  r <- terra::rast(path)
  
  # Asignar CRS si falta (asume el del template). Descomenta y ajusta si los
  # rásters del futuro vinieran en otro CRS conocido.
  if (is.na(terra::crs(r)) || terra::crs(r) == "") {
    warning("CRS ausente en ", basename(path), ": asumiendo CRS del template.")
    terra::crs(r) <- terra::crs(template)
  }
  
  # Reproyectar si difiere del template
  if (terra::crs(r, proj = TRUE) != terra::crs(template, proj = TRUE)) {
    message("  · reproyectando ", basename(path))
    r <- terra::project(r, terra::crs(template), method = method)
  }
  
  # Resample alinea extent + resolución + origen de celda al template
  r <- terra::resample(r, template, method = method)
  
  names(r) <- layer_name
  r
}

# -----------------------------------------------------------------------------
# 4. Procesar presente y futuro
# -----------------------------------------------------------------------------

message("\nHomogeneizando capas del PRESENTE...")
pres_layers <- lapply(VAR_PAIRS, function(v) {
  message("  - ", v$name, "  <- ", v$pre)
  align_to_template(file.path(DIR_RCP45, v$pre), template, v$name)
})
pres_stack <- terra::rast(pres_layers)

message("\nHomogeneizando capas del FUTURO RCP4.5 (2041-2070)...")
fut_layers <- lapply(VAR_PAIRS, function(v) {
  message("  - ", v$name, "  <- ", v$fut)
  align_to_template(file.path(DIR_RCP45, v$fut), template, v$name)
})
fut_stack <- terra::rast(fut_layers)

# -----------------------------------------------------------------------------
# 5. Recorte al área de estudio + máscara de NAs común
# -----------------------------------------------------------------------------
# Si en una celda CUALQUIER banda (presente o futuro) es NA, esa celda debe
# ser NA en TODAS las bandas. Esto evita descuadres en Mahalanobis.

message("\nAplicando máscara común (área de estudio + NAs compartidos)...")

pres_stack <- terra::crop(pres_stack, study_vect) |> terra::mask(study_vect)
fut_stack  <- terra::crop(fut_stack,  study_vect) |> terra::mask(study_vect)

# Asegurar que el futuro queda EXACTAMENTE en la misma malla que el presente
# tras crop (a veces crop puede dar 1 fila/col de diferencia por bordes).
fut_stack <- terra::resample(fut_stack, pres_stack, method = RESAMPLE_METHOD)

# Máscara de NAs compartida
valid <- !is.na(sum(pres_stack)) & !is.na(sum(fut_stack))
pres_stack <- terra::mask(pres_stack, valid, maskvalue = FALSE)
fut_stack  <- terra::mask(fut_stack,  valid, maskvalue = FALSE)

# -----------------------------------------------------------------------------
# 6. Verificación final
# -----------------------------------------------------------------------------

ok_geom <- terra::compareGeom(
  pres_stack, fut_stack,
  lyrs = FALSE, crs = TRUE, ext = TRUE, rowcol = TRUE, res = TRUE,
  stopOnError = FALSE
)
if (!isTRUE(ok_geom)) {
  stop("Presente y futuro no coinciden en geometría tras la homogeneización.")
}
if (!identical(names(pres_stack), names(fut_stack))) {
  stop("Los nombres de banda no coinciden entre presente y futuro.")
}

message("\n--- VERIFICACIÓN OK ---")
message("CRS:       ", terra::crs(pres_stack, proj = TRUE))
message("Extent:    ", paste(round(as.vector(terra::ext(pres_stack)), 1), collapse = ", "))
message("Resolución: ", paste(round(terra::res(pres_stack), 1), collapse = " x "))
message("Dimensión: ", paste(dim(pres_stack), collapse = " x "))
message("Bandas:    ", paste(names(pres_stack), collapse = ", "))

# -----------------------------------------------------------------------------
# 7. Guardar
# -----------------------------------------------------------------------------

out_pres <- file.path(DIR_OUT_CLIMATE, "present_climate_VIF.tif")
out_fut  <- file.path(DIR_OUT_CLIMATE, "future_climate_ensemble_MEAN.tif")

terra::writeRaster(pres_stack, out_pres, overwrite = TRUE)
terra::writeRaster(fut_stack,  out_fut,  overwrite = TRUE)

message("\nGuardados:")
message("  · ", out_pres)
message("  · ", out_fut)
message("\nListo. Ahora puedes ejecutar 02_ejecutar_climarep.R.")