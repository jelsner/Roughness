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


# Reference annulus rerun: 5–30 km

On October 14, 2026, the reference inner radius was increased to 5 km and the
outer radius to 30 km. Ten points per start, the original study domain,
2000–2024 tracks, prior-year cover, and the exposure-neighborhood radii were
retained. All 36,050 new reference points satisfy the exact longitude/latitude
bounds and the 5–30 km projected-distance limits. All 126,756 site/radius records
have complete land-cover coverage, and their class fractions sum to one. All
static covariates are finite. The report rendered without warnings.

The earlier sampler projected only four rectangle corners, admitting 51 of its
36,050 reference points slightly north of 42°N. The new sampler checks exact
geographic bounds; the domain polygon is densified for projected boundary-distance
calculations. The comparison therefore includes both the annulus change and this
correction. A northern-edge regression test was added: 37 assertions now pass.
Preparation now checks crop coverage and prevents rendering incomplete data.

| Adjusted local-background model | Odds ratio | 95% interval |
| --- | ---: | ---: |
| Earlier 2–10 km (original boundary implementation) | 0.980 | 0.910–1.055 |
| Current 5–30 km (exact geographic bounds) | 0.977 | 0.907–1.052 |

The paired endpoint estimates are numerically unchanged (verified to 1e-10).
The developed-cover-adjusted genesis sensitivity now gives 0.932 (0.866–1.002),
and the untruncated-annulus sensitivity gives 1.012 (0.923–1.111) using 3,009 sets.
The earlier estimates are preserved in a versioned baseline CSV and compared in
the report. These results remain inconclusive under the primary specification.

# Weak-tornado rerun and rating interaction

On October 14, 2026, the full analysis was repeated for archived maximum F/EF
ratings 0–1. The original domain, 2000–2024 period, 5–30 km references, prior-year
land cover, and all adjustment variables were retained. The cohort contains
3,054 starts (2,243 rated 0 and 811 rated 1), 2,116 distinct endpoint pairs, and
30,540 background locations. There are 45 invalid ends and 893 identical valid
endpoints. All retained coordinates and covariates match their all-rating source
rows to 1e-10. Neither references nor environmental exposures were resampled.

| Adjusted F/EF0–1 comparison | Odds ratio | 95% interval |
| --- | ---: | ---: |
| Local background | 0.994 | 0.918–1.077 |
| Paired endpoints | 0.864 | 0.730–1.022 |

The direct comparison uses a pooled conditional logistic model with separate
roughness and nuisance slopes for F/EF0–1 and F/EF2+, clustered jointly by date.
Its stronger group contains 310 starts and 306 distinct pairs; 241 unknown-rated
tracks are excluded. Each reference or endpoint inherits its own track's rating.
The group intercept is absorbed by track strata. The local-background F/EF2+
roughness odds ratio is 0.948 (0.769–1.170). The ratio of stronger to weak odds
ratios is 0.954 (0.766–1.188; two-sided p=0.673). The endpoint interaction ratio
is 1.101 (0.741–1.637; p=0.634). Neither supplies clear evidence of the proposed
rating difference. Final damage rating is not intensity at genesis; conditioning
on it may introduce selection bias.

The weak report reruns the calendar-day bootstrap and all sensitivity models.
It omits the earlier all-rating annulus baseline as an inappropriate comparison
for this selected cohort. Main estimates, sensitivities, membership and rating
audits, interaction estimates, models, and analysis parameters are saved under
`outputs/genesis-weak/`. The all-rating report was also rerendered; its four main
effects are unchanged to 1e-10. Tests now pass 49 assertions without warnings,
including recovery of simulated rating differences, agreement of pooled group
slopes with separate adjusted models, and exclusion of unknown ratings.
