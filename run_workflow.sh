#!/bin/bash
# ODHL AR Outbreak Pipeline
# Usage: bash run_workflow.sh -i OB26004 -s samplesheet.csv -g samplesheet_gff.csv -m metadata.csv -p Klebsiella_pneumoniae

#############################################################################################
# Setup
#############################################################################################
source ~/.bashrc

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_NF="$SCRIPT_DIR/main.nf"

helpFunction() {
   echo ""
   echo "Usage: bash run_workflow.sh [options]"
   echo ""
   echo "Required:"
   echo "  -i  project_id         Project identifier (e.g. OB26004)"
   echo "  -s  samplesheet        Path to samplesheet CSV (sample,fastq_1,fastq_2)"
   echo "  -g  samplesheet_gff    Path to GFF samplesheet CSV (sample) for outbreak filtering"
   echo "  -m  outbreak_metadata  Path to outbreak metadata CSV"
   echo "  -p  outbreak_species   Species name matching reference directory (e.g. Klebsiella_pneumoniae)"
   echo ""
   echo "Optional:"
   echo "  -n  nextflowParams     Additional Nextflow parameters (default: -profile docker,test --max_memory 7.GB --max_cpus 4)"
   echo "  -r  resume             Resume previous run: Y or N (default: Y)"
   echo "  -l  labResults         Path to lab results CSV"
   echo "  -d  metadata_NCBI      Path to NCBI metadata CSV"
   echo "  -o  output_NCBI        Path to NCBI output TSV (accession lookup)"
   echo "  -f  ref_samples        Path to reference samples CSV"
   exit 1
}

while getopts "i:s:g:m:p:n:r:l:d:o:f:" opt; do
   case "$opt" in
      i ) project_id="$OPTARG" ;;
      s ) samplesheet="$OPTARG" ;;
      g ) samplesheet_gff="$OPTARG" ;;
      m ) outbreak_metadata="$OPTARG" ;;
      p ) outbreak_species="$OPTARG" ;;
      n ) nextflowParams="$OPTARG" ;;
      r ) resume="$OPTARG" ;;
      l ) labResults="$OPTARG" ;;
      d ) metadata_NCBI="$OPTARG" ;;
      o ) output_NCBI="$OPTARG" ;;
      f ) ref_samples="$OPTARG" ;;
      ? ) helpFunction ;;
   esac
done

#############################################################################################
# Validate required args
#############################################################################################
if [ -z "$project_id" ] || [ -z "$samplesheet" ] || [ -z "$samplesheet_gff" ] || \
   [ -z "$outbreak_metadata" ] || [ -z "$outbreak_species" ]; then
   echo "ERROR: Missing required parameter(s)."
   helpFunction
fi

#############################################################################################
# Derived variables
#############################################################################################
project_name=$(echo "$project_id" | cut -f1 -d "_" | cut -f1 -d " ")

projDir="$HOME/output/$project_name"
outDir="$projDir/results/outbreakANALYSIS"
tmpDir="$projDir/tmp"
if [[ ! -d $tmpDir ]]; then mkdir -p $tmpDir; fi

#############################################################################################
# Optional defaults
#############################################################################################
if [ -z "$nextflowParams" ]; then
   nextflowParams="-profile docker,test --max_memory 7.GB --max_cpus 4"
fi

if [ -z "$resume" ] || [ "$resume" == "Y" ]; then
   nextflowParams="-resume $nextflowParams"
fi

if [ ! -z "$labResults" ];    then nextflowParams="$nextflowParams --labResults $labResults"; fi
if [ ! -z "$metadata_NCBI" ]; then nextflowParams="$nextflowParams --metadata_NCBI $metadata_NCBI"; fi
if [ ! -z "$output_NCBI" ];   then nextflowParams="$nextflowParams --output_NCBI $output_NCBI"; fi
if [ ! -z "$ref_samples" ];   then nextflowParams="$nextflowParams --ref_samples $ref_samples"; fi

#############################################################################################
# Run
#############################################################################################
cmd="nextflow run \
   $MAIN_NF \
   $nextflowParams \
   -entry OUTBREAK_ANALYZER \
   --input $samplesheet \
   --input_gff $samplesheet_gff \
   --outbreak_metadata $outbreak_metadata \
   --outbreak_species $outbreak_species \
   --outdir $outDir \
   --projectID $project_name \
   -work-dir $tmpDir"

echo
echo "Command Running:"
echo "$cmd"
$cmd
