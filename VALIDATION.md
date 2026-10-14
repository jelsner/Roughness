# Validation on October 14, 2026

The default report rendered successfully with R 4.5.0 on macOS, using the versions
in `renv.lock`. All 14 test assertions passed with no warnings. `git diff --check`
passed. GitHub Actions is configured for the synthetic geometry and raster tests;
it has not yet run on GitHub. The optional INLA fit was not run.

The default grid has 672 cells. The NCEI fit covers 1955–2025 and includes 8,790
regional event IDs. There are 1,175 national records excluded for invalid start
coordinates; those exclusions cannot be assigned to the study region reliably.

| Spatial NB GAM data | Roughness rate ratio | Approximate 95% interval |
| --- | ---: | ---: |
| NCEI report segments, 1955–2025 | 0.819 | 0.765–0.877 |
| NCEI report segments, 1996–2025 | 0.840 | 0.765–0.923 |
| SPC whole tracks, 1955–2024 | 0.824 | 0.770–0.882 |

Each contrast is a 10 m increase in mean native-resolution roughness at mean
elevation, conditional on population, elevation, and the spatial smooth. The
interaction means the effect varies with elevation. These are associations in
reports, not causal estimates of tornado formation.

The initial 60-function spatial basis flagged insufficient dimension. Increasing
the basis allowance to 120 and 200 changed the full-period roughness rate ratio
from 0.816 to 0.818 and 0.819, respectively. The final default uses 200; its
basis check gives k-index 0.96 and simulation p-value 0.07. This is borderline
and does not establish model adequacy. The exploratory one-sided positive
residual Moran test gives I = -0.036 and permutation p = 0.947. Shared paths
between cells complicate these diagnostics and uncertainty estimates.

The 2000 population covariate remains historical. Missing early-1990s coordinates,
report segmentation, observation changes, straight-line path approximation,
spatial confounding, and approximate confidence intervals remain limitations.
The full report includes quality tables and diagnostic plots. No spatial block
validation or causal identification has been performed.


# Genesis analysis, October 14, 2026

`TornadoGenesis.Rmd` rendered successfully with real 2000–2024 SPC whole-track
records and prior-year 1999–2023 Annual NLCD C1V1 land cover. All 36 combined test
assertions passed without warnings or failures. The prepared data contain 3,605
eligible starts, 36,050 sampled background locations, and 2,597 distinct valid ends.
There are 45 invalid/missing ends and 963 identical valid endpoint pairs; neither
is imputed for the paired analysis. Thirty-three distinct ends lie outside the
original domain and are retained with a land-cover halo. All static covariates
are finite. The default report uses a 1 km roughness neighborhood and 2–10 km
reference annuli, with calendar-day clustered standard errors.

| Default adjusted comparison | Odds ratio per doubling of roughness index | 95% interval |
| --- | ---: | ---: |
| Start versus end, matched by tornado | 0.882 | 0.756–1.028 |
| Start versus local background, matched by tornado | 0.980 | 0.910–1.055 |

Both primary intervals include one. With additional developed-cover adjustment,
the local-background odds ratio is 0.919 (0.855–0.987). The paired estimate is
also sensitive to seasonal lookup and water restrictions. These exploratory
sensitivities change the exposure contrast or the geographic sample; they do not
establish the proposed physical mechanism. Date clustering does not address
persistent spatial dependence across days. Land-cover lookup, coordinate,
reporting, and meteorological opportunity uncertainties remain.

The cached preparation script was rerun successfully without new downloads, and
the report renders offline using the versioned prepared tables. The native annual
rasters are ignored by Git. The report's land-cover manifest records each crop's
checksum and source URL; the input manifest includes the pinned USGS discovery
response and EPA lookup table.
