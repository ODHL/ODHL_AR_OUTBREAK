//
// Subworkflow: Running SPAdes and checking if spades failed to create scaffolds
//

include { SPADES                               } from '../../modules/local/spades'
include { DETERMINE_TAXA_ID_FAILURE            } from '../../modules/local/determine_taxa_id_failure'

workflow SPADES_WF {
    take:
        ch_passing_reads
        ch_krakenBestHit
        
    main:
        ch_versions = Channel.empty() // Used to collect the software versions

        // Add in full path to outdir into the channel so each sample has a the path to go with it. 
        // If you don't do this then only one sample goes through pipeline

        // Assemblying into scaffolds by passing filtered paired in reads and unpaired reads
        SPADES (
            ch_passing_reads
        )
        ch_versions = ch_versions.mix(SPADES.out.versions)
        ch_spadesOutcome = SPADES.out.spades_outcome
        ch_spadesScaffolds = SPADES.out.scaffolds

        // Combining weighted kraken report with the FastANI hit based on meta.id
        ch_bestHit = ch_krakenBestHit.map{                         meta, ksummary       -> [[id:meta.id], ksummary]}\
            .join(ch_spadesOutcome.splitCsv(strip:true).map{        meta, spades_outcome -> [[id:meta.id], spades_outcome]})

        // Getting ID from either FastANI or if fails, from Kraken2
        DETERMINE_TAXA_ID_FAILURE (
            ch_bestHit, 
            params.nodes, 
            params.names
        )
        ch_versions = ch_versions.mix(DETERMINE_TAXA_ID_FAILURE.out.versions)
        ch_taxaFailure = DETERMINE_TAXA_ID_FAILURE.out.taxonomy
        
    emit:
        spades_outcome              = ch_spadesOutcome
        ch_spadesScaffolds          = ch_spadesScaffolds
        taxaFailure                 = ch_taxaFailure
        versions                    = ch_versions // channel: [ versions.yml ]

}