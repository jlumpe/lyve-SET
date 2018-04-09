Output files
============
| Directory |File    |   Description  | Notes |
|:------:|:---------:|----------------|-------|
|project/msa  || The multiple sequence alignment directory | Most of the output files you want are here like the multiple sequence alignment and the phylogeny|
||`out.pooled.vcf.gz` | the pooled VCF file created from `bcftools merge` | |
||`out.pooled.vcf.gz.tbi` | the tabix index file | |
||`out.bcftoolsquery.tsv` | the `bcftools query` output | This file is essentially the main SNP matrix and describes the position and allele for each genome.  Each allele is in the genotype (GT) format, as specified in the vcf format specification |
||`out.filteredbcftoolsquery.tsv` | the filtered `bcftools query` output | After `out.bcftoolsquery.tsv` is generated, this file describes remaining SNPs after some are filtered out, usually because the `--allowedFlanking` option in `launch_set.pl`, `--allowed` in `filterMatrix.pl`, or similar parameters in other scripts |
||`out.aln.fas` | the output alignment file in fasta format. | Make any changes to this file before running a phylogeny |program.  Do not use `informative.aln.fas` to make edits because positions might come and go and therefore you might lose resolution. After any edits, use `removeUninformativeSites.pl` to re-create `informative.aln.fas`  |
|| `informative.aln.fas` | The alignment after removing uninformative columns (ambiguities, invariants, gaps) | Do not make any changes to this file before running a phylogeny. Make the changes in `out.aln.fas` |
|| `RAxML.RAxML_bipartitions` | RAxML-generated tree in newick format | The parameters of RAxML are shown in the process_msa logfile in `log/`.  Look for the line that says `RAxML was called as follows`. |
|| `pairwise.tsv` | Pairwise distances file | Format: tab-delimited with three columns: genome1, genome2, hqSNP distance |
|| `fst.avg.tsv` | Describes the Fst of all clades, given the other clades in the group | This file is less meaningful in tighter phylogenies, and gains much more meaning in more diverse phylogenies with more clades |
|| `fst.fst.dnd` | Copy of `RAxML.RAxML_bipartitions`, but with Fst values instead of bootstrap values | |
|project/log|| All the log files | |
|| `launch_set.log`    | Most of the SET log files are here | |
|| `set_processMsa.log`| The MSA and phylogeny log files are here | |
|project/asm, project/reads, project/reference || The assemblies, reads, and reference directories | These input directories are described elsewhere. |
|project/reference/maskedRegions || BED-formatted files that describe the regions to mask in the reference genome| Custom bed files with a `.bed` extension can also be placed here|
|project/bam|| Output bam files are here|
||`*.sorted.bam` | sorted bam files | The query and reference name are encoded in the filename; many times the reference name will just be called "reference." |
||`*.sorted.bam.bai` | samtools index file || 
||`*.sorted.bam.depth` | samtools depth output | It is a three-column format: seqname, pos, depth. Sites with zero-depth have been filled in using Lyve-SET. |
|project/vcf/unfiltered|| Output VCF files|These filtered VCF files are deprecated in favor of `project/vcf/*.vcf` and will probably not be continued in future versions of Lyve-SET|
||`*.vcf.gz`|VCF files |Filtered VCF files||
||`*.vcf.gz.tbi`| Tabix index files||
|project/vcf||VCF files|Have the same file format as the `*.sorted.bam` files, so that they can be matched easily when running Lyve-SET. These files are sorted with vcftools and compressed with bgzip.|
||`*.vcf.gz`|VCF files |Filtered VCF files||
||`*.vcf.gz.tbi`| Tabix index files||
