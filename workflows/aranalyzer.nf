/*
========================================================================================
    VALIDATE INPUTS
========================================================================================
*/


/*
========================================================================================
    SETUP
========================================================================================
*/

// Groovy funtion to make [ meta.id, [] ] - just an empty channel
def create_empty_ch(input_for_meta) { // We need meta.id associated with the empty list which is why .ifempty([]) won't work
    meta_id = input_for_meta[0]
    output_array = [ meta_id, [] ]
    return output_array
}

/*
========================================================================================
    CONFIG FILES
========================================================================================
*/


/*
========================================================================================
    IMPORT LOCAL MODULES
========================================================================================
*/

include { ASSET_CHECK                       } from '../modules/local/asset_check'
include { CORRUPTION_CHECK                  } from '../modules/local/corruption_check'
include { GET_RAW_STATS                     } from '../modules/local/get_raw_stats'
include { BBDUK                             } from '../modules/local/bbduk'
include { FASTP as FASTP_TRIMD              } from '../modules/local/fastp'
include { FASTP_SINGLES                     } from '../modules/local/fastp_singles'
include { GET_TRIMD_STATS                   } from '../modules/local/get_trimd_stats'
include { FASTQC                            } from '../modules/local/fastqc'
include { GENERATE_PIPELINE_STATS_FAILURE   } from '../modules/local/generate_pipeline_stats_failure'
include { PHOENIX_SUMMARY_LINE_FAILURE      } from '../modules/local/phoenix_summary_line_failure'
include { RENAME_FASTA_HEADERS              } from '../modules/local/rename_fasta_headers'
include { BBMAP_REFORMAT                    } from '../modules/local/contig_less500'
include { SCAFFOLD_COUNT_CHECK              } from '../modules/local/fairy_scaffold_count_check'
include { GAMMA as GAMMA_HV                 } from '../modules/local/gamma'
include { GAMMA as GAMMA_AR                 } from '../modules/local/gamma'
include { GAMMA_S as GAMMA_PF               } from '../modules/local/gammas'
include { QUAST                             } from '../modules/local/quast'
include { PROKKA                            } from '../modules/local/prokka'
include { MASH_DIST                         } from '../modules/local/mash_distance'
include { DETERMINE_TOP_MASH_HITS           } from '../modules/local/determine_top_mash_hits'
include { FASTANI                           } from '../modules/local/fastani'
include { FORMAT_ANI                        } from '../modules/local/format_ANI'
include { DETERMINE_TAXA_ID                 } from '../modules/local/determine_taxa_id'
include { GET_TAXA_FOR_AMRFINDER            } from '../modules/local/get_taxa_for_amrfinder'
include { AMRFINDERPLUS_RUN                 } from '../modules/local/amrfinder'
include { CALCULATE_ASSEMBLY_RATIO          } from '../modules/local/assembly_ratio'
include { GENERATE_PIPELINE_STATS           } from '../modules/local/generate_pipeline_stats'
include { CREATE_PHOENIX_SUMMARY_LINE       } from '../modules/local/create_phoenix_summary_line'

/*
========================================================================================
    IMPORT LOCAL SUBWORKFLOWS
========================================================================================
*/

include { KRAKEN2_WF as KRAKEN2_TRIMD           } from '../subworkflows/local/kraken2'
include { SPADES_WF                             } from '../subworkflows/local/spades'
include { KRAKEN2_WF as KRAKEN2_WTASMBLD        } from '../subworkflows/local/kraken2'
include { DO_MLST                               } from '../subworkflows/local/do_mlst'

/*
========================================================================================
    IMPORT NF-CORE MODULES/SUBWORKFLOWS
========================================================================================
*/

//
// MODULE: Installed directly from nf-core/modules
//

/*
========================================================================================
    RUN MAIN WORKFLOW
========================================================================================
*/
workflow arANALYZER {
    take:
        ch_reads
        ch_versions

    main:
        // Allow relative paths for krakendb argument
        // ch_kraken2_db  = Channel.fromPath(params.kraken2_db, relative: true)

        // unzip any zipped databases
        ASSET_CHECK (
            params.zipped_sketch,
            params.custom_mlstdb,
            params.kraken2_db
        )
        ch_versions = ch_versions.mix(ASSET_CHECK.out.versions)
        ch_path_mash = ASSET_CHECK.out.mash_sketch
        ch_path_mlst = ASSET_CHECK.out.mlst_db
        ch_path_kraken = ASSET_CHECK.out.kraken2_db

        // fairy compressed file corruption check & generate read stats
        CORRUPTION_CHECK (
            ch_reads, 
            params.runBUSCO
        )
        ch_versions = ch_versions.mix(CORRUPTION_CHECK.out.versions)
        ch_corruptionStatus = CORRUPTION_CHECK.out.outcome
        ch_corruptionSummary = CORRUPTION_CHECK.out.summary_line

        // Combining reads with output of corruption check. By=2 is for getting R1 and R2 results
        read_stats_ch = ch_reads
            .join(ch_corruptionStatus, by: [0,0])
            .join(ch_corruptionStatus.splitCsv(strip:true, by:2)
            .map{meta, fairy_outcome -> [meta, [fairy_outcome[0][0], fairy_outcome[1][0]]]}, by: [0,0])
            .filter { it[3].findAll {!it.contains('FAILED')}}

        // Get stats on raw reads if the reads aren't corrupted
        GET_RAW_STATS (
            read_stats_ch, params.runBUSCO // false says no busco is being run
        )
        ch_versions = ch_versions.mix(GET_RAW_STATS.out.versions)
        ch_rawStatus = GET_RAW_STATS.out.raw_outcome
        ch_rawStats = GET_RAW_STATS.out.combined_raw_stats
        ch_rawSummary = GET_RAW_STATS.out.summary_line

        // Combining reads with output of corruption check
        bbduk_ch = ch_reads
            .join(ch_rawStatus.splitCsv(strip:true, by:3)
            .map{meta, fairy_outcome -> [meta, [fairy_outcome[0][0]]]}, by: [0,0])
            .filter { it[1].findAll {!it.contains('FAILED')}}

        // Remove PhiX reads
        BBDUK (
            bbduk_ch, params.bbdukdb
        )
        ch_versions = ch_versions.mix(BBDUK.out.versions)
        ch_bbdukReads = BBDUK.out.reads

        // Trim and remove low quality reads
        FASTP_TRIMD (
            ch_bbdukReads, 
            params.save_trimmed_fail, 
            params.save_merged
        )
        ch_versions = ch_versions.mix(FASTP_TRIMD.out.versions)
        ch_trimmedJson=FASTP_TRIMD.out.json
        ch_trmdReads=FASTP_TRIMD.out.reads
        ch_trmdFailed=FASTP_TRIMD.out.reads_fail

        // Rerun on unpaired reads to get stats, nothing removed
        FASTP_SINGLES (
            ch_trmdFailed
        )
        ch_versions = ch_versions.mix(FASTP_SINGLES.out.versions)
        ch_singlesJson=FASTP_SINGLES.out.json
        ch_singlesReads=FASTP_SINGLES.out.reads

        // Combining fastp json outputs based on meta.id
        fastp_json_ch = ch_trimmedJson.join(ch_singlesJson, by: [0,0])
        .join(ch_rawStats, by: [0,0])\
        .join(ch_corruptionStatus, by: [0,0])
        // Script gathers data from fastp jsons for pipeline stats file
        GET_TRIMD_STATS (
            fastp_json_ch, params.runBUSCO // false says no busco is being run
        )
        ch_versions = ch_versions.mix(GET_TRIMD_STATS.out.versions)
        ch_trimmd_outcome = GET_TRIMD_STATS.out.trimmd_outcome
        ch_fastp_total_qc = GET_TRIMD_STATS.out.fastp_total_qc
        ch_trimmd_summary = GET_TRIMD_STATS.out.summary_line
        ch_synopsis       = GET_TRIMD_STATS.out.synopsis

        // combing fastp_trimd information with fairy check of reads to confirm there are reads after filtering
        trimd_reads_file_integrity_ch = ch_trmdReads
            .join(ch_trimmd_outcome.splitCsv(strip:true, by:5)
            .map{meta, fairy_outcome -> [meta, [fairy_outcome[0][0], fairy_outcome[1][0], fairy_outcome[2][0]]]}, by: [0,0])
            .filter { it[2].findAll {!it.contains('FAILED')}}

        // Running Fastqc on trimmed reads
        FASTQC (
            trimd_reads_file_integrity_ch
        )
        ch_versions = ch_versions.mix(FASTQC.out.versions.first())

        // Checking for Contamination in trimmed reads, creating krona plots and best hit files
        // fasta           // channel: tuple (meta) path(read_R1, reads_R2) or tuple (meta) path(scaffolds)
        // fairy_check     // GET_RAW_STATS.out.outcome
        // type            // val: trimd, asmbld or wtasmbld 
        // qc_stats        //GATHERING_READ_QC_STATS.out.fastp_total_qc
        // kraken2_db_path
        KRAKEN2_TRIMD (
            ch_trmdReads, 
            ch_trimmd_outcome, 
            "trimd", 
            ch_fastp_total_qc, 
            ch_path_kraken
        )
        ch_versions = ch_versions.mix(KRAKEN2_TRIMD.out.versions)
        ch_krakenReport =  KRAKEN2_TRIMD.out.report
        ch_krakenBestHit = KRAKEN2_TRIMD.out.k2_bh_summary

        // single_reads      // channel: tuple val(meta), path(reads), path(single_reads): FASTP_SINGLES.out.reads
        // paired_reads      // channel: tuple val(meta), path(reads), path(paired_reads):FASTP_TRIMD.out.reads.map
        // fastp_total_qc    // channel: tuple (meta) path(fastp_total_qc): GATHERING_READ_QC_STATS.out.fastp_total_qc
        // fastp_raw_qc      // channel: tuple (meta) path(fastp_raw_qc): GATHERING_READ_QC_STATS.out.fastp_raw_qc
        // report            // channel: tuple (meta) path(report): KRAKEN2_TRIMD.out.report
        // k2_bh_summary     // channel: tuple (meta) path(k2_bh_summary): KRAKEN2_TRIMD.out.k2_bh_summary
        // Combining paired end reads and unpaired reads that pass QC filters, both get passed to Spades
        passing_reads_ch = ch_trmdReads.map{        meta, reads          -> [[id:meta.id],reads]}\
            .join(ch_singlesReads.map{              meta, reads          -> [[id:meta.id],reads]},          by: [0])\
            .join(ch_krakenBestHit.map{             meta, ksummary       -> [[id:meta.id],ksummary]},       by: [0])\
            .join(ch_rawStats.map{                  meta, fastp_raw_qc   -> [[id:meta.id],fastp_raw_qc]},   by: [0])\
            .join(ch_fastp_total_qc.map{            meta, fastp_total_qc -> [[id:meta.id],fastp_total_qc]}, by: [0])\
            .join(ch_krakenReport.map{              meta, report         -> [[id:meta.id],report]},         by: [0])

        SPADES_WF (
            passing_reads_ch,
            ch_krakenBestHit
        )
        ch_versions = ch_versions.mix(SPADES_WF.out.versions)
        ch_spadesOutcome = SPADES_WF.out.spades_outcome
        ch_taxaFailure = SPADES_WF.out.taxaFailure
        ch_spadesScaffolds = SPADES_WF.out.ch_spadesScaffolds.map{meta, scaffolds -> [ [id:meta.id, single_end:true], scaffolds]} 
        ch_spadesScaffolds = SPADES_WF.out.ch_spadesScaffolds

        // Generate pipeline stats for case when spades fails to create scaffolds
        pipeline_stats_ch = ch_rawStats.map     {  meta, fastp_raw_qc -> [[id: meta.id], fastp_raw_qc] }
            .join(ch_fastp_total_qc.map         {  meta, fastp_total_qc -> [[id: meta.id], fastp_total_qc]}, by: [0])
            .join(ch_krakenReport.map           {  meta, report -> [[id: meta.id], report] }, by: [0])
            .join(ch_krakenBestHit.map          {  meta, ksummary -> [[id: meta.id], ksummary] }, by: [0])
            .join(ch_taxaFailure.map            {  meta, taxonomy -> [[id: meta.id], taxonomy] }, by: [0])
            .join(ch_spadesOutcome.splitCsv(strip: true).map { meta, spades_outcome -> [[id: meta.id], spades_outcome] }, by: [0])
        
        GENERATE_PIPELINE_STATS_FAILURE (
            pipeline_stats_ch, 
            params.coverage
        )
        ch_versions = ch_versions.mix(GENERATE_PIPELINE_STATS_FAILURE.out.versions)

        // Create one line summary for case when spades fails to create scaffolds
        line_summary_ch = GENERATE_PIPELINE_STATS_FAILURE.out.pipeline_stats.map { meta, pipeline_stats -> [[id: meta.id], pipeline_stats]}
            .join(ch_fastp_total_qc.map {                                   meta, fastp_total_qc -> [[id: meta.id], fastp_total_qc]}, by: [0])
            .join(ch_krakenBestHit.map {                                    meta, ksummary -> [[id: meta.id], ksummary]}, by: [0])
            .join(ch_taxaFailure.map {                                      meta, taxonomy -> [[id: meta.id], taxonomy]}, by: [0])
            .join(ch_spadesOutcome.splitCsv(strip: true).map {              meta, spades_outcome -> [[id: meta.id], spades_outcome]}, by: [0])

        PHOENIX_SUMMARY_LINE_FAILURE (
            line_summary_ch
        )
        ch_versions = ch_versions.mix(PHOENIX_SUMMARY_LINE_FAILURE.out.versions)
        line_summary = PHOENIX_SUMMARY_LINE_FAILURE.out.line_summary

        // Rename scaffold headers
        RENAME_FASTA_HEADERS (
            ch_spadesScaffolds
        )
        ch_versions = ch_versions.mix(RENAME_FASTA_HEADERS.out.versions)
        ch_renamedScaffolds = RENAME_FASTA_HEADERS.out.renamed_scaffolds

        // Removing scaffolds <500bp
        BBMAP_REFORMAT (
            ch_renamedScaffolds
        )
        ch_versions             = ch_versions.mix(BBMAP_REFORMAT.out.versions)
        ch_bbmapLog             = BBMAP_REFORMAT.out.log
        ch_bbmapFiltScaffolds   = BBMAP_REFORMAT.out.filtered_scaffolds

        // Combine bbmap log with the fairy outcome file
        scaffold_check_ch = ch_bbmapLog.map{    meta, log                -> [[id:meta.id], log]}\
            .join(ch_trimmd_outcome.map{        meta, outcome            -> [[id:meta.id], outcome]},    by: [0])\
            .join(ch_rawStats.map{              meta, combined_raw_stats -> [[id:meta.id], combined_raw_stats]}, by: [0])\
            .join(ch_fastp_total_qc.map{        meta, fastp_total_qc     -> [[id:meta.id], fastp_total_qc]},     by: [0])\
            .join(ch_krakenReport.map{          meta, report             -> [[id:meta.id], report]},             by: [0])\
            .join(ch_krakenBestHit.map{         meta, k2_bh_summary      -> [[id:meta.id], k2_bh_summary]},      by: [0])

        // Checking that there are still scaffolds left after filtering
        SCAFFOLD_COUNT_CHECK (
            scaffold_check_ch, 
            params.coverage, 
            params.nodes, 
            params.names
        )
        ch_versions        = ch_versions.mix(SCAFFOLD_COUNT_CHECK.out.versions)
        ch_scaffoldOutcome = SCAFFOLD_COUNT_CHECK.out.outcome
        ch_scaffoldSummary = SCAFFOLD_COUNT_CHECK.out.summary_line

    // Resume's can cause single:true to join in the channel
    // This ensure it stays the same str regardless of re-runs
    cleaned_ch_scaffoldOutcome = ch_scaffoldOutcome.map { meta, file ->
        def cleaned_meta = meta.findAll { it.key != 'single_end' }  // Remove 'single_end' key
        return [cleaned_meta, file]  // Return cleaned metadata with file
    }

    // Join with ch_scaffoldOutcome using ID
    ch_filtered_scaffolds = ch_bbmapFiltScaffolds.join(
        cleaned_ch_scaffoldOutcome, by: 0
        ).filter { entry -> 
            def scaffold_file = file(entry[2])  // Ensure it's treated as a file
            scaffold_file.exists() && scaffold_file.text.readLines().any { it.contains('PASSED: More than 0 scaffolds') }
        }

    // Running gamma to identify hypervirulence genes in scaffolds
    GAMMA_HV (
        ch_filtered_scaffolds, 
        params.hvgamdb
    )
    ch_versions = ch_versions.mix(GAMMA_HV.out.versions)
    ch_gammaHV = GAMMA_HV.out.gamma

    // Running gamma to identify AR genes in scaffolds
    GAMMA_AR (
        ch_filtered_scaffolds, 
        params.ardb
    )
    ch_versions = ch_versions.mix(GAMMA_AR.out.versions)
    ch_gammaAR = GAMMA_AR.out.gamma

    GAMMA_PF (
        ch_filtered_scaffolds, 
        params.gamdbpf
    )
    ch_versions = ch_versions.mix(GAMMA_PF.out.versions)
    ch_gammaPF = GAMMA_PF.out.gamma

    // Getting Assembly Stats
    QUAST (
        ch_filtered_scaffolds
    )
    ch_versions = ch_versions.mix(QUAST.out.versions)
    ch_quastReport = QUAST.out.report_tsv

    // get gff and protein files for amrfinder+
    PROKKA (
        ch_filtered_scaffolds
    )
    ch_versions = ch_versions.mix(PROKKA.out.versions)
    ch_prokkaFAA = PROKKA.out.faa
    ch_prokkaGFF = PROKKA.out.gff

    // Creating krona plots and best hit files for weighted assembly
    // fasta           // channel: tuple (meta) path(read_R1, reads_R2) or tuple (meta) path(scaffolds)
    // fairy_check     // GET_RAW_STATS.out.outcome or SCAFFOLD_COUNT_CHECK.out.outcome
    // type            // val: trimd, asmbld or wtasmbld 
    // qc_stats        //GATHERING_READ_QC_STATS.out.fastp_total_qc
    // kraken2_db_path
    KRAKEN2_WTASMBLD (
        ch_bbmapFiltScaffolds, 
        ch_filtered_scaffolds, 
        "wtasmbld", 
        ch_quastReport, 
        ch_path_kraken
    )
    ch_versions = ch_versions.mix(KRAKEN2_WTASMBLD.out.versions)
    ch_krakenReport_wtasmbld = KRAKEN2_WTASMBLD.out.report
    ch_krakenBestHit_wtasmbld = KRAKEN2_WTASMBLD.out.k2_bh_summary

    // Running Mash distance to get top 20 matches for fastANI to speed things up
    mash_dist_ch = ch_filtered_scaffolds.combine(ch_path_mash)
    MASH_DIST (
        mash_dist_ch
    )
    ch_versions = ch_versions.mix(MASH_DIST.out.versions)
    ch_mashDist = MASH_DIST.out.dist
        
    // Combining mash dist with filtered scaffolds and the outcome of the scaffolds count check based on meta.id
    // pull out any single:true
    cleaned_ch = ch_mashDist.map { meta, file1 ->
        def cleaned_meta = meta.findAll { it.key != 'single_end' }  // Remove 'single_end'
        return [cleaned_meta, file1]
    }
    top_mash_hits_ch=cleaned_ch.join(ch_bbmapFiltScaffolds)

    // Generate file with list of paths of top taxa for fastANI
    DETERMINE_TOP_MASH_HITS (
        top_mash_hits_ch
    )
    ch_versions = ch_versions.mix(DETERMINE_TOP_MASH_HITS.out.versions)
    mash_topList_ch = DETERMINE_TOP_MASH_HITS.out.top_taxa_list
    mash_refDir_ch = DETERMINE_TOP_MASH_HITS.out.reference_dir

    // Combining filtered scaffolds with the top taxa list based on meta.id
    top_taxa_list_ch = ch_bbmapFiltScaffolds.map{meta, filtered_scaffolds -> [[id:meta.id], filtered_scaffolds]}\
        .join(mash_topList_ch.map{              meta, top_taxa_list      -> [[id:meta.id], top_taxa_list ]}, by: [0])\
        .join(mash_refDir_ch.map{              meta, reference_dir      -> [[id:meta.id], reference_dir ]}, by: [0])

    // Getting species ID
    FASTANI (
        top_taxa_list_ch
    )
    ch_versions = ch_versions.mix(FASTANI.out.versions)
    ch_fastaniAni = FASTANI.out.ani

    // Reformat ANI headers
    FORMAT_ANI (
        ch_fastaniAni
    )
    ch_versions = ch_versions.mix(FORMAT_ANI.out.versions)
    ch_aniBestHit = FORMAT_ANI.out.ani_best_hit

    // Combining weighted kraken report with the FastANI hit based on meta.id
    best_hit_ch = ch_krakenBestHit_wtasmbld.map{    meta, k2_bh_summary -> [[id:meta.id], k2_bh_summary]}\
        .join(ch_aniBestHit.map{                    meta, ani_best_hit  -> [[id:meta.id], ani_best_hit ]},  by: [0])\
        .join(ch_krakenBestHit.map{                 meta, k2_bh_summary -> [[id:meta.id], k2_bh_summary ]}, by: [0])

    // Getting ID from either FastANI or if fails, from Kraken2
    DETERMINE_TAXA_ID (
        best_hit_ch, 
        params.nodes, 
        params.names
    )
    ch_versions = ch_versions.mix(DETERMINE_TAXA_ID.out.versions)
    ch_taxaID = DETERMINE_TAXA_ID.out.taxonomy

    // Perform MLST steps on isolates (with srst2 on internal samples)
    // ch_bbmapFiltScaffolds    // channel: tuple val(meta), path(assembly): BBMAP_REFORMAT.out.filtered_scaffolds
    // ch_scaffoldOutcome       // SCAFFOLD_COUNT_CHECK.out.outcome
    // ch_trmdReads             // channel: tuple val(meta), path(reads), path(paired_reads): FASTP_TRIMD.out.reads.map
    // ch_taxaID                // channel: tuple val(meta), path(taxonomy): DETERMINE_TAXA_ID.out.taxonomy
    // ch_path_mlst             // MLST DB to use with torstens MLST program
    DO_MLST (
        ch_bbmapFiltScaffolds, \
        ch_scaffoldOutcome, \
        ch_trmdReads, \
        ch_taxaID, \
        ch_path_mlst
    )
    ch_versions = ch_versions.mix(DO_MLST.out.versions)
    ch_mlstCheck = DO_MLST.out.checked_MLSTs

    // Create file that has the organism name to pass to AMRFinder
    GET_TAXA_FOR_AMRFINDER (
        ch_taxaID
    )
    ch_versions = ch_versions.mix(GET_TAXA_FOR_AMRFINDER.out.versions)
    ch_amrfinderTaxa = GET_TAXA_FOR_AMRFINDER.out.amrfinder_taxa

    // Combining taxa and scaffolds to run amrfinder and get the point mutations.
    amr_channel = ch_bbmapFiltScaffolds.map{            meta, reads             -> [[id:meta.id], reads]}\
        .join(ch_amrfinderTaxa.splitCsv(strip:true).map{meta, amrfinder_taxa    -> [[id:meta.id], amrfinder_taxa ]}, by: [0])\
        .join(ch_prokkaFAA.map{                         meta, faa               -> [[id:meta.id], faa ]},            by: [0])\
        .join(ch_prokkaGFF.map{                         meta, gff               -> [[id:meta.id], gff ]},            by: [0])

    // Run AMRFinder
    AMRFINDERPLUS_RUN (
        amr_channel, 
        params.amrfinder_db
    )
    ch_amrfinderReport          = AMRFINDERPLUS_RUN.out.report.map { it[1] }.collect()
    ch_amrfinderMutationReport  = AMRFINDERPLUS_RUN.out.mutation_report
    ch_versions                 = ch_versions.mix(AMRFINDERPLUS_RUN.out.versions)
        
    // Combining determined taxa with the assembly stats based on meta.id
    assembly_ratios_ch = ch_taxaID.map{meta, taxonomy   -> [[id:meta.id], taxonomy]}\
        .join(ch_quastReport.map{                         meta, report_tsv -> [[id:meta.id], report_tsv]}, by: [0])

    // Calculating the assembly ratio and gather GC% stats
    CALCULATE_ASSEMBLY_RATIO (
        assembly_ratios_ch, 
        params.ncbi_assembly_stats
    )
    ch_versions = ch_versions.mix(CALCULATE_ASSEMBLY_RATIO.out.versions)
    ch_assembledRatio = CALCULATE_ASSEMBLY_RATIO.out.ratio
    ch_assembledGC = CALCULATE_ASSEMBLY_RATIO.out.gc_content

    // Prepare all the samples for the stats report
    empty_results = ch_rawStats.map{ it -> create_empty_ch(it) }
    pipeline_stats_ch = ch_rawStats.map{      meta, ch_rawStats                 -> [[id:meta.id],ch_rawStats]}\
        .join(ch_fastp_total_qc.map{          meta, ch_fastp_total_qc           -> [[id:meta.id],ch_fastp_total_qc]},           by: [0])\
        .join(ch_krakenReport.map{            meta, ch_krakenReport             -> [[id:meta.id],ch_krakenReport]},             by: [0])\
        .join(empty_results.map{              meta, empty_results               -> [[id:meta.id],empty_results]},               by: [0])\
        .join(ch_krakenBestHit.map{           meta, ch_krakenBestHit            -> [[id:meta.id],ch_krakenBestHit]},            by: [0])\
        .join(ch_renamedScaffolds.map{        meta, ch_renamedScaffolds         -> [[id:meta.id],ch_renamedScaffolds]},         by: [0])\
        .join(ch_bbmapFiltScaffolds.map{      meta, ch_bbmapFiltScaffolds       -> [[id:meta.id],ch_bbmapFiltScaffolds]},       by: [0])\
        .join(ch_mlstCheck.map{               meta, ch_mlstCheck                -> [[id:meta.id],ch_mlstCheck]},                by: [0])\
        .join(ch_gammaHV.map{                 meta, ch_gammaHV                  -> [[id:meta.id],ch_gammaHV]},                  by: [0])\
        .join(ch_gammaAR.map{                 meta, ch_gammaAR                  -> [[id:meta.id],ch_gammaAR]},                  by: [0])\
        .join(ch_gammaPF.map{                 meta, ch_gammaPF                  -> [[id:meta.id],ch_gammaPF]},                  by: [0])\
        .join(ch_quastReport.map{             meta, ch_quastReport              -> [[id:meta.id],ch_quastReport]},              by: [0])\
        .join(empty_results.map{              meta, empty_results               -> [[id:meta.id],empty_results]},               by: [0])\
        .join(ch_krakenReport_wtasmbld.map{   meta, ch_krakenReport_wtasmbld    -> [[id:meta.id],ch_krakenReport_wtasmbld]},    by: [0])\
        .join(ch_krakenBestHit_wtasmbld.map{  meta, ch_krakenBestHit_wtasmbld   -> [[id:meta.id],ch_krakenBestHit_wtasmbld]},   by: [0])\
        .join(ch_taxaID.map{                  meta, ch_taxaID                   -> [[id:meta.id],ch_taxaID]},                   by: [0])\
        .join(ch_aniBestHit.map{              meta, ch_aniBestHit               -> [[id:meta.id],ch_aniBestHit]},               by: [0])\
        .join(ch_assembledRatio.map{          meta, ch_assembledRatio           -> [[id:meta.id],ch_assembledRatio]},           by: [0])\
        .join(ch_amrfinderMutationReport.map{ meta, ch_amrfinderMutationReport  -> [[id:meta.id],ch_amrfinderMutationReport]},  by: [0])\
        .join(ch_assembledGC.map{             meta, ch_assembledGC              -> [[id:meta.id],ch_assembledGC]},              by: [0])

    // Generate the stats report
    GENERATE_PIPELINE_STATS (
        pipeline_stats_ch, 
        params.coverage
    )
    ch_versions = ch_versions.mix(GENERATE_PIPELINE_STATS.out.versions)
    ch_pipeStats = GENERATE_PIPELINE_STATS.out.pipeline_stats

    // Combining output based on meta.id to create summary by sample -- is this verbose, ugly and annoying? yes, if anyone has a slicker way to do this we welcome the input.
    line_summary_ch = ch_fastp_total_qc.map{            meta, fastp_total_qc  -> [[id:meta.id], fastp_total_qc]}\
        .join(ch_mlstCheck.map{                         meta, checked_MLSTs   -> [[id:meta.id], checked_MLSTs]},   by: [0])\
        .join(ch_gammaHV.map{                           meta, gamma           -> [[id:meta.id], gamma]},           by: [0])\
        .join(ch_gammaAR.map{                           meta, gamma           -> [[id:meta.id], gamma]},           by: [0])\
        .join(ch_gammaPF.map{                           meta, gamma           -> [[id:meta.id], gamma]},           by: [0])\
        .join(ch_quastReport.map{                       meta, report_tsv      -> [[id:meta.id], report_tsv]},      by: [0])\
        .join(ch_assembledRatio.map{                    meta, ratio           -> [[id:meta.id], ratio]},           by: [0])\
        .join(ch_pipeStats.map{                         meta, pipeline_stats  -> [[id:meta.id], pipeline_stats]},  by: [0])\
        .join(ch_taxaID.map{                            meta, taxonomy        -> [[id:meta.id], taxonomy]},        by: [0])\
        .join(ch_krakenBestHit.map{                     meta, k2_bh_summary   -> [[id:meta.id], k2_bh_summary]},   by: [0])\
        .join(ch_amrfinderMutationReport.map{           meta, report          -> [[id:meta.id], report]},          by: [0])\
        .join(ch_aniBestHit.map{                        meta, ani_best_hit    -> [[id:meta.id], ani_best_hit]},    by: [0])
        
    // Generate summary per sample that passed SPAdes
    CREATE_PHOENIX_SUMMARY_LINE (
        line_summary_ch
    )
    ch_versions = ch_versions.mix(CREATE_PHOENIX_SUMMARY_LINE.out.versions)
    ch_line_summary = CREATE_PHOENIX_SUMMARY_LINE.out.line_summary
    
    emit:
        fastp_total_qc       = ch_fastp_total_qc
        geneFiles            = ch_amrfinderReport
        line_summary         = ch_line_summary
        pipeStats            = ch_pipeStats
        prokka_gff           = ch_prokkaGFF
        bbduk_reads          = ch_bbdukReads
        versions             = ch_versions
}

/*
========================================================================================
    COMPLETION EMAIL AND SUMMARY
========================================================================================
*/

/*
========================================================================================
    THE END
========================================================================================
*/
