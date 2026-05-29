process REPORT_BASIC_PREP {
    tag "REPORT_BASIC_PREP"
    label 'process_low'

    input:
        path(gene_files)
        path(ncbi_post_file)
        path(analyzer_results)
        path(basic_RMD)
        val(projectID)
        path(config_arReport)

    output:
        path("*final_report.csv")       , emit: finalReport
        path("ar_predictions.tsv")      , emit: predictions
        path("*_basicReport.Rmd")       , emit: projectBasicRMD

    script:
    """
    # prep the report file
    cp $basic_RMD ${projectID}_basicReport.Rmd

    # prep the final report and RMD file
    bash report_basic_prep.sh \
        $ncbi_post_file \
        $analyzer_results \
        ${projectID}_basicReport.Rmd \
        $projectID \
        $config_arReport
    """
}