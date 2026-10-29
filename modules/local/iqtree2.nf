process IQTREE2 {
  tag "CORE TREE"
  label 'process_high'
  container 'staphb/iqtree2@sha256:61c06874bbf40d91361f9b0deeb372cd8a32b38553f5b24e16a5a766220e968c'
  
  input:
  path(aln)

  output:
  path('*core_genome.tree')           , emit: genome_tree

  script:
  """
  numGenomes=`grep -o -e '^>.*' ${aln} | wc -l`
  if [ \$numGenomes -gt 3 ]; then
    iqtree2 -nt AUTO -keep-ident -m TEST -B 1000 -s ${aln} 
    mv core_gene_alignment.aln.contree core_genome.tree
  else
    echo "There is not enough points at 80% conformity" > core_genome.tree
  fi
  """
}