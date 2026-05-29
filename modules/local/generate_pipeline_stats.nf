process GENERATE_PIPELINE_STATS {
    tag "${meta.id}"
    label 'process_single'
    container 'quay.io/jvhagey/phoenix@sha256:f0304fe170ee359efd2073dcdb4666dddb96ea0b79441b1d2cb1ddc794de4943'

    input:
    tuple val(meta), path(rawStats), \
    path(fastp_total_qc), \
    path(krakenReport), \
    path(krona_trimd), \
    path(krakenBestHit), \
    path(renamedScaffolds), \
    path(bbmapFiltScaffolds), \
    path(mlstCheck), \
    path(gammaHV), \
    path(gammaAR), \
    path(gammaPF), \
    path(quastReport), \
    path(krona_weighted), \
    path(krakenReport_wtasmbld), \
    path(krakenBestHit_wtasmbld), \
    path(taxaID), \
    path(aniBestHit), \
    path(assembledRatio), \
    path(amrfinderMutationReport), \
    path(assembledGC)
    val(coverage)

    output:
    tuple val(meta), path('*.synopsis'), emit: pipeline_stats
    path("versions.yml")               , emit: versions

    script: // This script is bundled with the pipeline, in cdcgov/phoenix/bin/
    // define variables
    def prefix = task.ext.prefix            ?: "${meta.id}"
    """
    pipeline_stats_writer.sh \\
        -a $rawStats \
        -b $fastp_total_qc \
        -c $assembledGC \
        -d ${prefix} \
        -e $krakenReport \
        -f $krakenBestHit \
        -g "" \
        -h $renamedScaffolds \
        -i $bbmapFiltScaffolds \
        -m $krakenReport_wtasmbld \
        -n $krakenBestHit_wtasmbld \
        -o "" \
        -p $quastReport \
        -q $taxaID \
        -r $assembledRatio \
        -t $aniBestHit \
        -u $gammaAR \
        -v $gammaPF \
        -w $gammaHV \
        -y $mlstCheck \
        -4 $amrfinderMutationReport \
        -5 $coverage

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        script_version: v1.0
    END_VERSIONS
    """
}
