# Author: S Sevilla
# Date: 1/20/2025
# Version: 1.0

# bash core_ncbi_prep.sh \
# bin/core_functions.sh \ #core_functions
# test \ #project_id
# test/metaData_NCBI.csv \ #metadata_file
# conf/ncbiConfig.yaml \ #ncbiConfig
# assets/databases/ncbi/srr_db_master.csv #idDB_file
# ch_sample_list #sample_list
# ch_pipe_results #pipeline_results
# ch_wgs_results #idDB_results

#########################################################
# ARGS
#########################################################
core_functions=$1
project_id=$2
metadata_file=$3
ncbiConfig=$4
idDB_file=$5
pipeline_results=$6
idDB_results=$7

##########################################################
# Eval, source
#########################################################
source $(dirname "$0")/core_functions.sh
eval $(parse_yaml ${ncbiConfig} "config_")

#########################################################
# project variables
#########################################################
#set year
year="2025"

# set date
date_stamp=`date '+%Y_%m_%d'`

##########################################################
# Set files, dir
#########################################################
# pull the id dir 
id_dir=$(dirname "$idDB_file")
id_log="id_db_log.txt"

# update the ID results file to include SRR
ncbiDB_results="id_db_results_preNCBI.csv"
cp $idDB_results $ncbiDB_results

# ncbi
ncbi_upload="ncbi_sample_list.csv"
ncbi_attributes=batched_ncbi_att_${project_id}_${date_stamp}.tsv
ncbi_metadata=batched_ncbi_meta_${project_id}_${date_stamp}.tsv

# prepare the input dir
upload_dir="upload_dir"
mkdir -p $upload_dir

#########################################################
# Run Code
#########################################################
# Check samples were not already uploaded
if [[ -f $id_log ]]; then rm $id_log; fi
echo "** CHECK **" >> $id_log
awk -F"," '{print $2}' $idDB_results > passed_samples
IFS=$'\n' read -d '' -r -a sample_list < passed_samples
for sample_id in "${sample_list[@]}"; do
    echo "--sample: $sample_id" >> $id_log
    
    # grab wgsID, srrID
    wgsID=`cat $idDB_results | grep $sample_id | cut -f3 -d","`
	srrID=`cat $idDB_file | grep $sample_id | cut -f4 -d","` 
	samID=`cat $idDB_file | grep $sample_id | cut -f5 -d","` 

    # check the old ncbi file to make sure it hasnt been updated
	if [[ $srrID == "" ]]; then
		echo "----NEW SRR SAMPLE: $wgsID" >> $id_log
		echo "$sample_id,$wgsID" >> $ncbi_upload
	else
		echo "----SRR already exists: $srrID ($wgsID)" >> $id_log
		sed -i "s/$wgsID,,,/$wgsID,$srrID,$samID,/g" $ncbiDB_results
	fi
done

# Create NCBI upload files
## Create manifest for attribute upload
chunk1="*sample_name\tsample_title\tbioproject_accession\t*organism\tstrain\tisolate\thost"
chunk2="isolation_source\t*collection_date\t*geo_loc_name\t*sample_type\taltitude\tbiomaterial_provider\tcollected_by\tculture_collection\tdepth\tenv_broad_scale"
chunk3="genotype\thost_tissue_sampled\tidentified_by\tlab_host\tlat_lon\tmating_type\tpassage_history\tsamp_size\tserotype"
chunk4="serovar\tspecimen_voucher\ttemp\tdescription\tMLST"
echo -e "${chunk1}\t${chunk2}\t${chunk3}\t${chunk4}" > $ncbi_attributes

# Create manifest for metadata upload
chunk1="sample_name\tlibrary_ID\ttitle\tlibrary_strategy\tlibrary_source\tlibrary_selection"
chunk2="library_layout\tplatform\tinstrument_model\tdesign_description\tfiletype\tfilename"
chunk3="filename2\tfilename3\tfilename4\tassembly\tfasta_file"
echo -e "${chunk1}\t${chunk2}\t${chunk3}" > $ncbi_metadata

# process samples that need uploading
echo "** UPLOAD **" >> $id_log
awk -F"," '{print $1}' $ncbi_upload > passed_samples
IFS=$'\n' read -d '' -r -a sample_list < passed_samples
for sampleID in "${sample_list[@]}"; do
	# pull wgsID
	wgsID=`cat $ncbiDB_results | grep $sampleID | cut -f3 -d","`
	echo "--sample upload: $sampleID" >> $id_log

	# determine the sample line in the pipeline results
	# sampleID=`echo $sampleID | cut -f1 -d"-"` # replace spaces with underscores for OB samples only
	SID=$(awk -F"\t" -v sid=$sampleID '{ if ($1 == sid) print NR }' $pipeline_results)

	# pull organism from results	
	organism=`cat $pipeline_results | awk -F"\t" -v i=$SID 'FNR == i {print $9}' | sed "s/([0-9]*.[0-9]*%)//g" | sed "s/  //g"`

	# metadata file does not include projectID as part of the name
	clean_sample_id=`echo "$sampleID" | sed "s/"-${project_id}"//g"` 

	# grab metadata line
	meta=`cat $metadata_file | grep "$clean_sample_id"`

	#if meta is found create input metadata row
	if [[ ! "$meta" == "" ]]; then
		#convert date to ncbi required format - 4/21/81 to 1981-04-21
		raw_date=`echo $meta | awk -F',' '{print $(NF-1)}'` #| grep -o "[0-9]*/[0-9]*/202[0-9]*"`
		collection_yr=`echo "${raw_date}" | awk '{split($0,a,"/"); print a[3]}' | tr -d '"'`

		# set title
		sample_title=`echo "Illumina Sequencing of ${wgsID}"`
				
		# pull source
		isolation_source=`echo $meta | awk -F"," '{print $11}'`

		# pull instrument
		instrument_model=`echo $project_id | cut -f2 -d"-"| grep -o "^."`
		if [[ $instrument_model == "M" ]]; then instrument_model="Illumina MiSeq"; else instrument_model="NextSeq 1000"; fi

		# get MLST
		MLST=`cat $pipeline_results | grep $sampleID | awk -F"\t" '{print $24}'| awk -F";" '{print $NF}'`

		# ncbi_attributes
		## break output into chunks
		chunk1="${wgsID}\t${sample_title}\t${config_bioproject_accession}\t${organism}\t${config_strain}\t${wgsID}\t${config_host}"
		chunk2="${isolation_source}\t${collection_yr}\t${config_geo_loc_name}\t${config_sample_type}\t${config_taltitude}"
		chunk3="${config_biomaterial_provider}\t${config_tcollected_by}\t${config_culture_collection}\t${config_depth}"
		chunk4="${config_env_broad_scale}\t${config_genotype}\t${config_host_tissue_sampled}\t${config_identified_by}"
		chunk5="${config_lab_host}\t${config_lat_lon}\t${config_mating_type}\t${config_passage_history}\t${config_samp_size}"
		chunk6="${config_serotype}\t${config_serovar}\t${config_specimen_voucher}\t${config_temp}\t${config_description}\t${MLST}"
		## add output variables to attributes file
		echo -e "${chunk1}\t${chunk2}\t${chunk3}\t${chunk4}\t${chunk5}\t${chunk6}\t${chunk7}\t${chunk8}\t${chunk9}\t${chunk10}\t${chunk11}\t${chunk12}" >> $ncbi_attributes
				
		# ncbi_metadata
		## breakoutput into chunks
		chunk1="${wgsID}\t${wgsID}\t${sample_title}\t${config_library_strategy}\t${config_library_source}\t${config_library_selection}"
		chunk2="${config_library_layout}\t${config_platform}\t${instrument_model}\t${config_design_description}\t${config_filetype}\t${wgsID}.R1.fastq.gz"
		chunk3="${wgsID}.R2.fastq.gz\t${config_filename3}\t${config_filename4}\t${assembly}\t${config_fasta_file}"
		## add output variables to attributes file
		echo -e "${chunk1}\t${chunk2}\t${chunk3}" >> $ncbi_metadata

		# move fastq files
		for file in ${sampleID}*_R[12]_001.fastq.gz; do
			# Extract base sample name before _SXX_LXXX
			base_name=$(echo "$file" | sed -E 's/_S[0-9]+_L[0-9]+[0-9]+//')

			# Rename with .R1 or .R2
			new_name=$(echo "$base_name" | sed 's/_R1_001/.R1/' | sed 's/_R2_001/.R2/')

			# Rename with wgsID
			new_name=`echo $new_name | sed "s/$sampleID/$wgsID/g"`

			# Move to upload directory
			mv "$file" "$upload_dir/$new_name"
		done
	else
		echo "Missing metadata $sampleID | $clean_sample_id" >> $id_log
	fi
done