include { CUSTOM_SRATOOLSNCBISETTINGS } from '../../../modules/nf-core/custom/sratoolsncbisettings/main'
include { SRATOOLS_PREFETCH           } from '../../../modules/nf-core/sratools/prefetch/main'
include { SRATOOLS_FASTERQDUMP        } from '../../../modules/nf-core/sratools/fasterqdump/main'

//
// Download FASTQ sequencing reads from the NCBI's Sequence Read Archive (SRA).
//
workflow FASTQ_DOWNLOAD_PREFETCH_FASTERQDUMP_SRATOOLS {
    take:
    sra_metadata                // Channel<Map<String,String>>
    dbgap_key                   // Path?
    sratools_fasterqdump_args   // String
    sratools_pigz_args          // String

    main:
    //
    // Detect existing NCBI user settings or create new ones.
    //
    let ncbi_settings = CUSTOM_SRATOOLSNCBISETTINGS( collect(sra_metadata) )

    let reads = sra_metadata |> map { meta ->
        //
        // Prefetch sequencing reads in SRA format.
        //
        let sra = SRATOOLS_PREFETCH (
            meta,
            ncbi_settings,
            dbgap_key )

        //
        // Convert the SRA format into one or more compressed FASTQ files.
        //
        let fastq = SRATOOLS_FASTERQDUMP (
            meta,
            sra,
            ncbi_settings,
            dbgap_key,
            sratools_fasterqdump_args,
            sratools_pigz_args )

        ( meta, fastq )
    }                                                   // Channel<(Map<String,String>, List<Path>)>

    emit:
    reads   // Channel<(Map<String,String>, List<Path>)>
}
