# Geometry uses EPSG:5070 (metres); display and the original grid use EPSG:4326.
make_grid <- function(bbox, resolution = 0.25) {
  stopifnot(length(bbox) == 4L, all(is.finite(bbox)), resolution > 0,
            bbox[1] < bbox[2], bbox[3] < bbox[4])
  n <- c(diff(bbox[1:2]), diff(bbox[3:4])) / resolution
  if (any(abs(n - round(n)) > 1e-8)) stop("Extent must divide into whole cells")
  r <- terra::rast(xmin = bbox[1], xmax = bbox[2], ymin = bbox[3], ymax = bbox[4],
                   resolution = resolution, crs = "EPSG:4326")
  terra::values(r) <- seq_len(terra::ncell(r))
  names(r) <- "cell_id"
  grid <- sf::st_as_sf(terra::as.polygons(r, aggregate = FALSE))
  grid <- grid[order(grid$cell_id), ]
  grid$area_km2 <- as.numeric(sf::st_area(sf::st_transform(grid, 5070))) / 1e6
  list(raster = r, cells = grid)
}

read_reports <- function(path, start_year, end_year, min_rating = -1) {
  x <- readr::read_csv(path, show_col_types = FALSE, progress = FALSE,
                      col_types = readr::cols(.default = readr::col_character()))
  numeric_cols <- c("YEAR", "TOR_WIDTH", "BEGIN_LAT", "BEGIN_LON", "END_LAT", "END_LON")
  x[numeric_cols] <- lapply(x[numeric_cols], as.numeric)
  x$rating <- suppressWarnings(as.integer(sub("^EF|^F", "", x$TOR_F_SCALE)))
  x <- x[x$YEAR >= start_year & x$YEAR <= end_year, ]
  if (!all(start_year:end_year %in% x$YEAR)) stop("Missing years in tornado input")
  if (min_rating >= 0) x <- x[!is.na(x$rating) & x$rating >= min_rating, ]
  if (anyDuplicated(x$EVENT_ID)) stop("Duplicate NCEI event IDs")
  valid_start <- is.finite(x$BEGIN_LAT) & is.finite(x$BEGIN_LON) &
    abs(x$BEGIN_LAT) <= 90 & abs(x$BEGIN_LON) <= 180 &
    x$BEGIN_LAT != 0 & x$BEGIN_LON != 0
  excluded <- sum(!valid_start)
  x <- x[valid_start, ]
  valid_end <- is.finite(x$END_LAT) & is.finite(x$END_LON) &
    abs(x$END_LAT) <= 90 & abs(x$END_LON) <= 180 &
    x$END_LAT != 0 & x$END_LON != 0
  x$end_imputed <- !valid_end
  x$END_LAT[!valid_end] <- x$BEGIN_LAT[!valid_end]
  x$END_LON[!valid_end] <- x$BEGIN_LON[!valid_end]
  x$width_missing <- !is.finite(x$TOR_WIDTH) | x$TOR_WIDTH <= 0
  x$width_m <- ifelse(x$width_missing, 0, x$TOR_WIDTH * 0.9144)
  geometry <- lapply(seq_len(nrow(x)), function(i) {
    a <- c(x$BEGIN_LON[i], x$BEGIN_LAT[i])
    b <- c(x$END_LON[i], x$END_LAT[i])
    if (all(a == b)) sf::st_point(a) else sf::st_linestring(rbind(a, b))
  })
  list(tracks = sf::st_as_sf(x, geometry = sf::st_sfc(geometry, crs = 4326)),
       excluded_coordinates = excluded)
}

count_reports <- function(tracks, cells) {
  tracks <- sf::st_transform(tracks, 5070)
  # Zero/unknown widths retain the line or point, rather than disappearing in buffer(0).
  positive <- tracks$width_m > 0
  geom <- sf::st_geometry(tracks)
  geom[positive] <- sf::st_buffer(geom[positive], dist = tracks$width_m[positive] / 2)
  tracks <- sf::st_set_geometry(tracks, geom)
  hits <- sf::st_intersects(sf::st_transform(cells, 5070), tracks)
  list(counts = lengths(hits), paths = tracks,
       regional_ids = sort(unique(unlist(hits))))
}

terrain_covariates <- function(template, dem_path, population_path) {
  dem <- terra::rast(dem_path)
  if (!terra::is.lonlat(dem)) stop("This workflow expects a geographic DEM")
  # Halo preserves the 3 x 3 window at the study boundary. Compute before averaging.
  halo <- terra::ext(template) + 2 * max(terra::res(dem))
  dem <- terra::crop(dem, halo, snap = "out")
  rough <- terra::terrain(dem, v = "roughness", neighbors = 8)
  population <- terra::rast(population_path)
  # Average native pixels into analysis cells, not an arbitrary aggregate factor.
  elevation <- terra::resample(dem, template, method = "average")
  roughness <- terra::resample(rough, template, method = "average")
  density <- terra::project(population, template, method = "average")
  list(elevation_m = as.numeric(terra::values(elevation)),
       roughness_m = as.numeric(terra::values(roughness)),
       population_2000 = as.numeric(terra::values(density)),
       dem_resolution_arcsec = terra::res(dem) * 3600)
}

model_data <- function(cells, counts, covariates, years) {
  x <- sf::st_drop_geometry(cells)
  x$count <- counts
  for (name in c("elevation_m", "roughness_m", "population_2000")) {
    x[[name]] <- covariates[[name]][x$cell_id]
  }
  if (any(!is.finite(as.matrix(x))) || any(x$population_2000 < 0)) {
    stop("Missing/invalid covariates: check raster coverage; cells are not silently dropped")
  }
  xy <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(sf::st_transform(cells, 5070)))) / 1000
  x$x_km <- xy[, 1]
  x$y_km <- xy[, 2]
  x$log2_population <- log2(x$population_2000 + 1)
  x$roughness_10m <- (x$roughness_m - mean(x$roughness_m)) / 10
  x$elevation_100m <- (x$elevation_m - mean(x$elevation_m)) / 100
  x$exposure <- x$area_km2 * years / 1000
  x
}

fit_models <- function(x, spatial_k = 200L) {
  if (nrow(x) < 20L) stop("Use at least 20 analysis cells for the spatial smooth")
  spatial_k <- min(as.integer(spatial_k), nrow(x) - 10L)
  if (spatial_k < 10L) stop("spatial_k must be at least 10")
  # Full hierarchy makes the roughness coefficient interpretable at mean elevation.
  formula <- count ~ log2_population + roughness_10m * elevation_100m + offset(log(exposure))
  nonspatial <- MASS::glm.nb(formula, data = x)
  spatial <- mgcv::gam(count ~ log2_population + roughness_10m * elevation_100m +
                         s(x_km, y_km, k = spatial_k) + offset(log(exposure)),
                       family = mgcv::nb(), method = "REML", data = x)
  list(nonspatial = nonspatial, spatial = spatial)
}

fit_bym2 <- function(x, cells) {
  if (!requireNamespace("INLA", quietly = TRUE)) stop("Install INLA; see README.md")
  nb <- spdep::poly2nb(cells, queen = TRUE)
  if (any(spdep::card(nb) == 0)) stop("Isolated grid cells in adjacency graph")
  graph <- tempfile(fileext = ".adj")
  on.exit(unlink(graph))
  spdep::nb2INLA(graph, nb)
  INLA::inla(count ~ log2_population + roughness_10m * elevation_100m +
               f(cell_id, model = "bym2", graph = graph, scale.model = TRUE,
                 hyper = list(prec = list(prior = "pc.prec", param = c(1, 0.01)),
                              phi = list(prior = "pc", param = c(0.5, 2 / 3)))),
             family = "nbinomial", E = x$exposure, data = x,
             control.predictor = list(compute = TRUE),
             control.compute = list(waic = TRUE, cpo = TRUE, dic = TRUE))
}

roughness_effect <- function(model) {
  b <- stats::coef(model)[["roughness_10m"]]
  se <- sqrt(stats::vcov(model)["roughness_10m", "roughness_10m"])
  # Monotone transformation of coefficient limits, not relabeling density coordinates.
  data.frame(contrast = "10 m higher roughness at mean elevation",
             rate_ratio = exp(b), lower_95 = exp(b - 1.96 * se), upper_95 = exp(b + 1.96 * se))
}
