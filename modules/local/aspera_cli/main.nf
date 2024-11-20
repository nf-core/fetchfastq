process ASPERA_CLI {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/aspera-cli:4.14.0--hdfd78af_1' :
        'biocontainers/aspera-cli:4.14.0--hdfd78af_1' }"

    input:
    meta    : Map<String,String>
    user    : String

    output:
    fastq_1 : Path  = file('*_1.fastq.gz')
    fastq_2 : Path? = file('*_2.fastq.gz')
    md5_1   : Path  = file('*_1.fastq.gz.md5')
    md5_2   : Path? = file('*_2.fastq.gz.md5')

    topic:
    ( task.process, 'aspera_cli', eval('ascli --version') ) >> 'versions'

    script:
    def args = task.ext.args ?: ''
    def conda_prefix = ['singularity', 'apptainer'].contains(workflow.containerEngine) ? "export CONDA_PREFIX=/usr/local" : ""
    def fastq = meta.fastq_aspera.tokenize(';')
    if (meta.single_end.toBoolean()) {
        """
        $conda_prefix

        ascp \\
            $args \\
            -i \$CONDA_PREFIX/etc/aspera/aspera_bypass_dsa.pem \\
            ${user}@${fastq[0]} \\
            ${meta.id}.fastq.gz

        echo "${meta.md5_1}  ${meta.id}.fastq.gz" > ${meta.id}.fastq.gz.md5
        md5sum -c ${meta.id}.fastq.gz.md5
        """
    } else {
        """
        $conda_prefix

        ascp \\
            $args \\
            -i \$CONDA_PREFIX/etc/aspera/aspera_bypass_dsa.pem \\
            ${user}@${fastq[0]} \\
            ${meta.id}_1.fastq.gz

        echo "${meta.md5_1}  ${meta.id}_1.fastq.gz" > ${meta.id}_1.fastq.gz.md5
        md5sum -c ${meta.id}_1.fastq.gz.md5

        ascp \\
            $args \\
            -i \$CONDA_PREFIX/etc/aspera/aspera_bypass_dsa.pem \\
            ${user}@${fastq[1]} \\
            ${meta.id}_2.fastq.gz

        echo "${meta.md5_2}  ${meta.id}_2.fastq.gz" > ${meta.id}_2.fastq.gz.md5
        md5sum -c ${meta.id}_2.fastq.gz.md5
        """
    }
}
