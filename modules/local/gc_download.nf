process GC_DOWNLOAD {
    tag "${meta.id}"
    label 'process_low'

    input:
    tuple val(meta)

    output:
    tuple val(meta), path("*.fastq.gz"), emit: reads

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def source = meta.gc_path ?: meta.gcs_path ?: meta.path ?: meta.download_path ?: ''

    if (!source) {
        error "GC_DOWNLOAD requires a gc_path/gcs_path/path entry in sample metadata for ${prefix}"
    }

    // Support pipe-separated R1|R2 GCS paths or a single local/GCS directory path
    def parts = source.split('\\|')
    def r1_src = parts[0].trim()
    def r2_src = parts.size() > 1 ? parts[1].trim() : ''

    """
    set -euo pipefail
    PREFIX='${prefix}'
    R1_SRC='${r1_src}'
    R2_SRC='${r2_src}'

    if [[ -n "\$R2_SRC" ]]; then
        # Explicit R1 and R2 paths (GCS or local)
        if [[ "\$R1_SRC" == gs://* ]]; then
            gcloud storage cp "\$R1_SRC" "\${PREFIX}.R1.fastq.gz"
            gcloud storage cp "\$R2_SRC" "\${PREFIX}.R2.fastq.gz"
        else
            cp -L "\$R1_SRC" "\${PREFIX}.R1.fastq.gz"
            cp -L "\$R2_SRC" "\${PREFIX}.R2.fastq.gz"
        fi
    else
        # Single directory path — find R1/R2 inside it
        SRC="\$R1_SRC"
        mkdir -p gc_download_work
        if [[ "\$SRC" == gs://* ]]; then
            gsutil -q cp -r "\$SRC" gc_download_work/ 2>/dev/null || gsutil -q cp "\$SRC" gc_download_work/
        else
            if [[ -d "\$SRC" ]]; then
                cp -L "\$SRC"/* gc_download_work/ 2>/dev/null || true
            else
                cp -L "\$SRC" gc_download_work/
            fi
        fi
        shopt -s nullglob
        files=(gc_download_work/*fastq*.gz gc_download_work/*fq*.gz)
        if [[ \${#files[@]} -eq 0 ]]; then
            echo "ERROR: no FASTQ files found at \$SRC" >&2
            exit 1
        fi
        for f in "\${files[@]}"; do
            base=\$(basename "\$f")
            cp -L "\$f" "\${PREFIX}_\${base}"
        done
    fi
    """

    stub:
    """
    touch ${prefix}_R1.fastq.gz
    touch ${prefix}_R2.fastq.gz
    """
}
