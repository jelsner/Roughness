# Roughness

Updated R Markdown analysis of terrain roughness and tornado reports in the
central Great Plains, with NOAA NCEI data through **December 2025**. This repository
originally accompanied *Tornadoes are more common over smooth terrain*, published
in **PLoS One**. The 2015 analysis is preserved in
[`archive/TerrainRoughness-2015.Rmd`](archive/TerrainRoughness-2015.Rmd).

The default domain remains **102–95°W, 36–42°N**, on a **0.25° grid**. Both the
extent and period can be changed using the Rmd parameters. Larger extents require
DEM and population coverage; the supplied DEM covers the original region.

## Run

Use R 4.5 or newer and Pandoc (included with RStudio). On Linux, `sf` and `terra`
may require system GDAL, GEOS, PROJ, and UDUNITS development libraries.

```sh
Rscript scripts/setup.R
Rscript scripts/download_data.R
Rscript tests/test-analysis.R
Rscript scripts/render.R
```

Open `outputs/TerrainRoughness.html`. The report also writes cell data, effect
estimates, fitted models, annual quality counts, and session information to
`outputs/`. Download preparation requires internet access and about 1 GB of
local storage. Rendering and tests use local data and require no map-service key.

`renv.lock` records the tested R package versions. To reproduce these versions
in an isolated project library, install `renv` and run `renv::restore()` followed by `renv::load()` from the
repository root, then `source("scripts/render.R")` in that same R session. `scripts/setup.R` instead installs missing packages into the
current library; it does not force locked versions or update existing packages.

For example, render only the modern observing period or exclude weak tornadoes:

```r
rmarkdown::render("TerrainRoughness.Rmd", output_dir = "outputs",
                  params = list(start_year = 1996, min_rating = 1))
```

## What changed

- `sf` and `terra` replace retired `rgdal`, `rgeos`, and `maptools` workflows.
- Paths are buffered in metres in EPSG:5070; cell areas are explicitly calculated.
- DEM roughness is computed in the native 3 × 3 neighborhood before cell averaging.
- NCEI annual records provide a consistent source through 2025, with versioned
  extracts and source checksums. Missing coordinates are reported explicitly.
- Negative-binomial models include area × time exposure, centered covariates,
  an elevation–roughness interaction with both main effects, and a spatial smooth.
- A 1996–2025 sensitivity fit and a separate SPC whole-track fit through 2024
  help assess historical data quality and changes in the response definition.
- An optional INLA negative-binomial BYM2 model retains a Bayesian spatial option.

## Interpret the response carefully

The main analysis counts **NCEI tornado report segments intersecting each cell**.
These records can split a tornado across county or forecast-office boundaries.
They are not unique tornado counts, tornado genesis counts, or independent
observations. A segment intersecting several cells is counted in each. Event IDs
are checked for duplicates, but different segments are not guessed to be the
same tornado. Invalid start coordinates are excluded; missing endpoints use the
start point; zero/unknown widths retain a line or point. The early 1990s have
substantial missing-coordinate problems, so the report includes annual quality
counts and a modern-period sensitivity fit.

SPC's `actual_tornadoes` archive currently ends in 2024. Its whole-track records
are analyzed separately, not concatenated with NCEI's 2025 segments. SPC's `om`
field is not always unique within year; the prepared extract uses stable row IDs
for the pinned file after removing exact duplicate rows. The source and period
changes mean that this modernization is not an exact reproduction of the 2015
model. The original `tornado.zip` is retained for historical reference.

Population remains **GPW v3 year 2000 density**, as in the original analysis.
It is a static reporting proxy, not a contemporary population measure. Terrain
roughness depends on DEM resolution. The fitted relationships are associations
in reports; they do not establish a causal effect on tornado formation. Spatial
block validation and stronger controls for reporting and meteorological
confounding are needed for predictive or causal applications.

## Optional INLA

INLA is not needed for the default report. Install from its official repository:

```r
install.packages("INLA", repos = c(
  CRAN = "https://cloud.r-project.org",
  INLA = "https://inla.r-inla-download.org/R/stable"))
rmarkdown::render("TerrainRoughness.Rmd", output_dir = "outputs",
                  params = list(run_inla = TRUE))
```

The BYM2 model uses queen adjacency and explicit PC priors. The default verified
workflow is the `mgcv` spatial negative-binomial fit; INLA is optional and is not
included in the tested dependency lockfile or CI checks.

## Data provenance

- [NOAA NCEI annual Storm Events files](https://www.ncei.noaa.gov/pub/data/swdi/stormevents/csvfiles/)
  and [field documentation](https://www.ncei.noaa.gov/pub/data/swdi/stormevents/csvfiles/Storm-Data-Bulk-csv-Format.pdf).
- [NOAA SPC severe-weather archive](https://www.spc.noaa.gov/wcm/).
- [Viewfinder Panoramas 15-arc-second elevation tile 15-H](https://www.viewfinderpanoramas.org/DEM/TIF15/15-H.zip).
- Original GPW v3 population density archive, `usadens.zip`, retained from this repository.

`data/source_manifest.csv` records the NCEI annual source URLs, file checksums,
retrieval timestamps and tornado row counts. `data/auxiliary_manifest.csv` records
SPC, elevation and population checksums. Large downloaded archives and rendered
outputs are ignored by Git. The compressed prepared tornado extracts are tracked.
To refresh a source, remove its cached raw file and rerun preparation; the script
selects the newest annual revision listed by NOAA. Revisions may change results.

## Aerodynamic roughness and genesis: a separate analysis

[`TornadoGenesis.Rmd`](TornadoGenesis.Rmd) uses **2000–2024 SPC whole tracks** with
starts in the original domain, **prior-year Annual NLCD C1V1 land cover**, paired
start/end conditional logistic regression, and a matched local-background genesis
model. Ten reference points are sampled uniformly by area 2–10 km from each start,
inside the original domain. Real ends outside the domain are retained. Invalid
ends are never imputed; identical endpoints are excluded only from the paired fit.

```sh
Rscript scripts/setup.R
Rscript scripts/render_genesis.R
```

The small prepared site tables are versioned, so the default report renders
without downloading land-cover rasters. To regenerate the real inputs from source:

```sh
Rscript scripts/prepare_genesis.R
Rscript -e 'testthat::test_dir("tests", stop_on_failure = TRUE)'
Rscript scripts/render_genesis.R
```

Preparation caches 25 native-resolution regional land-cover crops (roughly 1 GB),
plus intermediate neighborhoods. It can take several minutes and requires network
access. Completed years/radii are cached. The source is discovered using a frozen
USGS STAC response bundled in `data/metadata/nlcd_c1v1_1999_stac.json`; the annual
filename template preserves the C1V1 version and changes only the year. The
preparation script validates native 30 m resolution and records crop checksums.

Open `outputs/genesis/TornadoGenesis.html`. Outputs include main and sensitivity
effect estimates, paired differences, site covariates, models, and session details.
Rmd parameters select the prepared 500, 1,000, or 2,000 m neighborhood radius,
coverage threshold, bootstrap replicates, and bootstrap seed. The primary radius
is 1,000 m. Sampling settings and coordinates are recorded in
`data/processed/genesis/design.json` and `sites.csv.gz`.

The aerodynamic measure is an isotropic geometric-mean **land-cover roughness
index**, based on EPA AERSURFACE Table 6-6 seasonal lookup values. Fixed calendar
seasons, non-airport assumptions, and non-arid shrub values are approximations;
this is not a full AERSURFACE run or an estimate of effective tornado drag.
Elevation variability is adjusted separately. Population remains a coarse,
static year-2000 reporting proxy. Standard errors are clustered by calendar day.

Endpoint asymmetry does not identify a genesis effect by itself, and local
reference points are available landscape, not confirmed storm opportunities or
non-tornadic controls. The report includes scale, endpoint-separation, boundary,
seasonal-lookup and low-water sensitivities, and identifies remaining reporting,
coordinate, meteorological, and land-cover uncertainty.
