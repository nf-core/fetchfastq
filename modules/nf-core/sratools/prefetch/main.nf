process SRATOOLS_PREFETCH {
    tag "$id"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/sra-tools:3.0.8--h9f5acd7_0' :
        'biocontainers/sra-tools:3.0.8--h9f5acd7_0' }"

    input:
    meta            : Map<String,String>
    ncbi_settings   : Path
    certificate     : Path?
    prefetch_args   : String = ''
    retry_args      : String = '5 1 100'  // <num retries> <base delay in seconds> <max delay in seconds>

    shell:
    id = meta.run_accession
    if (certificate) {
        if (certificate.baseName.endsWith('.jwt')) {
            prefetch_args += " --perm ${certificate}"
        }
        else if (certificate.baseName.endsWith('.ngc')) {
            prefetch_args += " --ngc ${certificate}"
        }
    }

    template 'retry_with_backoff.sh'

    output:
    file(id)

    topic:
    ( task.process, 'sratools', eval("prefetch --version 2>&1 | grep -Eo '[0-9.]+'") ) >> 'versions'
}
