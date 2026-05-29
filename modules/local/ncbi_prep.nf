process NCBI_PREP {
    label 'process_single'

    input:
    path(core_functions_script)
    val(project_id)
    path(metadata_file)
    path(ncbiConfig)
    path(idDB_file)
    path(pipeline_results)
    path(idDB_results)
    path(all_fastq_files)

    output:
    path('ncbi_sample_list.csv')               , emit: ncbi_sample_list
    path("versions.yml")                       , emit: versions
    path("batched_ncbi_att*")                  , emit: ncbi_att
    path("batched_ncbi_meta*")                 , emit: ncbi_meta
    path("id_db_results_preNCBI.csv")          , emit: ncbi_pre_file

    script:
    """
    core_ncbi_prep.sh \
        $core_functions_script \
        $project_id \
        $metadata_file \
        $ncbiConfig \
        $idDB_file \
        $pipeline_results \
        $idDB_results

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
    post_process_tag: "v1.0"
    END_VERSIONS
    """
}