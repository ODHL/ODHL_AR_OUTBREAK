//https://sanger-pathogens.github.io/Roary/
process ROARY {
    tag "ROARY"
    label 'process_high'
    container 'staphb/roary:3.12.0'
  
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