packages <- c("sf", "terra", "ggplot2", "readr", "dplyr", "maps", "MASS", "mgcv",
              "spdep", "knitr", "rmarkdown", "testthat", "renv")
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) install.packages(missing, repos = "https://cloud.r-project.org")
