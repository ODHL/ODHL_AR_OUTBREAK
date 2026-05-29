//
// Subworkflow: Running srst2_MLST
//

include { MLST                           } from '../../modules/local/mlst'
include { CHECK_MLST                     } from '../../modules/local/check_mlst'

workflow DO_MLST {
    take:
        trimmed_assembly     // channel: tuple val(meta), path(assembly): BBMAP_REFORMAT.out.filtered_scaffolds
        scaffold_count_check // SCAFFOLD_COUNT_CHECK.out.outcome
        paired_reads         // channel: tuple val(meta), path(reads), path(paired_reads): FASTP_TRIMD.out.reads.map
        taxonomy             // channel: tuple val(meta), path(taxonomy): DETERMINE_TAXA_ID.out.taxonomy
        mlst_db              // MLST DB to use with torstens MLST program

    main:
        ch_versions = Channel.empty() // Used to collect the software versions

        // Creating channel to ensure ID is paired with matching trimmed assembly
        mlst_ch = trimmed_assembly.map{meta, fasta         -> [[id:meta.id], fasta]}\
            .join(scaffold_count_check.splitCsv(strip:true, by:5).map{meta, fairy_outcome -> [[id:meta.id], [fairy_outcome[0][0]]]}, by: [0])\
            .join(taxonomy.map{            meta, taxonomy      -> [[id:meta.id], taxonomy]}, by: [0]).combine(mlst_db)
        
        // Running standard mlst tool (torstens) on assembly file using provided mlst database location for scemes, profiles, and allele definitions
        MLST (
            mlst_ch
        )
        ch_versions = ch_versions.mix(MLST.out.versions)

        // Creating a channel to pair up the tsv output to the matching taxonomy file, linked on metadata ID
        check_main_mlst_ch = MLST.out.tsv.map{meta, tsv      -> [[id:meta.id], tsv]}\
        .join(taxonomy.map{                   meta, taxonomy -> [[id:meta.id], taxonomy]}, by: [0]).combine(mlst_db)

        // Checks to see if multiple schemes were found in the sample. Will create _combined.tsv with one ST profile found per line
        CHECK_MLST (
            check_main_mlst_ch
        )
        ch_versions = ch_versions.mix(CHECK_MLST.out.versions)

        checked_mlst_ch = CHECK_MLST.out.checked_MLSTs.map{meta, checked_MLSTs -> [ [id:meta.id], checked_MLSTs]}

    emit:
        checked_MLSTs = checked_mlst_ch
        versions      = ch_versions // channel: [ versions.yml ]
}