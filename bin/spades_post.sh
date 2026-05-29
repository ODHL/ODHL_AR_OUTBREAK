#!/bin/bash -l

#
# Description: Script to clean up the output of SPAdes
# Usage: ./afterspades.sh -p <prefix>
# Output location:
# V2.0 (11/15/2023) Changed to signify adoption of CLIA-minded versioning

version=2.0

# Function to show help message
show_help() {
    echo "Usage: $0 -p <prefix> [-V] [-h]"
    echo "  -p <prefix>   Specify the prefix for output files"
    echo "  -V            Show version information"
    echo "  -h            Show this help message"
}

# Parse command line options
options_found=0
while getopts ":p:Vh" option; do
    options_found=$(( options_found + 1 ))
    case "${option}" in
        p) 
            prefix="${OPTARG}";; # Get the prefix from input
        V) 
            show_version="True";;
        h) 
            show_help
            exit 0;;
        \?) 
            echo "Invalid option: ${OPTARG}" >&2
            show_help
            exit 1;;
        :) 
            echo "Option -${OPTARG} requires an argument." >&2
            show_help
            exit 1;;
    esac
done

# Show version and exit if requested
if [[ "${show_version}" = "True" ]]; then
    echo "afterspades.sh: ${version}"
    exit 0
fi

# Check if prefix is set
if [[ -z "${prefix}" ]]; then
    echo "Error: Prefix (-p) is required." >&2
    show_help
    exit 1
fi

# Begin main script logic
spades_complete=run_completed
echo \$spades_complete | tr -d "\\n" > "${prefix}_spades_outcome.csv"

if [ -f spades/scaffolds.fasta ]; then
    mv spades/scaffolds.fasta "${prefix}.scaffolds.fa"
    gzip -n "${prefix}.scaffolds.fa"
    spades_complete=scaffolds_created
else
    spades_complete=no_scaffolds
fi
echo ,$spades_complete | tr -d "\n" >> "${prefix}_spades_outcome.csv"

if [ -f spades/contigs.fasta ]; then
    mv spades/contigs.fasta "${prefix}.contigs.fa"
    gzip -n "${prefix}.contigs.fa"
    spades_complete=contigs_created
else
    spades_complete=no_contigs
fi
echo ,$spades_complete | tr -d "\n" >> "${prefix}_spades_outcome.csv"

if [ -f spades/assembly_graph_with_scaffolds.gfa ]; then
    mv spades/assembly_graph_with_scaffolds.gfa "${prefix}.assembly.gfa"
    gzip -n "${prefix}.assembly.gfa"
fi
