dir.create("outputs/genesis",recursive=TRUE,showWarnings=FALSE)
rmarkdown::render("TornadoGenesis.Rmd",output_dir="outputs/genesis",envir=new.env())
