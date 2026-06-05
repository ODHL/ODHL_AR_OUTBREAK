process NO_NCBI_POST {
    label 'process_single'

    input:
    path(analyzer_results)
    val(project_id)

    output:
    path("versions.yml")               , emit: versions
    path("id_db_results_postNCBI.csv") , emit: ncbi_post_file

    script:
    """
    # Build a minimal post-NCBI style mapping file so downstream report
    # generation can run without upload accessions.
    echo "sample,placeholder,wgs_id,srr_id,samn_id" > id_db_results_postNCBI.csv
    awk -F"\\t" 'NR>1 && \$1!="" && \$1!="ID" {print \$1",,,,"}' "$analyzer_results" | sort -u >> id_db_results_postNCBI.csv

    cat <<-END_VERSIONS >> versions.yml
    "${task.process}":
        post_process_tag: "v1.0"
    END_VERSIONS
    """
}