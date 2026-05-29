process REPORT_OUTBREAK_PREP {
    tag "REPORT_OUTBREAK_PREP"
    label 'process_low'

    input:
        path(config_arReport)
        path(analyzer_results)
        path(CFSAN_snpMatrix)
        path(IQTREE_genomeTree)
        path(ROARY_coreGenomeStats)
        path(ar_predictions)
        path(outbreak_metadata)
        val(projectID)
        path(outbreak_RMD)
        path(ref_samples)

    output:
        path("*_outbreakReport.Rmd")        , emit: projecOutbreakRMD
        path("db_lookup.csv")               , emit: dbLookup

    script:
    """
    # prep the report file
    cp $outbreak_RMD ${projectID}_outbreakReport.Rmd

    # prep the final report and RMD file
    bash report_outbreak_prep.sh \
        ${config_arReport} \
        ${analyzer_results} \
        ${CFSAN_snpMatrix} \
        ${IQTREE_genomeTree} \
        ${ROARY_coreGenomeStats} \
        ${ar_predictions} \
        ${outbreak_metadata} \
        ${projectID} \
        ${projectID}_outbreakReport.Rmd \
        ${ref_samples}
    """
}