process GET_RAW_STATS {
    tag "${meta.id}"
    label 'process_single'
    container 'quay.io/jvhagey/phoenix@sha256:f0304fe170ee359efd2073dcdb4666dddb96ea0b79441b1d2cb1ddc794de4943'

    input:
    tuple val(meta), path(reads), path(fairy_outcome), val(fairy_corrupt_outcome)
    val(busco_val)

    output:
    tuple val(meta), path('*_raw_reads_counts.txt'),            emit: combined_raw_stats
    tuple val(meta), path('*_summary_rawStats.txt'),            emit: raw_outcome
    path('*_summaryline.tsv'),                                  optional:true, emit: summary_line
    tuple val(meta), path('*.synopsis'),                        optional:true, emit: synopsis
    path("versions.yml"),                                       emit: versions

    script: // This script is bundled with the pipeline, in cdcgov/phoenix/bin/
    // define variables
    def prefix = task.ext.prefix ?: "${meta.id}"
    def busco_parameter = busco_val ? "--busco" : ""
    def container_version = "base_v2.1.0"
    def container = task.container.toString() - "quay.io/jvhagey/phoenix@"
    def script_q30 = "q30.py"
    def script_merged = "get_raw_stats.py"
    """
    # run individual usage stats
    ${script_q30} -i ${reads[0]} > ${prefix}_R1_stats.txt
    ${script_q30} -i ${reads[1]} > ${prefix}_R2_stats.txt

    # create new summary
    cp $fairy_outcome ${prefix}_summary_rawStats.txt

    # compile all stats
    ${script_merged} \
        -n ${prefix} \
        -r1 ${prefix}_R1_stats.txt \
        -r2 ${prefix}_R2_stats.txt \
        -b ${busco_parameter} \
        -oS ${prefix}_summary_rawStats.txt \
        -oRC ${prefix}_raw_reads_counts.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //g')
        q30.py: \$(${script_q30} --version )
        script_merged.py: \$(${script_merged} --version )
        phoenix_base_container_tag: ${container_version}
        phoenix_base_container: ${container}
    END_VERSIONS
    """
}