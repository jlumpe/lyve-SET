#!/usr/bin/env perl
# Process a resulting MSA: remove uninformative sites; find pairwise distances;
# find Fst; make a tree; calculate the eigenvector
# Author: Lee Katz <lkatz@cdc.gov>

use FindBin;
use lib "$FindBin::RealBin/../lib";

use strict;
use warnings;
use Data::Dumper;
use Getopt::Long;
use File::Basename;
use File::Spec;
use File::Temp qw/tempdir/;
use Bio::Perl;
use File::Copy qw/move copy/;
use threads;
use Thread::Queue;

sub logmsg {local $0=basename $0;my $FH = *STDOUT; print $FH "$0: ".(caller(1))[3].": @_\n";}
exit main();

sub main{
  local $0=basename $0;
  my $settings={informative=>1};
  GetOptions($settings,qw(auto groups=s@ treePrefix=s informative! alnPrefix=s pairwisePrefix=s fstPrefix=s eigenPrefix=s numcpus=i msaDir=s tempdir=s force help rename-taxa=s)) or die $!;
  $$settings{treePrefix}||="";
  $$settings{alnPrefix}||="";
  $$settings{pairwisePrefix}||="";
  $$settings{fstPrefix}||="";
  $$settings{eigenPrefix}||="";
  $$settings{numcpus}||=1;
  $$settings{auto}||=0;
  $$settings{msaDir}||=0;
  $$settings{force}||=0;
  $$settings{'rename-taxa'}||="";
  die usage() if($$settings{help});

  if($$settings{auto} || $$settings{msaDir}){
    if($$settings{auto}){
      if(!$$settings{msaDir}){
        $$settings{msaDir}="msa" if(-e "msa/out.aln.fas");
        $$settings{msaDir}="." if(-e "./out.aln.fas");
      }
      die "ERROR: --auto was set but I could not find out.aln.fas in either this directory or in ./msa/\n".usage() if(!$$settings{msaDir} || !-e "$$settings{msaDir}/out.aln.fas");
    }
    $$settings{auto}=1;  # explicitly set auto if auto or msaDir is set

    my $dir="$$settings{msaDir}"; # save me on typing the next few lines
    $$settings{treePrefix}||="$dir/RAxML";
    $$settings{alnPrefix}||="$dir/informative";
    $$settings{pairwisePrefix}||="$dir/pairwise";
    $$settings{fstPrefix}||="$dir/fst";
    $$settings{eigenPrefix}||="$dir/eigen";
  }
  $$settings{tempdir}||=tempdir("set_processMSA.XXXXXX",TMPDIR=>1, CLEANUP=>1);
  mkdir $$settings{tempdir} if(!-d $$settings{tempdir});

  my $infile;
  if(@ARGV){
    $infile=$ARGV[0];
  } elsif($$settings{auto}){
    $infile="$$settings{msaDir}/out.aln.fas";
  } else {
    die "ERROR: need input alignment file\n".usage();
  }
  if(!-f $infile){
    die "ERROR: could not find file $infile\n".usage();
  }
  logmsg "Input alignment file is ".File::Spec->rel2abs($infile);

  renameTaxa($infile,$settings) if($$settings{'rename-taxa'});
  my $outgroup=distanceStuff($infile,$settings);
  my($informativeAln,$tree)=phylogenies($infile,$outgroup,$settings);
  Fst($infile,$$settings{pairwisePrefix},$$settings{treePrefix},$$settings{fstPrefix},$settings) if($$settings{fstPrefix} && $$settings{treePrefix} && $$settings{pairwisePrefix});

  #rmdir $$settings{tempdir};  # don't force this rmdir in case it contains files. This script should remove all tmp files before exiting.

  return 0;
}

####
## distance metrics stuff
####

# Rename the taxa in a fasta file. Back up the original file.
# Return the original file (renamed).
sub renameTaxa{
  my($infile,$settings)=@_;
  my $renamed="$infile.renamed.fasta";
  my $i=0;
  my $orig="$infile.orig".++$i;
  while(-e $orig){
    $orig="$infile.orig".++$i;
  }
  my $regex=$$settings{'rename-taxa'};

  logmsg "You requested to rename taxa with this regex =>$regex<=";

  my %taxa;

  my $in=Bio::SeqIO->new(-file=>$infile);
  my $out=Bio::SeqIO->new(-file=>">$renamed");
  while(my $seq=$in->next_seq){
    my $defline=$seq->id." ".$seq->desc;
    my $oldDefline=$defline;
    eval "\$defline=~$regex";
    my($id,@desc)=split(/\s+/,$defline);
    my $desc=join(" ",@desc);

    logmsg "$oldDefline => $defline";

    if($taxa{$id}++){
      die "ERROR: I have already seen id $id\n  It is possible that the regular expression you provided is too strict.";
    }

    # Print out the sequence
    $seq->id($id);
    $seq->desc($desc);
    $out->write_seq($seq);
  }

  copy($infile,$orig);
  move($renamed,$infile);
  return $orig;
}
    
sub distanceStuff{
  my($infile,$settings)=@_;
  logmsg "Calculating distances";

  my $pairwise=pairwiseDistance($infile,$$settings{pairwisePrefix},$settings) if($$settings{pairwisePrefix});
  eigen($pairwise,$$settings{eigenPrefix},$settings) if($$settings{eigenPrefix} && $pairwise);
}

sub pairwiseDistance{
  my($infile,$prefix,$settings)=@_;
  my $outfile="$prefix.tsv";
  my $matrix="$prefix.matrix.tsv";
  if(-f $outfile && !$$settings{force}){
    logmsg "$outfile was found. I will not perform pairwise distances again without --force";
    return $outfile;
  }
  
  # Before calculating pairwise distances, take a shortcut by
  # removing only invariant sites.
  logmsg "Removing invariant sites, as they do not contribute toward pairwise distances.";
  system("removeUninformativeSites.pl --gaps-allowed --ambiguities-allowed '$infile' > $$settings{tempdir}/variantSites.fasta");
  if($?){
    logmsg "Warning: could not remove invariant sites. Pairwise distance counting might go slower than intended."
  } else {
    $infile="$$settings{tempdir}/variantSites.fasta";
  }

  logmsg "Calculating pairwise distances";
  system("pairwiseDistances.pl --numcpus $$settings{numcpus} '$infile' | sort -k3,3n > '$outfile'");
  die if $?;
  system("pairwiseTo2d.pl < '$outfile' > '$matrix'");
  die if $?;
  
  return $outfile;
  # TODO inter and intra group distances
}

sub eigen{
  my($pairwise,$prefix,$settings)=@_;
  if(-f "$prefix.tsv" && !$$settings{force}){
    logmsg "The eigen vector file was found in $prefix.tsv. I will not recreate it without --force";
    return "$prefix.tsv";
  }
  system("set_indexCase.pl $pairwise | sort -k2,2nr > $prefix.tsv");
  logmsg "ERROR in set_indexCase.pl: $!" if $?;
  return "$prefix.tsv";
}


######
## phylogeny subroutines
#####


sub phylogenies{
  my($inAln,$outgroup,$settings)=@_;
  logmsg "Calculating phylogenies";

  my($informativeAln,$tree);
  $informativeAln=removeUninformativeSites($inAln,$$settings{alnPrefix},$settings) if($$settings{alnPrefix});
  $tree=inferPhylogeny($informativeAln,$$settings{treePrefix},$settings) if($$settings{treePrefix});
  return($informativeAln,$tree);
}

sub removeUninformativeSites{
  my($inAln,$outPrefix,$settings)=@_;
  my $informative="$outPrefix.aln.fas";

  if(-f $informative && !$$settings{force}){
    logmsg "$informative was found.  I will not recalculate without --force.";
    return $informative;
  }

  # If the user does not want to use the informative alignment, then copy over the actual alignment
  if(!$$settings{informative}){
    system("cp -v $inAln $informative");
    die "ERROR with copying $inAln to $informative" if $?;
    return $informative;
  }

  logmsg "Removing uninformative sites from the alignment and putting it into $informative";
  system("removeUninformativeSites.pl --ambiguities-allowed < '$inAln' > '$informative'");
  die if $?;
  return $informative;
}

# TODO put back in phyml
sub inferPhylogeny{
  my($inAln,$prefix,$settings)=@_;
  my $treeFile="$prefix.RAxML_bipartitions";
  if(-f "$prefix.RAxML_bipartitions" && !$$settings{force}){
    logmsg "$prefix.RAxML_bipartitions was found. I will not recalculate the phylogeny without --force.";
    return $treeFile;
  }
  
  my $numTaxa=`grep -c '>' '$inAln'`; die if $?;
  chomp($numTaxa);
  if($numTaxa < 4){
    logmsg "Only $numTaxa in the alignment. I will not determine the phylogeny";
    return "";
  }

  system("rm -fv $$settings{tempdir}/RAxML*");
  logmsg "Running raxml";
  my $alnInAbs=File::Spec->rel2abs($inAln);
  my $command="cd $$settings{tempdir}; launch_raxml.sh -n $$settings{numcpus} $alnInAbs suffix";
  logmsg "  $command";
  system($command);
  die if $?;

  # Move those files over when finished
  for (qw(RAxML_bestTree RAxML_bipartitionsBranchLabels RAxML_bipartitions RAxML_bootstrap RAxML_info)){
    system("mv -v $$settings{tempdir}/$_.suffix $prefix.$_");
    die "ERROR: could not move $$settings{tempdir}/$_.suffix to $prefix.$_: $!" if $?;
  }

  # If phyml exists, then run that too
  logmsg "Running phyml, if it available on this computer";
  system("launch_phyml.sh '$inAln'");
  if($?){
    logmsg "ERROR with phyml, but raxml completed successfully anyway";
  }

  return $treeFile;
}

#### 
# things that depend on pairwise and trees
####

sub Fst{
  my($inAln,$pairwisePrefix,$treePrefix,$fstPrefix,$settings)=@_;
  my $fstTree="$fstPrefix.fst.dnd";
  if(-f $fstTree && !$$settings{force}){
    logmsg "$fstTree fst tree was found.  Not recalculating without --force.";
    return $fstTree;
  }
  if(!-f "$treePrefix.RAxML_bipartitions"){
    logmsg "Tree was not created. Will not perform Fst on an empty tree";
    return "";
  }

  # Make a warning message if Fst doesn't complete. It's not necessary 
  # for the rest of the pipeline, so don't die on error.
  my $warningMsg="Warning: Fst could not be calculated either due to an error in the script 'applyFstToTree.pl', or because too many taxa are in one polytomy, or some other error I haven't uncovered yet.";
  my $exit_codes=0;

  # Run Fst, once for averages and once per data point.
  # TODO multithread this?
  system("applyFstToTree.pl --numcpus $$settings{numcpus} -t $treePrefix.RAxML_bipartitions -p $pairwisePrefix.tsv --outprefix $fstPrefix --outputType averages > $fstPrefix.avg.tsv");
  $exit_codes+=$?;
  system("applyFstToTree.pl --numcpus $$settings{numcpus} -t $treePrefix.RAxML_bipartitions -p $pairwisePrefix.tsv --outprefix $fstPrefix --outputType samples > $fstPrefix.samples.tsv");
  $exit_codes+=$?;
  logmsg $warningMsg if $exit_codes;
  return $fstTree;
}

sub usage{
  local $0=basename $0;
  "Process an MSA from a hqSNP pipeline and get useful information
  Usage: $0 file.fasta
  -n   numcpus
  --force               Files will be overwritten even if they exist
  --tempdir tmp/        Place to put temporary files
  --no-informative      Do not use an informative alignment. 
                        The output alignment will be the same as the 'informative' one in the MSA directory.

OUTPUT
  --rename-taxa ''      Rename taxa with a valid perl regex. Default: no renaming
                        Example to remove anything after the dot: --rename-taxa 's/\..*//'
                        Example to remove a suffix: --rename-taxa 's/\.fastq\.gz\-reference//'
  -tre treePrefix
  -aln informative.aln  Informative alignment, created by removeUninformativeSites.pl
  -p   pairwisePrefix   Pairwise distances
  -fst fstPrefix        Fixation index output files
  -e   eigenPrefix      Eigenvalue output files (connectedness)

  --auto                Indicate that you are currently in a SET directory and that you would like all outputs, overwriting any other output parameters
  --msaDir              Indicate a directory to perform everything in. --auto will be set if --msaDir is invoked
  "
}
