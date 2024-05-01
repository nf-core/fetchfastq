
process SRA_TO_SAMPLESHEET {
    executor 'local'
    memory 100.MB

    input:
    List<Map> sra_metadata
    String pipeline
    String strandedness
    String mapping_fields

    output:
    Path samplesheet  = path("samplesheet.csv")
    Path mappings     = path("mappings.csv")

    exec:
    //
    // Create samplesheet containing metadata
    //

    def records = sra_metadata.collect { meta ->
        getSraRecord(meta, pipeline, strandedness, mappings)
    }

    def samplesheet = records
        .collect { pipeline_map, mappings_map -> pipeline_map }
        .sort { record -> record.id }
    mergeCsv(samplesheet, task.workDir.resolve('samplesheet.csv'))

    def mappings = records
        .collect { pipeline_map, mappings_map -> mappings_map }
        .sort { record -> record.id }
    mergeCsv(mappings, task.workDir.resolve('id_mappings.csv'))
}

def getSraRecord(Map meta, String pipeline, String strandedness, String mapping_fields) {
    //  Remove custom keys needed to download the data
    def meta_clone = meta.clone()
    meta_clone.remove("id")
    meta_clone.remove("fastq_1")
    meta_clone.remove("fastq_2")
    meta_clone.remove("md5_1")
    meta_clone.remove("md5_2")
    meta_clone.remove("single_end")

    // Add relevant fields to the beginning of the map
    def pipeline_map = [
        sample  : "${meta.id.split('_')[0..-2].join('_')}",
        fastq_1 : meta.fastq_1,
        fastq_2 : meta.fastq_2
    ]

    // Add nf-core pipeline specific entries
    if (pipeline) {
        if (pipeline == 'rnaseq') {
            pipeline_map << [ strandedness: strandedness ]
        } else if (pipeline == 'atacseq') {
            pipeline_map << [ replicate: 1 ]
        } else if (pipeline == 'taxprofiler') {
            pipeline_map << [ fasta: '' ]
        }
    }
    pipeline_map << meta_clone

    //
    // Create sample id mappings file
    //
    def mappings_map = pipeline_map.clone()
    def fields = mapping_fields ? ['sample'] + mapping_fields.split(',').collect{ v -> v.trim().toLowerCase() } : []
    if ((mappings_map.keySet() + fields).unique().size() != mappings_map.keySet().size()) {
        error("Invalid option for '--sample_mapping_fields': ${mapping_fields}.\nValid options: ${mappings_map.keySet().join(', ')}")
    }

    mappings_map = mappings_map.subMap(fields)

    return [ pipeline_map, mappings_map ]
}
