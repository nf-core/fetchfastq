
process MULTIQC_MAPPINGS_CONFIG {

    conda "conda-forge::python=3.9.5"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.9--1' :
        'biocontainers/python:3.9--1' }"

    input:
    Path csv

    output:
    Path yml = path("multiqc_config.yml")

    topic:
    [ task.process, 'python', eval("python --version | sed 's/Python //g'") ] >> 'versions'

    script:
    """
    multiqc_mappings_config.py \\
        $csv \\
        multiqc_config.yml
    """
}
