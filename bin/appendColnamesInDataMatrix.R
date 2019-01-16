#!/usr/bin/env Rscript

## This script takes a matrix appends assayNames with .WithInSampleAbundance
## as the web App looks for .string in the AssayNames for proteomics and median 
## values each value of a matrix 
## This is hack around to get PRIDE data compatible with our process
cl <- commandArgs(trailingOnly = TRUE)

input_object_file <- cl[1]

output_file=gsub(".undecorated.*|tsv","",input_object_file)

## picks middle value from the values of aggregated quartiles
pick_median_value<- function(matrix){
  mat <- apply(matrix, c(1,2), function(x) 
    sapply(strsplit(x, ","), function(x) x[3], simplify=TRUE))
  return(mat)
}

prot.exps <- read.delim(input_object_file, row.names=1, header = TRUE, stringsAsFactors = FALSE, check.names=FALSE)
colnames(prot.exps)[1:ncol(prot.exps)]<- paste0(colnames((prot.exps))[1:ncol(prot.exps)],".WithInSampleAbundance")
prot.exps<-pick_median_value(prot.exps)
prot.exps<- cbind("Gene ID" = rownames(prot.exps), prot.exps)
write.table(prot.exps, file=paste0(output_file,"tsv.undecorated.aggregated"), sep="\t", quote=FALSE, row.names=FALSE)
