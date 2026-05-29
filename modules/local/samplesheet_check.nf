process SAMPLESHEET_CHECK {
    tag "samplesheet"
    label 'process_single'

    input:
    path(samplesheet)

    output:
    path("*_clean.csv"),                   emit: csv

    script:
    def args = task.ext.args ?: ''
    """
    cp $samplesheet samplesheet_clean.csv
    """

    stub:
    """
    touch ${samplesheet}.csv
    """
}