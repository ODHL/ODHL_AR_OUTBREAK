#!/bin/bash

#########################################################
# ARGS
#########################################################
configFILE=$1
analyzer_results=$2
CFSAN_snpMatrix=$3
IQTREE_genomeTree=$4
ROARY_coreGenomeStats=$5
ar_predictions=$6
outbreak_metadata=$7
projectID=$8
outbreak_RMD=$9
ref_samples=${10}

##########################################################
# Eval, source
#########################################################

#########################################################
# Set dirs, files, args
#########################################################

##########################################################
# update variables
#########################################################
# set date
today=`date +%Y%m%d`

##########################################################
# Run analysis
#########################################################    
# prepare the report
sed -i "s/REP_CONFIG/$configFILE/g" $outbreak_RMD
sed -i "s/REP_SAMPLETABLE/$analyzer_results/g" $outbreak_RMD
sed -i "s/REP_SNPMATRIX/$CFSAN_snpMatrix/g" $outbreak_RMD
sed -i "s/REP_IQTREE/$IQTREE_genomeTree/g" $outbreak_RMD
sed -i "s/REP_CGSTATS/$ROARY_coreGenomeStats/g" $outbreak_RMD
sed -i "s~REP_PREDICT~$ar_predictions~g" $outbreak_RMD
sed -i "s~REP_META~$outbreak_metadata~g" $outbreak_RMD
sed -i "s/REP_OB/$projectID/g" $outbreak_RMD
sed -i "s~REP_DATE~$today~g" $outbreak_RMD
sed -i "s~REF_REFSAMPLES~$ref_samples~g" $outbreak_RMD
sed -i "s~REP_DBLOOKUP~db_lookup.csv~g" $outbreak_RMD

# Generate db_lookup.csv: non-OB entries from db_master with SRRID populated
dbmaster="$HOME/workflows/ODHL_AR/assets/databases/IDdbs/db_master.csv"
echo "OHIO_ID,SRRID,SAMID,DATE_ASSIGNED" > db_lookup.csv
if [ -f "$dbmaster" ]; then
  awk -F',' 'NR>1 && $4!="" && $2!="" && $1!~/^OB/ { print $2","$4","$5","$6 }' "$dbmaster" >> db_lookup.csv
fi