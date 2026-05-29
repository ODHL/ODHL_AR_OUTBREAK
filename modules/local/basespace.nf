process BASESPACE {
    tag "${meta.id}"
    label 'process_low'

    input:
    tuple val(meta)

    output:
    tuple val(meta), path("*gz"), emit: reads

    script:
    // Extract sampleID from meta.id
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    
    """
    prefix='${prefix}'
    sample_id=\$(echo "\$prefix" | cut -f1 -d"-")
    project_id=\$(echo "\$prefix" | cut -f2- -d"-")
    download_name="\$prefix"

    # Some BaseSpace biosamples include a suffix such as "repeat" between the
    # specimen ID and project ID. Fall back to the real biosample name when the
    # exact logical outbreak name is not present.
    if ! basespace download biosample -n "\$download_name"; then
        download_name=\$(basespace list biosamples --filter-field BioSampleName --filter-term "\$sample_id" 2>/dev/null \
            | grep '^|' \
            | cut -d'|' -f2 \
            | sed 's/^[[:space:]]*//; s/[[:space:]]*\$//' \
            | grep -v '^BioSampleName\$' \
            | grep -E "^\$sample_id([^-]*)-\$project_id" \
            | head -n1)

        if [[ -z "\$download_name" ]]; then
            echo "ERROR: could not resolve BaseSpace biosample for ${prefix}" >&2
            exit 3
        fi

        basespace download biosample -n "\$download_name"
    fi
    
    # Grab R1, R2 names
    R1=\$(find \${download_name}*ds* -type f | grep 'R1' | head -n1)
    R2=\$(find \${download_name}*ds* -type f | grep 'R2' | head -n1)
    
    # Standardize output names to the logical outbreak sample ID.
    mv "\$R1" "${prefix}.R1.fastq.gz"
    mv "\$R2" "${prefix}.R2.fastq.gz"

    
    """

    stub:
    """
    touch \${sample_id}.R1.fastq.gz
    touch \${sample_id}.R2.fastq.gz
    """
}
