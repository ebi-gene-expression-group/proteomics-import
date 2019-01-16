#!/usr/bin/env bash

## This script looks for curated config files and protein expression matrices 
## provided by PRIDE and performs intermediate steps of renaming files, aggregation of 
## technical replicates, estimate median values, decoration, generation of condensed sdrf,
## deploying to staging and loading on wwwdev using webAPI.

scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
projectRoot=${scriptDir}/..
source $projectRoot/../db/scripts/experiment_loading_routines.sh
source $projectRoot/../bioentity_annotations/decorate_routines.sh

# check for env variables if defined
[ ! -z ${expAcc+x} ] || ( echo "Env var expAcc for the id/accession of the experiment needs to be defined." && exit 1 )
[ ! -z ${expTargetDir+x} ] || ( echo "Env var expTargetDir for the path of the experiment needs to be defined." && exit 1 )
[ ! -z ${TOMCAT_HOST_USERNAME+x} ] || ( echo "Env var TOMCAT_HOST_USERNAME curator needs to be defined." && exit 1 )
[ ! -z ${TOMCAT_HOST_PASSWORD+x} ] || ( echo "Env var TOMCAT_HOST_PASSWORD needs to be defined." && exit 1 )
[ ! -z ${TOMCAT_HOST+x} ] || ( echo "Env var TOMCAT_HOST ie. ves:8080 needs to be defined." && exit 1 )

    	
# function to sync files
rsyncExperimentFolders(){
    	rsync -a --copy-links --out-format="%n%L" \
    		--include '*/' \
    		--exclude '*archive/**' \
    		--exclude '*condensed-sdrf*' \
    		--include '*.tsv' \
    		--include 'qc/**' \
    		--include '*.xml' \
    		--include '*.txt' \
    		--include '*.png' \
    		--include '*.bedGraph'\
    		--include '*.Rdata' \
    		--include '*.pdf' \
    		--include '*.tsv.gz' \
    		--exclude '*' \
    		$@
}

copy_protein(){   
	expAcc=$1
	source_dir=$2
	target_dir=$ATLAS_EXPS/$expAcc

	mkdir -p "$target_dir"
	chmod 755 "$target_dir"
    echo "syncing experiment to staging area -  - $expAcc "
	rsyncExperimentFolders --prune-empty-dirs -b --backup-dir "archive" --suffix ".1" "$source_dir/*" "$target_dir"

	## 
	echo "generating mage-tab - $expAcc"
	get_magetab_for_experiment $expAcc
}

rename_files(){
 	expAcc=$1
 	
 	if [ -s "analysis-methods.tsv" ]; then
 		mv analysis-methods.tsv ${expAcc}-analysis-methods.tsv
 	else
 	   echo "ERROR: analysis-methods.tsv file doesn't exist for $expAcc"
 	fi

 	cp *MappedToGeneID*.txt ${expAcc}.tsv.undecorated.backup
 }
 	
 pushd $expTargetDir
    # rename analysis methods
    echo "renaming $expAcc"
    rename_files $expAcc

    # remove quotes and gename and make matrix in tsv format.
    # remove genename column as we will decorate using recent Ensembl annotations.
    echo "Remove genes names and make the matrix to tsv"
    $projectRoot/bin/removeGeneNamesInDataMatrix.R ${expAcc}.tsv.undecorated.backup
	
    # aggregate technical replicates
	echo "summarise expression for $expAcc.."
	$projectRoot/../irap/gxa_summarize_expression.pl \
    --aggregate-quartiles \
    --configuration ${expAcc}-configuration.xml \
    < ${expAcc}.tsv.undecorated \
    > ${expAcc}.tsv.undecorated.aggregated
    
	# append columns with .WithInSampleAbundance and pick median value of quartiles
	echo "median values pick up and appending columns with sample abundance.."
    $projectRoot/bin/appendColnamesInDataMatrix.R ${expAcc}.tsv.undecorated.aggregated

    # This step performs decoration by mapping Ensembl ids with gene names with latest 
    # annotations from Ensembl.
    echo "decoration of protein expression matrix.."
    $projectRoot/../bioentity_annotations/decorate_baseline_rnaseq_experiment.sh $expTargetDir
    organism=$($projectRoot/bash_util/get_organism.sh $expTargetDir)
    geneNameFile=$(get_geneNameFile_given_organism $organism)
	decorate_rnaseq_file ${expAcc}.tsv.undecorated.aggregated baseline "$geneNameFile" >&2
    
    # copy files to staging and generate condensed sdrf.
	echo "copying files to staging.."
    copy_protein $expAcc $expTargetDir
	
    # all baseline proteomic studies are loaded as public.
    echo "loading $expAcc.."
    WEB_APP_CALL="load_public"  
    curl -X GET -u $TOMCAT_HOST_USERNAME:$TOMCAT_HOST_PASSWORD "http://$TOMCAT_HOST/gxa/admin/experiments/$expAcc/$WEB_APP_CALL" | tee >( jq -r '.[].error' > $expAcc.webapp_error )
popd
