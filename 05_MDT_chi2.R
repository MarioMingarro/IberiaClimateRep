library(terra)
library(dplyr)
library(tidyr)
library(ggplot2)

# 1. Cargar rasters
r_n2000 <- rast("C:/A_TRABAJO/IberiaClimateRep_RES/SSP370/04_metrics/N2000CRS_present.tif")
r_er    <- rast("C:/A_TRABAJO/IberiaClimateRep_RES/SSP370/04_metrics/EUCRS_present.tif")
r_dem   <- rast("C:/A_TRABAJO/IberiaClimateRep_RES/DATA/MDT_ES_100M_land.tif")

r_dem    <- project(r_dem, r_n2000, method = "near")
r_n2000_res <- resample(r_n2000, r_dem, method = "near")
r_er_res    <- resample(r_er    , r_dem, method = "near")

r_stack <- c(r_n2000_res, r_er_res, r_dem)
names(r_stack) <- c("N2000", "ER", "Elevation")

df <- as.data.frame(r_stack, xy = FALSE, na.rm = TRUE)

bin_width <- 20

df_sum <- df %>%
  mutate(Elevation_Bin = floor(Elevation / bin_width) * bin_width) %>%
  filter(Elevation_Bin >= 0) %>% # Descartar batimetría o errores negativos
  group_by(Elevation_Bin) %>%
  summarise(
    Geo_Area  = n(),                          # Número de celdas disponibles
    Clim_Area = sum(ER, na.rm = TRUE),        # Espacio climático
    Rep_Area  = sum(N2000, na.rm = TRUE)      # Red Natura 2000
  ) %>%
  ungroup()

prop_n2000_clim <- sum(df_sum$Rep_Area) / sum(df_sum$Clim_Area)

df_plot <- df_sum %>%
  mutate(
    Expected_N2000 = Clim_Area * prop_n2000_clim,
    Pearson_Res = ifelse(Expected_N2000 < 1, 0, 
                         (Rep_Area - Expected_N2000) / sqrt(Expected_N2000)),
    Geo_Scaled  = (Geo_Area / max(Geo_Area, na.rm = TRUE)) * 100,
    Clim_Scaled = (Clim_Area / max(Clim_Area, na.rm = TRUE)) * 100,
    Rep_Scaled  = (Rep_Area / max(Rep_Area, na.rm = TRUE)) * 100
  )

max_res <- max(abs(df_plot$Pearson_Res), na.rm = TRUE)
escala_residuos <- ifelse(max_res == 0, 1, 40 / max_res) 

df_plot <- df_plot %>%
  mutate(Pearson_Res_Y = Pearson_Res * escala_residuos)


df_lines <- df_plot %>%
  select(Elevation_Bin, 
         `Hipsometría` = Geo_Scaled, 
         `ECR` = Clim_Scaled, 
         `ECN2000` = Rep_Scaled) %>%
  pivot_longer(-Elevation_Bin, names_to = "Metrics", values_to = "Scaled_Value")

ggplot() +
  geom_col(data = df_plot, 
           aes(x = Elevation_Bin, y = Pearson_Res_Y, fill = Pearson_Res), 
           width = bin_width, alpha = 0.8) +
  geom_line(data = df_lines, 
            aes(x = Elevation_Bin, y = Scaled_Value, color = Metrics), 
            linewidth = 0.7, alpha = 0.5) +
  geom_point(data = df_lines, 
             aes(x = Elevation_Bin, y = Scaled_Value, color = Metrics), 
             size = 0.8, alpha = 0.7) +
  
  # ESCALAS Y ESTÉTICA
  scale_fill_gradient2(
    low = "firebrick", mid = "white", high = "forestgreen", 
    midpoint = 0, name = expression(paste("Pearson residuals (", chi^2, ")")),
    limits = c(-max_res, max_res)
  ) +
  scale_color_manual(
    values = c("Hipsometría" = "gray70", 
               "ECR" = "coral", 
               "ECN2000" = "black"),
    name = ""
  ) +
  scale_y_continuous(
    name = "Scaled area value (%)",
    limits = c(min(df_plot$Pearson_Res_Y, na.rm = TRUE) * 1.1, 100),
    breaks = seq(0, 100, by = 20),
    # Eje secundario honesto para leer la magnitud real de los residuos
    sec.axis = sec_axis(~ . / escala_residuos, name = "Pearson Residuals")
  ) +
  scale_x_continuous(
    name = "Elevation (m)",
    breaks = seq(0, max(df_plot$Elevation_Bin, na.rm = TRUE), by = 500)
  ) +
  labs(title = "") +
  theme_minimal() +
  theme(
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_line(color = "gray90"),
    panel.grid.major.y = element_line(color = "gray95", linetype = "dashed"),
    plot.title = element_text(hjust = 0.5, face = "bold"),
    legend.position = "bottom",
    legend.box = "horizontal",
    legend.title = element_text(vjust = 0.8),
    axis.title.y.right = element_text(color = "black") # Destaca el eje secundario
  )
