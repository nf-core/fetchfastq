
process SRA_FASTQ_FTP {
    tag "$meta.id"
    label 'process_low'
    label 'error_retry'

    conda "conda-forge::wget=1.20.1"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/wget:1.20.1' :
        'biocontainers/wget:1.20.1' }"

    input:
    meta    : Map<String,String>

    output:
    fastq_1 : Path  = file('*_1.fastq.gz')
    fastq_2 : Path? = file('*_2.fastq.gz')
    md5_1   : Path  = file('*_1.fastq.gz.md5')
    md5_2   : Path? = file('*_2.fastq.gz.md5')

    topic:
    ( task.process, 'wget', eval("echo \$(wget --version | head -n 1 | sed 's/^GNU Wget //; s/ .*\$//')") ) >> 'versions'

    script:
    def args = task.ext.args ?: ''
    if (meta.single_end.toBoolean()) {
        """
        wget \\
            $args \\
            -O ${meta.id}.fastq.gz \\
            ${meta.fastq_1}

        echo "${meta.md5_1}  ${meta.id}.fastq.gz" > ${meta.id}.fastq.gz.md5
        md5sum -c ${meta.id}.fastq.gz.md5
        """
    } else {
        """
        wget \\
            $args \\
            -O ${meta.id}_1.fastq.gz \\
            ${meta.fastq_1}

        echo "${meta.md5_1}  ${meta.id}_1.fastq.gz" > ${meta.id}_1.fastq.gz.md5
        md5sum -c ${meta.id}_1.fastq.gz.md5

        wget \\
            $args \\
            -O ${meta.id}_2.fastq.gz \\
            ${meta.fastq_2}

        echo "${meta.md5_2}  ${meta.id}_2.fastq.gz" > ${meta.id}_2.fastq.gz.md5
        md5sum -c ${meta.id}_2.fastq.gz.md5
        """
    }
}
