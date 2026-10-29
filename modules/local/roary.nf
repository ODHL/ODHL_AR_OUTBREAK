//https://sanger-pathogens.github.io/Roary/
process ROARY {
    tag "ROARY"
    label 'process_high'
    container 'staphb/roary@sha256:4fb621c491ea5d0fd5193ea468353e7788c89709c6d9987412b62ec9faeee63b'
  
    input:
    path(gff)
    val(percent_id)

    output:
    path('*.aln')                                 , emit: aln
    path('*core_genome_statistics.txt')           , emit: core_genome_stats
    path('*gene_presence_absence.csv')            , emit: present_absence

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    roary -e --mafft -p $task.cpus -i ${percent_id} ${gff}
    mv summary_statistics.txt core_genome_statistics.txt
    """
}