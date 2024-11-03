/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT LOCAL MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { MULTIQC_MAPPINGS_CONFIG } from '../../modules/local/multiqc_mappings_config'
include { SRA_FASTQ_FTP           } from '../../modules/local/sra_fastq_ftp'
include { SRA_IDS_TO_RUNINFO      } from '../../modules/local/sra_ids_to_runinfo'
include { SRA_RUNINFO_TO_FTP      } from '../../modules/local/sra_runinfo_to_ftp'
include { ASPERA_CLI              } from '../../modules/local/aspera_cli'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT NF-CORE SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { FASTQ_DOWNLOAD_PREFETCH_FASTERQDUMP_SRATOOLS } from '../../subworkflows/nf-core/fastq_download_prefetch_fasterqdump_sratools'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow SRA {

    take:
    ids                         : Channel<String>
    params                      : SraParams

    main:
    ids                                                         // Channel<String>
        //
        // MODULE: Get SRA run information for public database ids
        //
        |> map { id ->
            SRA_IDS_TO_RUNINFO ( id, params.ena_metadata_fields )
        }                                                       // Channel<Path>
        //
        // MODULE: Parse SRA run information, create file containing FTP links and read into workflow as [ meta, [reads] ]
        //
        |> map(SRA_RUNINFO_TO_FTP)                              // Channel<Path>
        |> set { runinfo_ftp }                                  // Channel<Path>
        |> flatMap { tsv ->
            splitCsv(tsv, header:true, sep:'\t')
        }                                                       // Channel<Map>
        |> map { meta ->
            meta + [single_end: meta.single_end.toBoolean()]
        }                                                       // Channel<Map>
        |> unique                                               // Channel<Map>
        |> set { sra_metadata }                                 // Channel<Map>

    //
    // MODULE: If FTP link is provided in run information then download FastQ directly via FTP and validate with md5sums
    //
    sra_metadata
        |> filter { meta ->
            !skip_fastq_download && getDownloadMethod(meta, params.download_method) == 'ftp'
        }                                                   // Channel<Map>
        |> map { meta ->
            let fastq = [ file(meta.fastq_1), file(meta.fastq_2) ]
            let out = SRA_FASTQ_FTP ( meta, fastq, params.sra_fastq_ftp_args )
            new Sample(out.meta, out.fastq, out.md5)
        }                                                   // Channel<Sample>
        |> set { ftp_samples }                              // Channel<Sample>

    //
    // SUBWORKFLOW: Download sequencing reads without FTP links using sra-tools.
    //
    sra_metadata
        |> filter { meta ->
            !skip_fastq_download && getDownloadMethod(meta, params.download_method) == 'sratools'
        }                                                   // Channel<Map>
        |> FASTQ_DOWNLOAD_PREFETCH_FASTERQDUMP_SRATOOLS (
            params.dbgap_key ? file(params.dbgap_key, checkIfExists: true) : null,
            params.sratools_fasterqdump_args,
            params.sratools_pigz_args )                     // Channel<ProcessOut(meta: Map, fastq: List<Path>)>
        |> map { out ->
            new Sample(out.meta, out.fastq, [])
        }                                                   // Channel<Sample>
        |> set { sratools_samples }                         // Channel<Sample>

    //
    // MODULE: If Aspera link is provided in run information then download FastQ directly via Aspera CLI and validate with md5sums
    //
    sra_metadata
        |> filter { meta ->
            !skip_fastq_download && getDownloadMethod(meta, params.download_method) == 'aspera'
        }                                                   // Channel<Map>
        |> map { meta ->
            let fastq = meta.fastq_aspera.tokenize(';').take(2).collect { name -> file(name) }
            let out = ASPERA_CLI ( meta, fastq, 'era-fasp', params.aspera_cli_args )
            new Sample(out.meta, out.fastq, out.md5)
        }                                                   // Channel<Sample>
        |> set { aspera_samples }                           // Channel<Sample>

    mix( ftp_samples, sratools_samples, aspera_samples )    // Channel<Sample>
        |> map { sample ->
            let meta = sample.meta
            meta + [
                fastq_1: sample.fastq[0],
                fastq_2: sample.fastq[1] && !meta.single_end ? sample.fastq[1] : null,
                md5_1: sample.md5[0],
                md5_2: sample.md5[1] && !meta.single_end ? sample.md5[1] : null
            ]
        }                                                   // Channel<Map>
        |> set { samples }                                  // Channel<Map>

    emit:
    samples

    publish:
    runinfo_ftp >> 'metadata'
}

/*
========================================================================================
    FUNCTIONS
========================================================================================
*/

fn getDownloadMethod(meta: Map, download_method: String) -> String {
    // meta.fastq_aspera is a metadata string with ENA fasp links supported by Aspera
        // For single-end: 'fasp.sra.ebi.ac.uk:/vol1/fastq/ERR116/006/ERR1160846/ERR1160846.fastq.gz'
        // For paired-end: 'fasp.sra.ebi.ac.uk:/vol1/fastq/SRR130/020/SRR13055520/SRR13055520_1.fastq.gz;fasp.sra.ebi.ac.uk:/vol1/fastq/SRR130/020/SRR13055520/SRR13055520_2.fastq.gz'
    if (meta.fastq_aspera && download_method == 'aspera')
        return 'aspera'
    if ((!meta.fastq_aspera && !meta.fastq_1) || download_method == 'sratools')
        return 'sratools'
    return 'ftp'
}

/*
========================================================================================
    TYPES
========================================================================================
*/

record SraParams {
    ena_metadata_fields         : String
    download_method             : String // enum: 'aspera' | 'ftp' | 'sratools'
    skip_fastq_download         : boolean
    dbgap_key                   : String?
    aspera_cli_args             : String
    sra_fastq_ftp_args          : String
    sratools_fasterqdump_args   : String
    sratools_pigz_args          : String
}

record Sample {
    meta    : Map<String,Object>
    fastq   : List<Path>
    md5     : List<Path>
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
