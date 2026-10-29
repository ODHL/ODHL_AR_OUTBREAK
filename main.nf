#!/usr/bin/env nextflow
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ODHL_AR_OUTBREAK Nextflow pipeline
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Github : https://github.com/ODHL/ODHL_AR_OUTBREAK
----------------------------------------------------------------------------------------
*/

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS / WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { outbreakANALYZER          } from './workflows/outbreakanalyzer'
include { CREATE_INPUT_CHANNEL      } from './subworkflows/local/create_input_channel'
include { PIPELINE_INITIALISATION   } from './subworkflows/local/utils_nfcore_odhlar_pipeline'
include { PIPELINE_COMPLETION       } from './subworkflows/local/utils_nfcore_odhlar_pipeline'
include { BASESPACE                 } from './modules/local/basespace'
include { NCBI_DOWNLOAD             } from './modules/local/ncbi_download'
include { GC_DOWNLOAD               } from './modules/local/gc_download'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    NAMED WORKFLOWS FOR PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// WORKFLOW: Full outbreak analysis — from raw reads to outbreak report (HTML + Rmd)
//
workflow OUTBREAK_ANALYZER {

    samplesheet  = file(params.input)
    ch_versions  = Channel.empty()

    main:
        runBASESPACE = params.runBASESPACE.toBoolean()
        runNCBI      = params.runNCBI.toBoolean()
        runGC        = params.runGC.toBoolean()

        // Read and validate input samplesheet
        CREATE_INPUT_CHANNEL(
            samplesheet,
            runBASESPACE
        )
        ch_manifest = CREATE_INPUT_CHANNEL.out.reads

        ch_basespace = ch_manifest.filter { item -> item[0].download_mode == 'basespace' }
        ch_ncbi      = ch_manifest.filter { item -> item[0].download_mode == 'ncbi' }
        ch_gc        = ch_manifest.filter { item -> item[0].download_mode == 'gc' }
        ch_local     = ch_manifest.filter { item -> item[0].download_mode == 'local' }

        BASESPACE(ch_basespace)
        NCBI_DOWNLOAD(ch_ncbi)
        GC_DOWNLOAD(ch_gc)

        // Strip download-only meta fields so downstream processes see only id
        ch_reads = ch_local.mix(
            BASESPACE.out.reads,
            NCBI_DOWNLOAD.out.reads,
            GC_DOWNLOAD.out.reads
        ).map { item -> [[id: item[0].id], item[1]] }

        // Run the combined outbreak analysis workflow
        outbreakANALYZER(
            ch_reads,
            ch_versions
        )
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
