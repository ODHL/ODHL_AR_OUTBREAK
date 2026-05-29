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
    samplesheet_gff = file(params.input_gff)
    ch_versions  = Channel.empty()

    main:
        runBASESPACE = params.runBASESPACE.toBoolean()

        // Read and validate input samplesheet
        CREATE_INPUT_CHANNEL(
            samplesheet,
            runBASESPACE
        )
        ch_manifest = CREATE_INPUT_CHANNEL.out.reads

        // Conditional BaseSpace download
        if (runBASESPACE) {
            BASESPACE(ch_manifest)
            ch_reads = BASESPACE.out.reads
        } else {
            ch_reads = ch_manifest
        }

        // Run the combined outbreak analysis workflow
        outbreakANALYZER(
            ch_reads,
            ch_versions,
            samplesheet_gff
        )
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
