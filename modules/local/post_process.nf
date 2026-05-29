process POST_PROCESS {
    label 'process_single'

    input:
    path(all_files_ch)
    path(final_phoenix_summary)
    path(core_functions_script)
    path(labResults)

    output:
    path('processed_pipeline_results.csv')         , emit: pipeline_results
    path('quality_results.csv')          , emit: quality_results
    path("versions.yml")                 , emit: versions

    script:
    """
    post_process.sh \
        $core_functions_script \
        $final_phoenix_summary \
        $labResults

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        post_process_tag: "v1.0"
    END_VERSIONS
    """
}