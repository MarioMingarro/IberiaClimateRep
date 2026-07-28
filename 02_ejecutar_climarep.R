# =============================================================================
# ClimaRep - Paso 2: Ejecución de ClimaRep en paralelo
# =============================================================================
# Cambio respecto a la versión anterior:
# ---------------------------------------
# Antes se utilizaba mh_rep() para calcular la representatividad PRESENTE
# (tanto para APs → N2000CRS como para la cuadrícula → EUCRS) y mh_rep_ch()
# se reservaba al cálculo de cambio sobre las APs. Esto generaba una
# INCONGRUENCIA: la representatividad presente derivada de mh_rep() usa una
# matriz de covarianza calculada SOLO con datos presentes, mientras que el
# "presente" implícito en los outputs de mh_rep_ch() (Stable + Lost) usa la
# matriz combinada presente+futuro. Comparar N2000CRS_futuro (derivado de
# mh_rep_ch) con EUCRS_presente (derivado de mh_rep) no era estrictamente
# coherente.
#
# Ahora se usa SIEMPRE mh_rep_ch() — tanto para APs como para la cuadrícula —
# y todas las métricas (presente y futuro, N2000CRS y EUCRS) se derivan de los
# rásteres Stable / Lost / Novel:
#   Representativo en presente = Stable + Lost
#   Representativo en futuro   = Stable + Novel
#
# 2.1  Filtrado de APs por área e IPQ
# 2.2  Construcción de la cuadrícula EUCRS
# 2.3  mh_rep_ch() sobre cada AP        → DIR_OUT_APS_CHANGE/Change/*.tif
# 2.4  mh_rep_ch() sobre cada celda EUCRS → DIR_OUT_GRID_CHANGE/Change/*.tif

source("0_configuracion.R")

library(terra)
library(sf)
library(dplyr)
library(ClimaRep)
library(foreach)
library(doParallel)


# 2.1 Filtrado polígonos de APs ----

message("2.1  Filtrando áreas protegidas")
dir.create(DIR_OUT_APS_CHANGE, recursive = TRUE, showWarnings = FALSE)
study_area      <- read_sf(PATH_STUDY_AREA) |> st_make_valid() |> st_transform("EPSG:3035")
protected_areas <- read_sf(PATH_PROTECTED_AREAS) |>
  st_make_valid() |>
  st_transform("EPSG:3035") |>
  st_intersection(study_area) |>
  mutate(
    Area_m2 = as.numeric(st_area(geometry)),
    Prmtr_m = as.numeric(st_perimeter(geometry)),
    IPQ     = (4 * pi * Area_m2) / (Prmtr_m^2)
  ) |>
  filter(Area_m2 > MIN_AREA_M2, IPQ > MIN_IPQ) |>
  select(all_of(c(COL_AP_ID, COL_AP_NAME)), Area_m2, Prmtr_m, IPQ)

protected_areas <- st_transform(protected_areas, TARGET_CRS)
st_write(
  protected_areas,
  file.path(DIR_OUT_APS_CHANGE, "protected_areas_filtered.shp"),
  append = FALSE
)
message("APs retenidas: ", nrow(protected_areas))

# Rutas a los archivos preparados en el Paso 1
present_clim_path <- file.path(DIR_OUT_CLIMATE, "present_climate_VIF.tif")
future_clim_path  <- file.path(DIR_OUT_CLIMATE, "future_climate_ensemble_MEAN.tif")

# Cargar datos espaciales en CRS objetivo
present_clim    <- terra::rast(present_clim_path)
study_area      <- read_sf(PATH_STUDY_AREA) |> st_make_valid() |> st_transform(TARGET_CRS)
protected_areas <- read_sf(file.path(DIR_OUT_APS_CHANGE, "protected_areas_filtered.shp")) |>
  st_make_valid() |>
  st_transform(TARGET_CRS)


# 2.2 Construcción de la cuadrícula EUCRS ----
#
# La cuadrícula se construye aquí porque la usaremos para mh_rep_ch() (sección 2.4).
# Se mantiene la misma lógica que antes: agregar el ráster de referencia por
# GRID_AGG_FACTOR y descartar celdas demasiado pequeñas tras recortar al área
# de estudio.

message("2.2  Construyendo cuadrícula de referencia para EUCRS")
dir.create(DIR_OUT_GRID_CHANGE, recursive = TRUE, showWarnings = FALSE)

r_ref     <- terra::rast(present_clim_path)[[1]]
r_agg     <- terra::aggregate(r_ref, fact = GRID_AGG_FACTOR, fun = "mean", na.rm = TRUE)
grid_vect <- terra::as.polygons(r_agg, values = FALSE, dissolve = FALSE, na.rm = FALSE)
grid_vect$ID <- seq_len(nrow(grid_vect))

study_area_clean <- study_area |>
  sf::st_make_valid() |>
  sf::st_set_crs(4326)

grid_sf <- sf::st_as_sf(grid_vect) |>
  sf::st_make_valid() |>
  sf::st_intersection(study_area_clean) |>
  mutate(Area_m2 = as.numeric(st_area(geometry))) |>
  filter(Area_m2 > MIN_AREA_M2) |>
  select(ID)

terra::writeVector(
  terra::vect(grid_sf),
  file.path(DIR_OUT_GRID_CHANGE, "reference_grid.shp"),
  overwrite = TRUE
)
message("Cuadrícula: ", nrow(grid_sf), " celdas.")


# 2.3 mh_rep_ch() para todas las APs → Stable / Lost / Novel ----
#
# Para cada AP, mh_rep_ch produce un ráster con códigos:
#   0 = Unsuitable, 1 = Stable, 2 = Lost, 3 = Novel
# A partir de aquí se derivan en el Paso 3:
#   N2000CRS_present = Stable + Lost
#   N2000CRS_future  = Stable + Novel

message("2.3  mh_rep_ch() para cada AP (presente + futuro)")
tictoc::tic()

cl <- makeCluster(NUM_CORES)
registerDoParallel(cl)
clusterExport(cl,
              c("protected_areas", "study_area",
                "present_clim_path", "future_clim_path",
                "DIR_OUT_APS_CHANGE", "REP_THRESHOLD",
                "COL_AP_ID", "FUTURE_PERIOD", "ENSEMBLE_LABEL"),
              envir = environment())

foreach(
  i              = seq_len(nrow(protected_areas)),
  .packages      = c("sf", "terra", "ClimaRep"),
  .combine       = "c",
  .errorhandling = "pass"
) %dopar% {
  pres <- terra::rast(present_clim_path)
  fut  <- terra::rast(future_clim_path)
  ap   <- protected_areas[i, ]
  ClimaRep::mh_rep_ch(
    polygon                   = ap,
    col_name                  = COL_AP_ID,
    present_climate_variables = pres,
    future_climate_variables  = fut,
    study_area                = study_area,
    th                        = REP_THRESHOLD,
    model                     = ENSEMBLE_LABEL,
    year                      = FUTURE_PERIOD,
    dir_output                = DIR_OUT_APS_CHANGE,
    save_raw                  = FALSE
  )
  paste("OK AP:", ap[[COL_AP_ID]])
}
stopCluster(cl)
message("mh_rep_ch() para APs completado.")
tictoc::toc()


# 2.4 mh_rep_ch() para cada celda de la cuadrícula EUCRS ----
#
# Este es el cambio clave: en lugar de mh_rep() (matriz de covarianza solo
# del presente), se usa mh_rep_ch(), que utiliza internamente la matriz
# combinada presente+futuro para el cálculo del futuro. Así los rásteres de
# cuadrícula y los de APs comparten el mismo marco de referencia y las
# métricas derivadas son comparables entre sí.
#
# Notar que se usa EUCRS_THRESHOLD = 1.0 (rango completo dentro de la celda).

message("2.4  mh_rep_ch() para cada celda de la cuadrícula EUCRS")
tictoc::tic()

cl <- makeCluster(NUM_CORES)
registerDoParallel(cl)
clusterExport(cl,
              c("grid_sf", "study_area",
                "present_clim_path", "future_clim_path",
                "DIR_OUT_GRID_CHANGE", "EUCRS_THRESHOLD",
                "FUTURE_PERIOD", "ENSEMBLE_LABEL"),
              envir = environment())

foreach(
  i              = seq_len(nrow(grid_sf)),
  .packages      = c("sf", "terra", "ClimaRep"),
  .combine       = "c",
  .errorhandling = "pass"
) %dopar% {
  pres <- terra::rast(present_clim_path)
  fut  <- terra::rast(future_clim_path)
  cell <- grid_sf[i, ]
  ClimaRep::mh_rep_ch(
    polygon                   = cell,
    col_name                  = "ID",
    present_climate_variables = pres,
    future_climate_variables  = fut,
    study_area                = study_area,
    th                        = EUCRS_THRESHOLD,
    model                     = ENSEMBLE_LABEL,
    year                      = FUTURE_PERIOD,
    dir_output                = DIR_OUT_GRID_CHANGE,
    save_raw                  = FALSE
  )
  paste("OK celda:", cell$ID)
}
stopCluster(cl)
message("mh_rep_ch() para cuadrícula completado.")
tictoc::toc()

message("Paso 2 completado.")
