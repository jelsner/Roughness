# Run from the repository root. Files are cached; delete a cache to refresh it.
options(timeout = 600)
dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)
dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
fetch <- function(url, path) {
  if (!file.exists(path)) {
    tmp <- paste0(path, ".part")
    download.file(url, tmp, mode = "wb", quiet = TRUE)
    if (!file.rename(tmp, path)) stop("Cannot save ", path)
  }
  path
}
base <- "https://www.ncei.noaa.gov/pub/data/swdi/stormevents/csvfiles/"
index <- paste(readLines(base, warn = FALSE), collapse = "\n")
files <- unique(regmatches(index, gregexpr(
  "StormEvents_details-ftp_v1\\.0_d[0-9]{4}_c[0-9]{8}\\.csv\\.gz", index))[[1]])
years <- 1955:2025
manifest <- list()
reports <- list()
columns <- c("EVENT_ID", "EPISODE_ID", "YEAR", "BEGIN_YEARMONTH", "EVENT_TYPE",
             "STATE", "CZ_NAME", "TOR_F_SCALE", "TOR_WIDTH", "TOR_LENGTH",
             "BEGIN_LAT", "BEGIN_LON", "END_LAT", "END_LON",
             "TOR_OTHER_CZ_STATE", "TOR_OTHER_CZ_FIPS")
for (year in years) {
  candidates <- sort(files[grepl(paste0("_d", year, "_"), files)])
  if (!length(candidates)) stop("No NCEI data for ", year)
  name <- tail(candidates, 1)
  url <- paste0(base, name)
  message("NCEI ", year)
  path <- fetch(url, file.path("data/raw", name))
  x <- readr::read_csv(path, col_types = readr::cols(.default = readr::col_character()),
                       col_select = dplyr::any_of(columns), show_col_types = FALSE,
                       progress = FALSE)
  if (!all(columns %in% names(x))) stop("Unexpected NCEI schema for ", year)
  if (max(as.integer(x$BEGIN_YEARMONTH), na.rm = TRUE) < year * 100 + 12L) {
    stop("NCEI file does not reach December for ", year)
  }
  reports[[as.character(year)]] <- x[x$EVENT_TYPE == "Tornado", ]
  manifest[[as.character(year)]] <- data.frame(
    year = year, url = url, md5 = unname(tools::md5sum(path)),
    tornado_records = nrow(reports[[as.character(year)]]),
    retrieved_utc = format(file.info(path)$mtime, tz = "UTC", usetz = TRUE))
}
x <- dplyr::bind_rows(reports)
stopifnot(!anyDuplicated(x$EVENT_ID), all(years %in% as.integer(x$YEAR)))
readr::write_csv(x, "data/processed/ncei_tornadoes_1955_2025.csv.gz")
readr::write_csv(dplyr::bind_rows(manifest), "data/source_manifest.csv")
# Original DEM: 15-arc-second elevation; roughness depends on this resolution.
fetch("https://www.viewfinderpanoramas.org/DEM/TIF15/15-H.zip", "data/raw/15-H.zip")
unzip("data/raw/15-H.zip", exdir = "data/raw/elevation")
# Retain the original population covariate for comparability, explicitly dated 2000.
if (!file.exists("data/raw/usadens/usads00g/w001001.adf")) {
  unzip("usadens.zip", files = unzip("usadens.zip", list = TRUE)$Name[
    grepl("^usadens/", unzip("usadens.zip", list = TRUE)$Name)], exdir = "data/raw")
}
message("Data prepared through December 2025.")

# Whole-track sensitivity using SPC, kept separate from NCEI segment counts.
spc_url <- "https://www.spc.noaa.gov/wcm/data/1950-2024_actual_tornadoes.csv"
spc_path <- fetch(spc_url, "data/raw/spc_actual_1950_2024.csv")
s <- readr::read_csv(spc_path, show_col_types = FALSE)
stopifnot(max(s$yr) == 2024, all(s$sg == 1))
s <- s[s$yr >= 1955, ]
s <- s[!duplicated(s), ] # Remove exact duplicate rows only; om is not unique within year.
spc <- data.frame(EVENT_ID = paste0("spc-row-", seq_len(nrow(s))), YEAR = s$yr,
                  TOR_WIDTH = s$wid, TOR_F_SCALE = ifelse(s$mag >= 0, paste0("F", s$mag), "FU"),
                  BEGIN_LAT = s$slat, BEGIN_LON = s$slon, END_LAT = s$elat, END_LON = s$elon)
stopifnot(!anyDuplicated(spc$EVENT_ID))
readr::write_csv(spc, "data/processed/spc_tracks_1955_2024.csv.gz")
readr::write_csv(data.frame(source = c("SPC tracks", "Elevation", "GPW v3 population 2000"),
  url = c(spc_url, "https://www.viewfinderpanoramas.org/DEM/TIF15/15-H.zip",
          "Local archive usadens.zip from original repository"),
  md5 = unname(tools::md5sum(c(spc_path, "data/raw/15-H.zip", "usadens.zip")))),
  "data/auxiliary_manifest.csv")
