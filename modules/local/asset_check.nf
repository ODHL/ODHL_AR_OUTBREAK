process ASSET_CHECK {
    label 'process_low'
    container 'quay.io/jvhagey/phoenix@sha256:f0304fe170ee359efd2073dcdb4666dddb96ea0b79441b1d2cb1ddc794de4943'

    input:
    path(zipped_sketch)
    path(mlst_db_path)
    path(kraken2_db)

    output:
    path("versions.yml"),               emit: versions
    path('*.msh'),                      emit: mash_sketch
    path('db'),                         emit: mlst_db
    path('*_folder'),                   emit: kraken2_db

    when:
    task.ext.when == null || task.ext.when

    script:
    def container_version = "base_v2.1.0"
    def container = task.container.toString() - "quay.io/jvhagey/phoenix@"
    def unzipped_sketch = "${zipped_sketch}".minus(".bz2")
    """
    pigz -vdf ${zipped_sketch}
    
    tar --use-compress-program="pigz -vdf" -xf ${mlst_db_path}
    
    tar --use-compress-program="pigz -vdf" -xf ${kraken2_db}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        phoenix_base_container_tag: ${container_version}
        phoenix_base_container: ${container}
    END_VERSIONS
    """
}