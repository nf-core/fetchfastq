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
    ids     : Channel<String>
    params  : SraParams

    main:
    runinfo_ftp = ids
        //
        // MODULE: Get SRA run information for public database ids
        //
        .map { id ->
            SRA_IDS_TO_RUNINFO ( id, params.ena_metadata_fields )
        }                                                   // Channel<Path>
        //
        // MODULE: Parse SRA run information, create file containing FTP links and read into workflow as [ meta, [reads] ]
        //
        .map(SRA_RUNINFO_TO_FTP)                            // Channel<Path>

    sra_metadata = runinfo_ftp.scatter { tsv ->
        tsv.splitCsv(header:true, sep:'\t').unique()
    }                                                       // Channel<Map<String,String>>

    //
    // MODULE: If FTP link is provided in run information then download FastQ directly via FTP and validate with md5sums
    //
    ftp_samples = sra_metadata
        .filter { meta ->
            !skip_fastq_download && getDownloadMethod(meta, params.download_method) == DownloadMethod.FTP
        }                                                   // Channel<Map<String,String>>
        .map { meta ->
            def out = SRA_FASTQ_FTP ( meta, params.sra_fastq_ftp_args )
            new Sample(meta.id, out.fastq_1, out.fastq_2, out.md5_1, out.md5_2)
        }                                                   // Channel<Sample>

    //
    // SUBWORKFLOW: Download sequencing reads without FTP links using sra-tools.
    //
    sratools_metadata = sra_metadata.filter { meta ->
        !skip_fastq_download && getDownloadMethod(meta, params.download_method) == DownloadMethod.SRATOOLS
    }                                                       // Channel<Map<String,String>>

    sratools_reads = FASTQ_DOWNLOAD_PREFETCH_FASTERQDUMP_SRATOOLS (
        sratools_metadata,
        params.dbgap_key,
        params.sratools_fasterqdump_args,
        params.sratools_pigz_args
    )                                                       // Channel<(Map<String,String>, List<Path>)>

    sratools_samples = sra_metadata.map { (meta, fastq) ->
        def fastq_1 = fastq[0]
        def fastq_2 = !meta.single_end ? fastq[1] : null
        new Sample(meta.id, fastq_1, fastq_2, null, null)
    }                                                       // Channel<Sample>

    //
    // MODULE: If Aspera link is provided in run information then download FastQ directly via Aspera CLI and validate with md5sums
    //
    aspera_samples = sra_metadata
        .filter { meta ->
            !skip_fastq_download && getDownloadMethod(meta, params.download_method) == DownloadMethod.ASPERA
        }                                                   // Channel<Map<String,String>>
        .map { meta ->
            def out = ASPERA_CLI ( meta, 'era-fasp', params.aspera_cli_args )
            new Sample(meta.id, out.fastq_1, out.fastq_2, out.md5_1, out.md5_2)
        }                                                   // Channel<Sample>

    emit:
    ftp_samples
        .mix(sratools_samples)
        .mix(aspera_samples)

    publish:
    runinfo_ftp >> 'metadata'
}

/*
========================================================================================
    FUNCTIONS
========================================================================================
*/

def getDownloadMethod(meta: Map<String,String>, userMethod: DownloadMethod) -> DownloadMethod {
    // meta.fastq_aspera is a metadata string with ENA fasp links supported by Aspera
        // For single-end: 'fasp.sra.ebi.ac.uk:/vol1/fastq/ERR116/006/ERR1160846/ERR1160846.fastq.gz'
        // For paired-end: 'fasp.sra.ebi.ac.uk:/vol1/fastq/SRR130/020/SRR13055520/SRR13055520_1.fastq.gz;fasp.sra.ebi.ac.uk:/vol1/fastq/SRR130/020/SRR13055520/SRR13055520_2.fastq.gz'
    if (meta.fastq_aspera && userMethod == DownloadMethod.ASPERA)
        return DownloadMethod.ASPERA
    if ((!meta.fastq_aspera && !meta.fastq_1) || userMethod == DownloadMethod.SRATOOLS)
        return DownloadMethod.SRATOOLS
    return DownloadMethod.FTP
}

/*
========================================================================================
    TYPES
========================================================================================
*/

record SraParams {
    ena_metadata_fields         : String
    download_method             : DownloadMethod
    skip_fastq_download         : boolean
    dbgap_key                   : Path?
    aspera_cli_args             : String
    sra_fastq_ftp_args          : String
    sratools_fasterqdump_args   : String
    sratools_pigz_args          : String
}

enum DownloadMethod {
    ASPERA,
    FTP,
    SRATOOLS
}

record Sample {
    id      : String
    fastq_1 : Path
    fastq_2 : Path?
    md5_1   : Path?
    md5_2   : Path?
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
