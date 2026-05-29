process REPORT_OUTBREAK {
  tag "REPORT_OUTBREAK"
  label 'process_high'

    container 'ghcr.io/slsevilla/report:latest'

  input:
    path(ch_config_arReport)
    path(ch_analyzer_results)
    path(ch_CFSAN_snpMatrix)
    path(ch_IQTREE_genomeTree)
    path(ch_ROARY_coreGenomeStats)
    path(ch_ar_predictions)
    path(ch_outbreak_metadata)
    val(projectID)
    path(updated_outbreakRMD)
    path(ref_samples)
    path(db_lookup)

  output:
    path('*.html')           , emit: report

  script:
  """
  Rscript -e 'rmarkdown::render("${updated_outbreakRMD}", output_file="${projectID}_outbreakReport.html", output_dir = getwd())'
  """
}