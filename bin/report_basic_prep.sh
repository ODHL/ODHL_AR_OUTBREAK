#!/bin/bash

#########################################################
# ARGS
#########################################################
ncbi_post_file=$1
analyzer_results=$2
basic_RMD=$3
project_id=$4
configFILE=$5
##########################################################
# Eval, source
#########################################################

#########################################################
# Set dirs, files, args
#########################################################
final_results=${project_id}_final_report.csv
merged_prediction="ar_predictions.tsv"

##########################################################
# update variables
#########################################################
# set date
today=`date +%Y%m%d`

##########################################################
# Run analysis
#########################################################    
# prepare the report
sed -i "s/REP_CONFIG/$configFILE/g" $basic_RMD
sed -i "s/REP_SAMPLETABLE/$final_results/g" $basic_RMD
sed -i "s~REP_PREDICT~$merged_prediction~g" $basic_RMD
sed -i "s/REP_PROJID/$project_id/g" $basic_RMD
sed -i "s/REP_OB/$project_id/g" $basic_RMD
sed -i "s~REP_DATE~$today~g" $basic_RMD

# create the sample list
awk '{print $1}' $analyzer_results | grep -v "ID" > passed_samples
IFS=$'\n' read -d '' -r -a sample_list < passed_samples

# generate header for predictions file
echo -e "Sample \tGene \tCoverage \tIdentity" > $merged_prediction

# generate final report file
chunk1="specimen_id,wgs_id,srr_id,wgs_date_put_on_sequencer,sequence_classification,run_id"
chunk2="auto_qc_outcome,estimated_coverage,genome_length,species,mlst_scheme_1"
chunk3="mlst_1,mlst_scheme_2,mlst_2,gamma_beta_lactam_resistance_genes"
chunk4="auto_qc_failure_reason,lab_results,samn_id"
echo -e "${chunk1},${chunk2},${chunk3},${chunk4}" > $final_results 

# create final result file 
# create gene prediction file for any passing samples  
for sample_id in "${sample_list[@]}"; do
    # set variables
    clean_sample_id=`echo "$sample_id" | sed "s/"-${project_id}"//g"` 
    wgs_date_put_on_sequencer=`echo $project_id | cut -f3 -d"-"`
    run_id=$project_id

    # set ID's from post file
    wgs_id=`cat $ncbi_post_file | grep $sample_id | cut -f3 -d","`
    raw_srr=`cat $ncbi_post_file | grep $sample_id | cut -f4 -d","`
    raw_samn=`cat $ncbi_post_file | grep $sample_id | cut -f5 -d","`
    # only use values that match expected NCBI accession patterns
    if [[ "$raw_srr" =~ ^SRR[0-9]+ ]]; then srr_id="$raw_srr"; else srr_id=""; fi
    if [[ "$raw_samn" =~ ^SAMN[0-9]+ ]]; then samn_id="$raw_samn"; else samn_id=""; fi

    # pull data from analyzer_results
    ## determine row to pull analysis information from
    SID=$(awk -F"\t" -v sid=$sample_id '{ if ($1 == sid) print NR }' $analyzer_results)
    SID=`echo $SID | cut -d" " -f1`
    ## pull data from analysis row
    estimated_coverage=`cat $analyzer_results | awk -F"\t" -v i=$SID 'FNR == i {print $4}'`
    genome_length=`cat $analyzer_results | awk -F"\t" -v i=$SID 'FNR == i {print $5}'`
    auto_qc_failure_reason=`cat $analyzer_results | awk -F"\t" -v i=$SID 'FNR == i {print $24}' | cut -f1 -d";"`
    ## if samples fail due to seq (low reads), adjust
    auto_qc_outcome=`cat $analyzer_results | awk -F"\t" -v i=$SID 'FNR == i {print $2}'`
    if [[ $auto_qc_outcome == "" ]]; then auto_qc_outcome="SeqFAIL"; auto_qc_failure_reason="sequencing_failure"; fi
    species=`cat $analyzer_results | awk -F"\t" -v i=$SID 'FNR == i {print $9}'| cut -f1 -d","`
    mlst_1=`cat $analyzer_results | awk -F"\t" -v i=$SID 'FNR == i {print $16}'| cut -f1 -d","`
    mlst_scheme_1=`cat $analyzer_results | sort | uniq | awk -F"\t" -v i=$SID 'FNR == i {print $15}'`
    mlst_2=`cat $analyzer_results | sort | uniq | awk -F"\t" -v i=$SID 'FNR == i {print $18}'| cut -f1 -d","`
    mlst_scheme_2=`cat $analyzer_results | awk -F"\t" -v i=$SID 'FNR == i {print $17}'`
    sequence_classification=`cat $analyzer_results | awk -F"\t" -v i=$SID 'FNR == i {print $24}' | awk -F";" '{print $NF}'`
    gamma_beta_lactam_resistance_genes=`cat $analyzer_results | awk -F"\t" -v i=$SID 'FNR == i {print $19}'`
    lab_results=`cat $analyzer_results | awk -F"\t" -v i=$SID 'FNR == i {print $25}'`

    # prepare chunks
    chunk1="$clean_sample_id,$wgs_id,$srr_id,$wgs_date_put_on_sequencer,\"${sequence_classification}\",$run_id"
    chunk2="$auto_qc_outcome,$estimated_coverage,$genome_length,"${species}",$mlst_scheme_1"
    chunk3="\"${mlst_1}\",$mlst_scheme_2,\"${mlst_2}\",\"${gamma_beta_lactam_resistance_genes}\""
    chunk4="\"${auto_qc_failure_reason}\",\"${lab_results}\",\"${samn_id}\""
    echo -e "${chunk1},${chunk2},${chunk3},${chunk4}" >> $final_results
    	
    # create all genes output file
	if [[ $auto_qc_outcome == "PASS" ]]; then
        if [[ -f ${sample_id}_all_genes.tsv ]]; then
            cat ${sample_id}_all_genes.tsv | awk -F"\t" '{print $2"\t"$6"\t"$16"\t"$17}' | sed -s "s/_all_genes.tsv//g" | grep -v "_Coverage_of_reference_sequence">> $merged_prediction
        fi
    fi
done