# =============================================================================
# ClimaRep - Paso 2: Ejecución de ClimaRep en paralelo
# =============================================================================
# 3.1  mh_rep()    sobre cada AP         → rásteres de representatividad (→ N2000CRS)
# 3.2  mh_rep()    sobre cuadrícula EUCRS → rásteres de referencia       (→ EUCRS)
# 3.3  mh_rep_ch() sobre cada AP         → rásteres de cambio (Stable/Lost/Novel)
#
# Los tres bloques son independientes y pueden ejecutarse en cualquier orden.
# El procesamiento paralelo se gestiona con doParallel en cada bloque.

source("0_configuracion.R")

library(terra)
library(sf)
library(dplyr)
library(ClimaRep)
library(foreach)
library(doParallel)


# Filtrado polígonos de APs----

message("Filtrando áreas protegidas")
dir.create(DIR_OUT_APS, recursive = TRUE, showWarnings = FALSE)
study_area      <- read_sf(PATH_STUDY_AREA) |> st_make_valid() |> st_transform("EPSG:3035")
protected_areas <- read_sf(PATH_PROTECTED_AREAS) |>
  st_make_valid() |>
  st_transform("EPSG:3035") |>
  st_intersection(study_area) |>
  mutate(
    Area_m2     = as.numeric(st_area(geometry)),
    Prmtr_m = as.numeric(st_perimeter(geometry)),
    IPQ         = (4 * pi * Area_m2) / (Prmtr_m^2)
  ) |>
  filter(Area_m2 > MIN_AREA_M2, IPQ > MIN_IPQ) |>
  select(all_of(c(COL_AP_ID, COL_AP_NAME)), Area_m2, Prmtr_m, IPQ)

protected_areas <- st_transform("EPSG:4326")
st_write(
  protected_areas,
  file.path(DIR_OUT_APS, "protected_areas_filtered.shp"),
  append = FALSE
)

message("APs retenidas: ", nrow(protected_areas))
#protected_areas <- st_read(file.path(DIR_OUT_APS, "protected_areas_filtered.shp"))


# Rutas a los archivos preparados en el Paso 1
present_clim_path <- file.path(DIR_OUT_CLIMATE, "present_climate_VIF.tif")
future_clim_path  <- file.path(DIR_OUT_CLIMATE, "future_climate_ensemble_MEAN.tif")

# Cargar datos espaciales
present_clim    <- terra::rast(present_clim_path)
study_area      <- read_sf(PATH_STUDY_AREA) |> st_make_valid() |> st_transform(CHELSA_TARGET_CRS)
protected_areas <- read_sf(PATH_PROTECTED_AREAS)|> st_make_valid() |> st_transform(CHELSA_TARGET_CRS)


# 3.1 mh_rep() para todas las APs → N2000CRS----
#
# Para cada AP genera un ráster binario: 1 = celda análoga, 0 = no análoga.
# La agregación de todos estos rásteres (Paso 3) produce N2000CRS.
tictoc::tic()
message("3.1  mh_rep() para cada AP (representatividad presente)")
dir.create(DIR_OUT_APS, recursive = TRUE, showWarnings = FALSE)

cl <- makeCluster(NUM_CORES)
registerDoParallel(cl)
clusterExport(cl,
              c("protected_areas", "study_area",
                "present_clim_path", "DIR_OUT_APS",
                "REP_THRESHOLD", "COL_AP_NAME"),
              envir = environment())

foreach(
  i          = seq_len(nrow(protected_areas)),
  .packages  = c("sf", "terra", "ClimaRep"),
  .combine   = "c",
  .errorhandling = "pass"
) %dopar% {
  clim <- terra::rast(present_clim_path)
  ap   <- protected_areas[i, ]
  ClimaRep::mh_rep(
    polygon           = ap,
    col_name          = COL_AP_ID,
    climate_variables = clim,
    study_area        = study_area,
    th                = REP_THRESHOLD,
    dir_output        = DIR_OUT_APS,
    save_raw          = FALSE
  )
  paste("OK:", ap[[COL_AP_ID]])
}
stopCluster(cl)
message("mh_rep() para APs completado.")
tictoc::toc()

# 2.2 mh_rep() para la cuadrícula de referencia → EUCRS----
#
# EUCRS(c) = nº de celdas de la cuadrícula cuyo espacio climático incluye c.
# Equivale a la redundancia climática de fondo (no debida a la red de APs).
# Se usa una cuadrícula gruesa (≈100 km) para que cada celda tenga suficientes
# píxeles internos y el percentil sea representativo.

message("2.2  Creando cuadrícula y ejecutando mh_rep() para EUCRS")
tictoc::tic()
dir.create(DIR_OUT_GRID, recursive = TRUE, showWarnings = FALSE)

r_ref   <- terra::rast(present_clim_path)[[1]]
r_agg   <- terra::aggregate(r_ref, fact = GRID_AGG_FACTOR, fun = "mean", na.rm = TRUE)
grid_vect <- terra::as.polygons(r_agg, values = FALSE, dissolve = FALSE, na.rm = FALSE)
grid_vect$ID <- seq_len(nrow(grid_vect))

# Recortar al área de estudio para eliminar celdas marinas/fuera del dominio
study_area_clean <- sf::st_make_valid(study_area)
grid_sf <- sf::st_as_sf(grid_vect) |>
  sf::st_make_valid() |>
  sf::st_intersection(study_area_clean) |>
  mutate(
    Area_m2     = as.numeric(st_area(geometry))) |>
  filter(Area_m2 > MIN_AREA_M2) |>
  select(ID)

terra::writeVector(
  terra::vect(grid_sf),
  file.path(DIR_OUT_GRID, "reference_grid.shp"),
  overwrite = TRUE
)
message("Cuadrícula: ", nrow(grid_sf), " celdas.")

cl <- makeCluster(NUM_CORES)
registerDoParallel(cl)
clusterExport(cl,
              c("grid_sf", "study_area",
                "present_clim_path", "DIR_OUT_GRID", "EUCRS_THRESHOLD"),
              envir = environment())

foreach(
  i          = seq_len(nrow(grid_sf)),
  .packages  = c("sf", "terra", "ClimaRep"),
  .combine   = "c",
  .errorhandling = "pass"
) %dopar% {
  clim <- terra::rast(present_clim_path)
  cell <- grid_sf[i, ]
  ClimaRep::mh_rep(
    polygon           = cell,
    col_name          = "ID",
    climate_variables = clim,
    study_area        = study_area,
    th                = EUCRS_THRESHOLD,
    dir_output        = DIR_OUT_GRID,
    save_raw          = FALSE
  )
  paste("OK celda:", cell$ID)
}
stopCluster(cl)
message("mh_rep() para cuadrícula completado.")
tictoc::toc()

# 2.3 mh_rep_ch() para todas las APs → Stable / Lost / Novel----
#
# Para cada AP compara el espacio climático presente con el futuro e identifica:
#   Stable    (1): análogo en presente Y en futuro  → persistencia climática
#   Lost      (2): análogo en presente, NO en futuro → pérdida climática
#   Novel     (3): NO en presente, análogo en futuro → ganancia climática
#   Unsuitable(0): no análogo en ningún escenario

message("2.3  mh_rep_ch() para cada AP (trayectorias de cambio)")
dir.create(DIR_OUT_CHANGE, recursive = TRUE, showWarnings = FALSE)

cl <- makeCluster(NUM_CORES)
registerDoParallel(cl)
clusterExport(cl,
              c("protected_areas", "study_area",
                "present_clim_path", "future_clim_path",
                "DIR_OUT_CHANGE", "REP_THRESHOLD",
                "COL_AP_NAME","COL_AP_ID", "FUTURE_PERIOD"),
              envir = environment())

foreach(
  i          = seq_len(nrow(protected_areas)),
  .packages  = c("sf", "terra", "ClimaRep"),
  .combine   = "c",
  .errorhandling = "pass"
) %dopar% {
  pres <- terra::rast(present_clim_path)
  fut  <- terra::rast(future_clim_path)
  ap   <- protected_areas[892, ]
  ClimaRep::mh_rep_ch(
    polygon                   = ap,
    col_name                  = COL_AP_NAME,
    present_climate_variables = pres,
    future_climate_variables  = fut,
    study_area                = study_area,
    th                        = REP_THRESHOLD,
    model                     = COL_AP_ID,
    year                      = FUTURE_PERIOD,
    dir_output                = DIR_OUT_CHANGE,
    save_raw                  = TRUE
  )
}
stopCluster(cl)
message("mh_rep_ch() completado.")
message("Paso 2 completado.")
