library(testthat)
source(if (file.exists("R/analysis.R")) "R/analysis.R" else "../R/analysis.R")
test_that("grid IDs, areas and raster cells agree", {
  g <- make_grid(c(-102, -95, 36, 42))
  expect_equal(nrow(g$cells), 672L)
  expect_equal(g$cells$cell_id, seq_len(672))
  expect_true(all(g$cells$area_km2 > 0))
  expect_error(make_grid(c(-102, -95, 36, 42), 0.3), "whole cells")
})
test_that("line, point, boundary and buffered intersections are counted correctly", {
  g <- make_grid(c(-100, -99, 38, 39), 0.5)
  geometry <- sf::st_sfc(
    sf::st_linestring(rbind(c(-99.9, 38.25), c(-99.1, 38.25))),
    sf::st_point(c(-99.75, 38.75)), sf::st_point(c(-98, 38)), crs = 4326)
  tracks <- sf::st_sf(width_m = c(0, 100, 0), geometry = geometry)
  z <- count_reports(tracks, g$cells)
  expect_equal(z$counts, c(1L, 0L, 1L, 1L))
  expect_equal(z$regional_ids, c(1L, 2L))
})
test_that("native roughness is calculated before target-cell averaging", {
  dem <- terra::rast(xmin=-100.1, xmax=-98.9, ymin=37.9, ymax=39.1,
                     nrows=12, ncols=12, crs="EPSG:4326")
  terra::values(dem) <- rep(seq_len(12), each=12)
  population <- dem
  terra::values(population) <- 4
  d <- tempfile(fileext=".tif"); p <- tempfile(fileext=".tif")
  terra::writeRaster(dem,d); terra::writeRaster(population,p)
  g <- make_grid(c(-100,-99,38,39),0.5)
  v <- terrain_covariates(g$raster,d,p)
  expect_equal(v$roughness_m, rep(2,4), tolerance=1e-6)
  expect_equal(v$population_2000, rep(4,4), tolerance=1e-6)
  x <- model_data(g$cells, rep(1,4), v, 71)
  expect_equal(x$log2_population, rep(log2(5),4))
  expect_equal(x$exposure, g$cells$area_km2*71/1000)
})
test_that("invalid starts are excluded and missing endpoints retain start points", {
  x <- data.frame(EVENT_ID=1:3,YEAR=2025,TOR_WIDTH=c(0,100,NA),
                  BEGIN_LAT=c(38,0,38),BEGIN_LON=c(-100,-100,-100),
                  END_LAT=c(NA,38,38.1),END_LON=c(NA,-100,-100.1),TOR_F_SCALE=c("EF0","EF1","EFU"))
  p <- tempfile(fileext=".csv"); readr::write_csv(x,p)
  r <- read_reports(p,2025,2025)
  expect_equal(r$excluded_coordinates,1L)
  expect_equal(nrow(r$tracks),2L)
  expect_equal(as.character(sf::st_geometry_type(r$tracks)),c("POINT","LINESTRING"))
  expect_equal(nrow(read_reports(p,2025,2025,0)$tracks),1L)
})
