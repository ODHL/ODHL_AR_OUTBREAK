include { SAMPLESHEET_CHECK } from '../../modules/local/samplesheet_check'

workflow CREATE_INPUT_CHANNEL {
    take:
    samplesheet   // file: /path/to/samplesheet.csv
    needsDownload // retained for compatibility with the caller

    main:
    def runNCBI = params.runNCBI.toBoolean()
    def runGC = params.runGC.toBoolean()
    def runBASESPACE = params.runBASESPACE.toBoolean()

    SAMPLESHEET_CHECK ( samplesheet )
        .csv
        .splitCsv ( header:true, sep:',' )
        .map { create_download_channels(it, runNCBI, runGC, runBASESPACE) }
        .set { reads }

    emit:
    reads                                     // channel: [ val(meta), [ reads ] ]
    valid_samplesheet = SAMPLESHEET_CHECK.out.csv
}

// Function to get list of [ meta ] or [ meta, [ fastq_1, fastq_2 ] ]
def create_download_channels(LinkedHashMap row, boolean runNCBI=false, boolean runGC=false, boolean runBASESPACE=false) {
    def meta = [:]
    meta.id = row.sample.toString()

    def download_mode = (row.download_source ?: row.download_mode ?: row.source ?: '').toString().trim().toLowerCase()
    def gc_path = (row.gc_path ?: row.gcs_path ?: row.path ?: row.download_path ?: '').toString().trim()
    def srr_id = (row.srr_id ?: '').toString().trim()

    if (download_mode in ['ncbi', 'sra']) {
        meta.download_mode = 'ncbi'
        meta.srr_id = srr_id
        return [ meta ]
    } else if (download_mode in ['gc', 'gcs']) {
        meta.download_mode = 'gc'
        meta.gc_path = gc_path
        return [ meta ]
    } else if (download_mode in ['basespace', 'bs']) {
        meta.download_mode = 'basespace'
        return [ meta ]
    } else if (download_mode == 'local' && row.fastq_1 && row.fastq_2) {
        meta.download_mode = 'local'
        return [ meta, [ file(row.fastq_1), file(row.fastq_2) ] ]
    } else if (runNCBI) {
        meta.download_mode = 'ncbi'
        meta.srr_id = srr_id
        return [ meta ]
    } else if (runGC) {
        meta.download_mode = 'gc'
        meta.gc_path = gc_path
        return [ meta ]
    } else if (runBASESPACE) {
        meta.download_mode = 'basespace'
        return [ meta ]
    }

    if (row.fastq_1 && row.fastq_2) {
        meta.download_mode = 'local'
        return [ meta, [ file(row.fastq_1), file(row.fastq_2) ] ]
    }

    meta.download_mode = 'basespace'
    return [ meta ]
}