process SPADES {
    tag "$meta.id"
    label 'process_high_memory'
    // v3.15.5
    container 'quay.io/staphb/spades@sha256:b33f57d65cb63d631c6e3ba9b2a1c5a11ff4351475f38a1108ec61a5bf430077'

    input:
    tuple val(meta), \
    path(reads), path(unpaired_reads), \
    path(k2_bh_summary), path(fastp_raw_qc), \
    path(fastp_total_qc), path(kraken2_trimd_report)

    output:
    tuple val(meta), path('*.contigs.fa.gz')              ,                emit: contigs // minimum to complete sucessfully
    tuple val(meta), path('*.log')                        ,                emit: log
    tuple val(meta), path("*_spades_outcome.csv")         ,                emit: spades_outcome
    tuple val(meta), path('*.scaffolds.fa.gz')            , optional:true, emit: scaffolds // possible that contigs could be created, but not scaffolds
    tuple val(meta), path('*.assembly.gfa.gz')            , optional:true, emit: gfa
    path("versions.yml")                                  ,                emit: versions

    script:
    // define variables
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def maxmem = task.memory.toGiga() // allow 4 less GB to provide enough space
    def input_reads = "-1 ${reads[0]} -2 ${reads[1]}"
    def single_reads = "-s $unpaired_reads"
    def phred_offset = "33"
    """
    if [[ -z \$(zcat $unpaired_reads) ]]; then
        spades.py \\
            $args \\
            --threads $task.cpus \\
            --memory $maxmem \\
            $input_reads \\
            --phred-offset $phred_offset\\
            -o spades/

    else
        spades.py \\
            $args \\
            --threads $task.cpus \\
            --memory $maxmem \\
            $single_reads \\
            $input_reads \\
            --phred-offset $phred_offset\\
            -o spades/
    fi

    # Create post processing log
    cp spades/spades.log ${prefix}.spades.log
    bash spades_post.sh -p $prefix
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        spades: \$(spades.py --version 2>&1 | sed 's/^.*SPAdes genome assembler v//; s/ .*\$//')
    END_VERSIONS    
    """
}
