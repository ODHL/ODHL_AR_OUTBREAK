process AMRFINDERPLUS_RUN {
    tag "$meta.id"
    label 'process_medium'
    // 3.12.8-2024-01-31.1 - new
    container 'quay.io/staphb/ncbi-amrfinderplus@sha256:fc06f8739bcb2b0cecb3aacd48370a27a3590e54e0aeb19b8a53dcaa6cc8ae9b'

    input:
    tuple val(meta), path(nuc_fasta), val(organism_param), path(pro_fasta), path(gff)
    path(db)

    output:
    tuple val(meta), path("${meta.id}_all_genes.tsv"),                    emit: report
    tuple val(meta), path("${meta.id}_all_mutations.tsv"), optional:true, emit: mutation_report
    path("versions.yml")                                 ,                emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // use --organism
    if ( "${organism_param[0]}" != "No Match Found") {
        organism = "--organism ${organism_param[0]}"
    } else { organism = "" }
    
    // define variables
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    //get name of amrfinder database file
    db_name = db.toString() - '.tar.gz'
    """
    if [[ $nuc_fasta = *.gz ]]; then
        NUC_FNAME=\$(basename ${nuc_fasta} .gz)
        gzip -c -d $nuc_fasta > \$NUC_FNAME
    else
        NUC_FNAME = $nuc_fasta
    fi

    # decompress the amrfinder database
    tar xzvf $db

    amrfinder \\
        --nucleotide \$NUC_FNAME \\
        --protein $pro_fasta \\
        --gff $gff \\
        --annotation_format prokka \\
        --mutation_all ${prefix}_all_mutations.tsv \\
        $organism \\
        --plus \\
        --database $db_name \\
        --threads $task.cpus > ${prefix}_all_genes.tsv

    sed -i '1s/ /_/g' ${prefix}_all_genes.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        amrfinderplus: \$(amrfinder --version)
        amrfinderplus_db_version: \$(head $db_name/version.txt)
    END_VERSIONS
    """
}