#!/bin/bash
# bash run_.sh 202401 k2_standard_08gb_20240112.tar.gz

tag=$1
kraken_db=$2
kraken_output="k2_standard_08gb_reformat_${tag}.tar.gz"

if [[ ${kraken_db} == *.tar.gz ]]; then
	echo "Preparing K2 directory: from ${kraken_db} to  ${kraken_output}"
	
	# Use standard gzip for decompression
	tar -xzf "${kraken_db}" || {
		echo "Error: Failed to extract ${kraken_db}" >&2
		exit 1
	}

        # create the final dir
        mkdir -p "${kraken_output}"
        mv *.kmer_distrib *.k2d seqid2taxid.map inspect.txt ktaxonomy.tsv "${kraken_output}" 2>/dev/null || {
        	echo "Warning: Some expected files were not found."
	}
elif
	echo "Output already exists: ${kraken_output}"
fi


