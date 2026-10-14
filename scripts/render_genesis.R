args <- commandArgs(trailingOnly=TRUE)
group <- if(length(args)) match.arg(args[[1]],c("all","weak","strong")) else "all"
out <- if(group=="all") "outputs/genesis" else paste0("outputs/genesis-",group)
dir.create(out,recursive=TRUE,showWarnings=FALSE)
rmarkdown::render("TornadoGenesis.Rmd",output_dir=out,
                  params=list(rating_group=group),envir=new.env())
