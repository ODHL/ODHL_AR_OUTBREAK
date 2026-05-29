process CALCULATE_ASSEMBLY_RATIO {
    tag "$meta.id"
    label 'process_single'
    // base_v2.1.0 - MUST manually change below (line 27)!!!
    container 'quay.io/jvhagey/phoenix@sha256:f0304fe170ee359efd2073dcdb4666dddb96ea0b79441b1d2cb1ddc794de4943'

    input:
    tuple val(meta), path(taxa_file), path(quast_report)
    path(ncbi_database)

    output:
    tuple val(meta), path('*_Assembly_ratio_*.txt'), emit: ratio
    tuple val(meta), path('*_GC_content_*.txt')    , emit: gc_content
    path("versions.yml")                           , emit: versions

    script: // This script is bundled with the pipeline, in cdcgov/phoenix/bin/
    // define variables
    def prefix = task.ext.prefix ?: "${meta.id}"
    def container_version = "base_v2.1.0"
    """
    calculate_assembly_ratio.sh -d $ncbi_database -q $quast_report -x $taxa_file -s ${prefix}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        NCBI_Assembly_Stats_DB: $ncbi_database
        phoenix_base_container_tag: ${container_version}
    END_VERSIONS
    """
}
