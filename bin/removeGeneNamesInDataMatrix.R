#!/usr/bin/env Rscript

cl <- commandArgs(trailingOnly = TRUE)

input_object_file <- cl[1]
output_file=gsub(".undecorated.*|tsv","",input_object_file)

## read the file
prot.exps <- read.delim(input_object_file, header = TRUE, stringsAsFactors = FALSE, check.names=FALSE)

## remove colum "Gene Name" as we want to redocrate with recent genenames
prot.exps <- prot.exps[,-c(2)]

write.table(prot.exps, file=paste0(output_file,"tsv.undecorated"), sep="\t", quote=FALSE, row.names=FALSE)

