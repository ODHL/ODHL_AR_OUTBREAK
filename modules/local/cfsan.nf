process CFSAN {
  tag "CFSAN"
  label 'process_high'
  container 'staphb/cfsan-snp-pipeline:2.2.1'
  
  input:
  path(gffs)
  path(db)
  path(config)

  output:
  path('*snp_distance_matrix.tsv')            , emit: distmatrix
  path('*snpma.fasta')                        , emit: snpma

  // cfsan requires each sample to be in a subfolder
  script:
  """
  if [[ -d input ]]; then rm -rf input; fi
  mkdir -p input

  # standardize naming
  for f in *cleaned*; do
    # rename the sames with a reference
    new=`echo \$f | sed "s/_cleaned_/.R/g"`
    mv "\$f" "\$new"
  done

  for f in *fastq.gz; do
    sample_name=\$(basename "\$f" .fastq.gz)
    sample_name=`echo \$sample_name | sed "s/.R[1,2]//g"`
    if [[ ! -d input/\$sample_name ]]; then mkdir input/\$sample_name; fi
    mv \$f input/\$sample_name
  done 

  cfsan_snp_pipeline run ${db} -c ${config} -o . -s input
  """
}