# Run once. Restart R before using Earth Engine if Python was already initialized.
pkgs <- c('sf','terra','dplyr','tidyr','readr','ggplot2','scales','jsonlite','png','reticulate','rgee')
missing <- pkgs[!vapply(pkgs,function(p) length(find.package(p,quiet=TRUE))>0,logical(1))]
if(length(missing)) install.packages(missing,repos='https://cloud.r-project.org')
