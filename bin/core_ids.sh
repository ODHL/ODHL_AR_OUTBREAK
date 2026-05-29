# Author: S Sevilla
# Date: 1/20/2025
# Version: 1.0

# bash bin/core_id_id.sh

#########################################################
# ARGS
#########################################################
core_functions=$1
quality_file=$2
idDB_file=$3
project_id=$4

##########################################################
# Eval, source
#########################################################
source $(dirname "$0")/core_functions.sh

##########################################################
# Set files, dir
#########################################################
# pull the id dir 
id_dir=$(dirname "$idDB_file")
id_results="id_db_results.csv"
id_log="id_db_log.txt"

passed_samples=passed_samples.txt
failed_samples=failed_samples.txt
#########################################################
# project variables
#########################################################
year=$(date +%Y)

##########################################################
# Run code
#########################################################
# create cache of local
today=`date +%Y%m%d`
cachedDB_file=${today}_id_db.csv
cp $idDB_file $cachedDB_file

# add a new line
echo "" >> $cachedDB_file

# pull sampleIDs for all samples that passed analysis
cat $quality_file | grep -v "ID" | grep "PASS" | awk -F"," '{print $1}' | uniq > $passed_samples
IFS=$'\n' read -d '' -r -a passed_list < $passed_samples

# pull sampleIDs for all samples that failed analysis
cat $quality_file | grep -v "ID" | grep "FAIL" | awk -F"," '{print $1}' | uniq > $failed_samples
IFS=$'\n' read -d '' -r -a failed_list < $failed_samples

# pull the first ID
echo "--pulling ID from cache" >> $id_log
sed -i '/^$/d' $cachedDB_file
last_saved_id=`tail -n1 $cachedDB_file | awk -F"," '{print $3}' | cut -f2 -d"-"`
echo "----last saved: $last_saved_id" >> $id_log
stripped_id=`echo "${last_saved_id#"${last_saved_id%%[!0]*}"}"`
echo "----stripped $stripped_id" >> $id_log
new_id=$(( stripped_id + 1 ))

# for each passed sample create an ID file
# add the info to the ID cached file
## PROJECT_ID,OHIO_ID,WGSID,SRRID,SAMID,DATE_ASSIGNED
### OHIO_ID is formatted: YYYY-GZ-0001
for sample_id in ${passed_list[@]}; do
    echo "--sample: $sample_id">> $id_log
            
    # clean the sampleID
    clean_id=$(clean_file_names $sample_id)

    # check if sample already has an ID
    check=`cat $cachedDB_file | grep "$clean_id"`

    # if the check is empty, add new ID
    if [[ $check == "" ]]; then
        echo "----assigning new ID">> $id_log

        # add zeros so the final ID is always four digits
        if [[ $new_id -lt 10 ]]; then
            final_id="${year}ZN-000$new_id"
        elif [[ $new_id -lt 100 ]]; then
            final_id="${year}ZN-00$new_id"
        elif [[ $new_id -lt 1000 ]]; then
            final_id="${year}ZN-0$new_id"
        else
            final_id="${year}ZN-$new_id"
        fi

        #increase counter
        new_id=$(( new_id + 1 ))

        # add sample with new ID to list
        # PROJECT_ID,OHIO_ID,WGSID,SRRID,SAMID,DATE_ASSIGNED
        add_line="$project_id,$sample_id,$final_id,,,$today"
        echo $add_line >> $cachedDB_file
    else
        echo "----sample was already assigned an ID: $check">> $id_log
        final_id=`echo $check |cut -f3 -d","`
        add_line="$project_id,$sample_id,$final_id,,,$today"
    fi

    # add to results file
    echo -e "$add_line" >> $id_results
done        

# copy the original file to the backup
sed -i '/^$/d' $cachedDB_file
cat $idDB_file | uniq > $id_dir/id_db_backup.csv

# copy the new file to master
cat $cachedDB_file | uniq > $id_dir/id_db_master.csv

# copy the cached file to the directory
cp $cachedDB_file $id_dir/cached