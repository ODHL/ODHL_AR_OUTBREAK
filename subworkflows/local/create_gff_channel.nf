include { SAMPLESHEET_CHECK } from '../../modules/local/samplesheet_check'

workflow CREATE_GFF_CHANNEL {
    take:
    samplesheet // file: /path/to/samplesheet_gff.csv

    main:
        SAMPLESHEET_CHECK ( samplesheet )
            .csv
            .splitCsv ( header:true, sep:',' )
            .map { create_sample_channels(it) }
            .set { sampleList }
    emit:
        sampleList                                     // channel: [ val(meta) ]
        valid_samplesheet = SAMPLESHEET_CHECK.out.csv
}

def create_sample_channels(LinkedHashMap row) {
    def meta = [:]
    meta.id           = row.sample

    def array = []
    array = [ meta ]
    return array
}