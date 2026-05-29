process FASTP_SINGLES {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/fastp:0.23.4--h5f740d0_0' :
        'biocontainers/fastp:0.23.4--h5f740d0_0' }"
    
    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path('*.singles.fastq.gz')  , emit: reads
    tuple val(meta), path('*.json')              , emit: json
    tuple val(meta), path('*.html')              , emit: html
    tuple val(meta), path('*.log')               , emit: log
    path("versions.yml")                         , emit: versions
    tuple val(meta), path('*.merged.fastq.gz')   , optional:true, emit: reads_merged

    when:
    task.ext.when == null || task.ext.when

    script:
    // define variables
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    zcat ${reads[0]} ${reads[1]} > ${prefix}.cat_singles.fastq
    gzip "${prefix}.cat_singles.fastq"
        
    fastp \
        --in1 "${prefix}.cat_singles.fastq.gz" \
        --thread $task.cpus \
        --json "${prefix}_singles.fastp.json" \
        --html "${prefix}_singles.fastp.html" \
        --out1 "${prefix}.singles.fastq.gz" \
        $args \
        2> "${prefix}.fastp.log"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fastp: \$(fastp --version 2>&1 | sed -e "s/fastp //g")
    END_VERSIONS
    """
}