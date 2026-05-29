process GET_TRIMD_STATS {
    tag "$meta.id"
    label 'process_single'
    // base_v2.1.0 - MUST manually change below (line 30)!!!
    container 'quay.io/jvhagey/phoenix@sha256:f0304fe170ee359efd2073dcdb4666dddb96ea0b79441b1d2cb1ddc794de4943'

    input:
    tuple val(meta), path(fastp_trimd_json), path(fastp_singles_json), path(raw_qc), path(fairy_outcome)
    val(busco_val)

    output:
    tuple val(meta), path('*_trimmed_read_counts.txt'),          emit: fastp_total_qc
    tuple val(meta), path('*_summary_trimmd.txt'),               emit: trimmd_outcome
    path('*_summaryline.tsv'),                                   optional:true, emit: summary_line
    tuple val(meta), path('*.synopsis'),                         optional:true, emit: synopsis
    path("versions.yml"),                                        emit: versions

    script: // This script is bundled with the pipeline, in cdcgov/phoenix/bin/
    // define variables
    def prefix = task.ext.prefix ?: "${meta.id}"
    def busco_parameter = busco_val ? "--busco" : ""
    def script_fastp = "FastP_QC.py"
    def script_fairy = "fairy.py"
    def script_trimmed = "get_trimmed_stats.py"
    """
    # create new summary
    cp $fairy_outcome ${prefix}_summary_trimmd.txt

    ${script_trimmed} \\
      --trimmed_json ${fastp_trimd_json} \\
      --single_json ${fastp_singles_json} \\
      --name ${prefix} \\
      -r ${raw_qc} \\
      -oTC ${prefix}_trimmed_read_counts.txt \\
      -oS ${prefix}_summary_trimmd.txt \\
      ${busco_parameter}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //g')
        fairy.py: \$( ${script_fairy} --version )
        FastP_QC.py: \$(${script_fastp} --version )
    END_VERSIONS
    """
}