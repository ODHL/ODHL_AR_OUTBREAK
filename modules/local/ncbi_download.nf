process NCBI_DOWNLOAD {
    tag "${meta.id}"
    label 'process_low'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/sra-tools:3.1.0--h4304569_1' :
        'quay.io/biocontainers/sra-tools:3.1.0--h4304569_1' }"

    input:
    tuple val(meta)

    output:
    tuple val(clean_meta), path("*.fastq.gz"), emit: reads

    script:
    def srr = meta.srr_id instanceof List ? meta.srr_id[0] : meta.srr_id
    def id = meta.id instanceof List ? meta.id[0] : "${meta.id}".replaceAll(/[\[\]]/, '')
    def prefix = task.ext.prefix ?: id

    // Create cleaned metadata to pass downstream
    clean_meta = meta.clone()
    clean_meta.id = id
    clean_meta.srr_id = srr
    """
    fasterq-dump --split-files --threads ${task.cpus} ${srr}
    gzip ${srr}_1.fastq
    gzip ${srr}_2.fastq
    mv ${srr}_1.fastq.gz ${prefix}_1.fastq.gz
    mv ${srr}_2.fastq.gz ${prefix}_2.fastq.gz
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.R1.fastq.gz
    touch ${prefix}.R2.fastq.gz
    """
}
