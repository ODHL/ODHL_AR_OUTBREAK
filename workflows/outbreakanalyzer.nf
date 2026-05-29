/*
========================================================================================
    IMPORT LOCAL MODULES
========================================================================================
*/
include { CREATE_PHOENIX_SUMMARY            } from '../modules/local/create_phoenix_summary'
include { POST_PROCESS                      } from '../modules/local/post_process'
include { ID_DB                             } from '../modules/local/id_db'
include { NCBI_PREP                         } from '../modules/local/ncbi_prep'
include { NCBI_POST                         } from '../modules/local/ncbi_post'
include { REPORT_BASIC_PREP                 } from '../modules/local/report_basic_prep'
include { CFSAN                             } from '../modules/local/cfsan'
include { ROARY                             } from '../modules/local/roary'
include { IQTREE2                           } from '../modules/local/iqtree2'
include { REPORT_OUTBREAK_PREP              } from '../modules/local/report_outbreak_prep'
include { REPORT_OUTBREAK                   } from '../modules/local/report_outbreak'

/*
========================================================================================
    IMPORT LOCAL SUBWORKFLOWS
========================================================================================
*/
include { arANALYZER                        } from './aranalyzer'
include { CREATE_GFF_CHANNEL                } from '../subworkflows/local/create_gff_channel'

/*
========================================================================================
    RUN MAIN WORKFLOW
========================================================================================
*/
workflow outbreakANALYZER {
    take:
        ch_reads
        ch_versions
        samplesheet

    main:
        //////////////////////////////////////////////////////////////////
        // Params
        //////////////////////////////////////////////////////////////////
        projectID        = params.projectID
        outbreak_species = params.outbreak_species
        max_samples      = params.max_samples
        percent_id       = params.percent_id

        ch_ardb                  = Channel.fromPath(params.ardb)
        ch_snp_config            = Channel.fromPath(params.snp_config)
        ch_outbreak_RMD          = Channel.fromPath(params.outbreak_RMD)
        ch_config_arReport       = Channel.fromPath(params.config_arReport)
        ch_outbreak_metadata     = Channel.fromPath(params.outbreak_metadata)
        ch_id_db                 = Channel.fromPath(params.id_db)
        ch_basic_RMD             = Channel.fromPath(params.basic_RMD)
        ch_labResults            = Channel.fromPath(params.labResults)
        ch_metadata_NCBI         = Channel.fromPath(params.metadata_NCBI)
        ch_config_NCBI           = Channel.fromPath(params.config_NCBI)
        ch_output_NCBI           = Channel.fromPath(params.output_NCBI)
        ch_core_functions_script = Channel.fromPath(params.coreFunctions)
        ch_ref_samples           = Channel.fromPath(params.ref_samples)

        //////////////////////////////////////////////////////////////////
        // STEP 1: PER-SAMPLE ANALYSIS (arANALYZER)
        //////////////////////////////////////////////////////////////////
        arANALYZER(
            ch_reads,
            ch_versions
        )

        //////////////////////////////////////////////////////////////////
        // STEP 2: COMBINE SAMPLE SUMMARIES
        //////////////////////////////////////////////////////////////////
        all_summaries_ch = arANALYZER.out.line_summary.collect()

        CREATE_PHOENIX_SUMMARY(
            all_summaries_ch,
            params.runBUSCO
        )
        ch_versions = ch_versions.mix(CREATE_PHOENIX_SUMMARY.out.versions)

        //////////////////////////////////////////////////////////////////
        // STEP 3: POST PROCESS PIPELINE RESULTS
        //////////////////////////////////////////////////////////////////
        all_fastp_files    = arANALYZER.out.fastp_total_qc.map { meta, f -> f }.collect()
        all_synopsis_files = arANALYZER.out.pipeStats.map { meta, f -> f }.collect()
        all_files_ch       = all_fastp_files.concat(all_synopsis_files).collect()

        POST_PROCESS(
            all_files_ch,
            CREATE_PHOENIX_SUMMARY.out.summary_report,
            ch_core_functions_script,
            ch_labResults
        )
        ch_versions = ch_versions.mix(POST_PROCESS.out.versions)

        //////////////////////////////////////////////////////////////////
        // STEP 4: ID DATABASE LOOKUP
        //////////////////////////////////////////////////////////////////
        ID_DB(
            ch_core_functions_script,
            POST_PROCESS.out.quality_results,
            ch_id_db,
            projectID
        )
        ch_versions = ch_versions.mix(ID_DB.out.versions)

        //////////////////////////////////////////////////////////////////
        // STEP 5: NCBI PREP
        //////////////////////////////////////////////////////////////////
        if (!file("${params.outdir}/basespace").isDirectory()) {
            all_fastq_files_ncbi = Channel
                .fromPath("${projectDir}/test/fastq/*fastq.gz")
                .collect()
        } else {
            all_fastq_files_ncbi = Channel
                .fromPath("${params.outdir}/basespace/*fastq.gz")
                .collect()
        }

        NCBI_PREP(
            ch_core_functions_script,
            projectID,
            ch_metadata_NCBI,
            ch_config_NCBI,
            ch_id_db,
            POST_PROCESS.out.pipeline_results,
            ID_DB.out.wgs_results,
            all_fastq_files_ncbi
        )
        ch_versions = ch_versions.mix(NCBI_PREP.out.versions)

        //////////////////////////////////////////////////////////////////
        // STEP 6: NCBI POST (update with NCBI accessions)
        //////////////////////////////////////////////////////////////////
        NCBI_POST(
            projectID,
            ch_id_db,
            NCBI_PREP.out.ncbi_pre_file,
            ch_output_NCBI
        )
        ch_versions = ch_versions.mix(NCBI_POST.out.versions)

        //////////////////////////////////////////////////////////////////
        // STEP 7: REPORT BASIC PREP (produces final_report.csv + ar_predictions.tsv)
        //////////////////////////////////////////////////////////////////
        REPORT_BASIC_PREP(
            arANALYZER.out.geneFiles,
            NCBI_POST.out.ncbi_post_file,
            POST_PROCESS.out.pipeline_results,
            ch_basic_RMD,
            projectID,
            ch_config_arReport
        )

        //////////////////////////////////////////////////////////////////
        // STEP 8: OUTBREAK ANALYSIS - GFF / ROARY / IQTREE2
        //////////////////////////////////////////////////////////////////
        // Get the filtered sample list from GFF samplesheet
        CREATE_GFF_CHANNEL(samplesheet)
        ch_sampleList = CREATE_GFF_CHANNEL.out.sampleList.map { it.id }

        // Sample GFFs from arANALYZER prokka output, filtered to samplesheet
        ch_sample_gffs = arANALYZER.out.prokka_gff
            .map { meta, file -> [meta.id, file] }
            .join(ch_sampleList)
            .map { sample_id, file -> file }

        // Reference GFFs from reference database
        all_reference_gff = Channel
            .fromPath("${params.reference_outdir}/${outbreak_species}/gff/*gff")
            .map { file -> file }

        // Combine sample + reference GFFs, capped at max_samples
        ch_all_gffs = ch_sample_gffs.concat(all_reference_gff)
            .collect().map { collectedFiles ->
                collectedFiles.take(max_samples)
            }

        // Run ROARY for core genome
        ROARY(
            ch_all_gffs,
            percent_id
        )

        // Generate phylogenetic tree from core genome alignment
        IQTREE2(
            ROARY.out.aln
        )

        //////////////////////////////////////////////////////////////////
        // STEP 9: OUTBREAK ANALYSIS - FASTQ / CFSAN SNP
        //////////////////////////////////////////////////////////////////
        // Sample trimmed FASTQs from arANALYZER bbduk output, filtered to samplesheet
        ch_sample_fastqs = arANALYZER.out.bbduk_reads
            .map { meta, files -> [meta.id, files] }
            .join(ch_sampleList)
            .map { sample_id, files -> files }
            .flatten()

        // Reference FASTQs from reference database
        all_reference_fastqs = Channel
            .fromPath("${params.reference_outdir}/${outbreak_species}/bbduk/*fastq.gz")
            .map { file -> file }

        // Combine sample + reference FASTQs, capped at max_samples * 2 (R1+R2 per sample)
        ch_all_fastqs = ch_sample_fastqs.concat(all_reference_fastqs)
            .collect().map { collectedFiles ->
                collectedFiles.take(max_samples * 2)
            }

        // Run CFSAN SNP pipeline
        CFSAN(
            ch_all_fastqs,
            ch_ardb,
            ch_snp_config
        )

        //////////////////////////////////////////////////////////////////
        // STEP 10: OUTBREAK REPORT
        //////////////////////////////////////////////////////////////////
        ch_analyzer_results = REPORT_BASIC_PREP.out.finalReport.collect()
        ch_ar_predictions   = REPORT_BASIC_PREP.out.predictions.collect()

        REPORT_OUTBREAK_PREP(
            ch_config_arReport,
            ch_analyzer_results,
            CFSAN.out.distmatrix,
            IQTREE2.out.genome_tree,
            ROARY.out.core_genome_stats,
            ch_ar_predictions,
            ch_outbreak_metadata,
            projectID,
            ch_outbreak_RMD,
            ch_ref_samples
        )

        REPORT_OUTBREAK(
            ch_config_arReport,
            ch_analyzer_results,
            CFSAN.out.distmatrix,
            IQTREE2.out.genome_tree,
            ROARY.out.core_genome_stats,
            ch_ar_predictions,
            ch_outbreak_metadata,
            projectID,
            REPORT_OUTBREAK_PREP.out.projecOutbreakRMD,
            ch_ref_samples,
            REPORT_OUTBREAK_PREP.out.dbLookup
        )
}

/*
========================================================================================
    THE END
========================================================================================
*/
