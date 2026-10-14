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
