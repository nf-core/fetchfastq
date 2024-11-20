#!/usr/bin/env nextflow
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    nf-core/fetchngs
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Github : https://github.com/nf-core/fetchngs
    Website: https://nf-co.re/fetchngs
    Slack  : https://nfcore.slack.com/channels/fetchngs
----------------------------------------------------------------------------------------
*/

nextflow.preview.types = true

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / WORKFLOWS / TYPES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { SRA                     } from './workflows/sra'
include { PIPELINE_INITIALISATION } from './subworkflows/local/utils_nfcore_fetchngs_pipeline'
include { PIPELINE_COMPLETION     } from './subworkflows/local/utils_nfcore_fetchngs_pipeline'
include { SOFTWARE_VERSIONS       } from './subworkflows/nf-core/utils_nfcore_pipeline'
include { DownloadMethod          } from './workflows/sra'
include { SraParams               } from './workflows/sra'
include { Sample                  } from './workflows/sra'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    WORKFLOW INPUTS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

params {

    // TODO: declare as Set<SraId> and construct SraId with isSraId()
    input: Set<String> {
        description 'Set of SRA/ENA/GEO/DDBJ identifiers to download their associated metadata and FastQ files'
    }

    // TODO: declare as EnaMetadataFields and construct with sraCheckENAMetadataFields()
    ena_metadata_fields: String {
        description "Comma-separated list of ENA metadata fields to fetch before downloading data."
        help "The default list of fields used by the pipeline can be found at the top of the [`bin/sra_ids_to_runinfo.py`](https://github.com/nf-core/fetchngs/blob/master/bin/sra_ids_to_runinfo.py) script within the pipeline repo. This pipeline requires a minimal set of fields to download FastQ files i.e. `'run_accession,experiment_accession,library_layout,fastq_ftp,fastq_md5'`. Full list of accepted metadata fields can be obtained from the [ENA API](https://www.ebi.ac.uk/ena/portal/api/returnFields?dataPortal=ena&format=tsv&result=read_run)."
        icon 'fas fa-columns'
        defaultValue ''
    }

    download_method: DownloadMethod {
        description "Method to download FastQ files. Available options are 'aspera', 'ftp' or 'sratools'. Default is 'ftp'."
        help 'FTP and Aspera CLI download FastQ files directly from the ENA FTP whereas sratools uses sra-tools to download *.sra files and convert to FastQ.'
        icon 'fas fa-download'
        defaultValue 'ftp'
    }

    skip_fastq_download: boolean {
        description "Only download metadata for public data database ids and don't download the FastQ files."
        icon 'fas fa-fast-forward'
    }

    dbgap_key: Path? {
        description 'dbGaP repository key.'
        help 'Path to a JWT cart file used to access protected dbGAP data on SRA using the sra-toolkit. Users with granted access to controlled data can download the JWT cart file for the study from the SRA Run Selector upon logging in. The JWT file can only be used on cloud platforms and is valid for 1 hour upon creation.'
        icon 'fas fa-address-card'
    }

    // TODO: ...

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow {

    main:
    //
    // SUBWORKFLOW: Run initialisation tasks
    //
    PIPELINE_INITIALISATION (
        params.version,
        params.help,
        params.validate_params,
        params.monochrome_logs,
        args,
        workflow.outputDir
    )

    //
    // WORKFLOW: Run primary workflows for the pipeline
    //
    samples = SRA (
        Channel.fromList(params.input),
        SraParams(
            params.ena_metadata_fields,
            params.download_method,
            params.skip_fastq_download,
            params.dbgap_key
        )
    )

    //
    // SUBWORKFLOW: Collect software versions
    //
    versions = SOFTWARE_VERSIONS()

    //
    // SUBWORKFLOW: Run completion tasks
    //
    PIPELINE_COMPLETION (
        params.email,
        params.email_on_fail,
        params.plaintext_email,
        workflow.outputDir,
        params.monochrome_logs,
        params.hook_url
    )

    publish:
    samples >> 'samples'
    versions >> 'versions'
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    WORKFLOW OUTPUTS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

output {
    samples: Sample {
        path { _sample ->
            def dirs = [
                'fastq': 'fastq',
                'md5': 'fastq/md5'
            ]
            return { file -> "${dirs[file.ext]}/${file.baseName}" }
        }
        index {
            path 'samplesheet/samplesheet.json'
            sort { sample -> sample.id }
        }
    }

    versions: Map<String,Map<String,String>> {
        path '.'
        index {
            path 'nf_core_fetchngs_software_mqc_versions.yml'
        }
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
