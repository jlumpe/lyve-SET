#!/usr/bin/env perl

require 5.12.0;
use strict;
use warnings;
use Data::Dumper;
use Getopt::Long;
use Bio::Perl;
use File::Basename;
use File::Temp qw/tempdir/;
use List::Util qw/min max sum/;
use Fcntl qw(SEEK_SET SEEK_CUR SEEK_END); #SEEK_SET=0 SEEK_CUR=1 ...

use FindBin;
use lib "$FindBin::RealBin/../lib";
use LyveSET qw/logmsg/;
use lib "$FindBin::RealBin/../lib/lib/perl5";
use Number::Range;

use constant reportEvery=>100000;

$0=fileparse $0;

exit main();
sub main{
  my $settings={};
  GetOptions($settings,qw(help ambiguities|ambiguities-allowed! invariant! tempdir=s allowed|allowedFlanking=i mask=s@ numcpus=i Ns-as-ref)) or die $!;
  die usage() if($$settings{help});
  $$settings{ambiguities}//=0;
  $$settings{invariant}//=0;
  $$settings{'Ns-as-ref'}//=0;
  $$settings{tempdir}||=tempdir("$0XXXXXX",TMPDIR=>1,CLEANUP=>1);
  $$settings{allowed}||=0;
  $$settings{mask}||=[];
  $$settings{numcpus}||=1;

  my($in)=@ARGV;
  $in or die "ERROR: need input file\n".usage();

  # Explain the settings for this script.
  my $settingsString="";
  for (sort {$a cmp $b} keys(%$settings)){
    my $str=$$settings{$_};
    if(ref($str) eq 'ARRAY'){
      $str=join("\t",@$str);
    }
    $settingsString.=join("\t=\t",$_,$str)."\n";
  }
  logmsg "Filtering and other settings for this script:\n$settingsString";
  filterSites($in,$settings);

  return 0;
}

# Filter the BCF query file into a new one, if any filters were given
sub filterSites{
  my($bcfqueryFile,$settings)=@_;

  # Open the unfiltered BCF query file
  my $fp;
  open($fp,"<",$bcfqueryFile) or die "ERROR: could not open bcftools query file $bcfqueryFile for reading: $!";

  # If there are any coordinates explicitly listed for masking,
  # combine them all into a single range object, one per seqname.
  my $maskedRanges=readBedFiles($bcfqueryFile,$$settings{mask},$settings);

  # Read in the header with genome labels
  my $header=<$fp>;
  print $header;  # Print the header right away so that it can be saved correctly before it's changed
  $header=~s/^\s+|^#|\s+$//g; # trim and remove pound sign
  my @header=split /\t/, $header;

  my $inputSitesCount=0;
  my $outputSitesCount=0;
  while(my $bcfMatrixLine=<$fp>){
    chomp $bcfMatrixLine;
    $inputSitesCount++;

    # Start by assuming that this is a high-quality site
    # i.e., innocent until proven guilty.
    my $hqSite=1;

    # get the fields from the matrix
    my($CONTIG,$POS,$REF,@GT)=split(/\t/,$bcfMatrixLine);
    my $numAlts=@GT;

    # If the user wants to make sure that this snp is --allowedFlanking
    # SNPs apart from other SNPs, make sure it is that many
    # positions away from the beginning of the contig.
    next if($POS < $$settings{allowed});
    # TODO: also do this for the end of the contig if the lengths are known.

    # Change the geotype to haploid.
    for(my $i=0;$i<$numAlts;$i++){
      $GT[$i]=diploidGtToHaploid($GT[$i],$REF,$settings);
    }
    # Save these genotypes for printing later, even if @GT gets altered.
    #my @GT_original=@GT; # ACTUALLY: @GT is not printed anyway

    # Mask any site found in the BED files
    $hqSite=0 if(defined($$maskedRanges{$CONTIG}) && $$maskedRanges{$CONTIG}->inrange($POS));

    # Simply get rid of any site that consists of all Ns
    my $is_allNs=1;
    # Need a ref base that will be in the MSA that
    # is not ambiguous for decent comparison.
    # The bases in the MSA are only coming from alts
    # and not from ref.
    my $altRef;
    my $altRefIndex=0;
    for(my $i=0;$i<$numAlts;$i++){
      next if($GT[$i]=~/[Nn\.]/);

      $is_allNs=0;

      # Generate the reference base.
      if(!$altRef){
        $altRef=$GT[$i];
        $altRefIndex=$i;
      }
      #last; # No need to loop over the other ALTs if a nonN was found
    }
    $hqSite=0 if($is_allNs);
    
    # The user can specify that high quality sites are those where every site is defined
    # (ie through --noambiguities)
    if(!$$settings{ambiguities}){
      for(my $i=0;$i<$numAlts;$i++){
        if($GT[$i]!~/[ATCG]/i){
          $hqSite=0;
          last;
        }
      }
    }

    # If we want to treat ambiguous bases as the reference
    # but not print them out that way, then change them
    # internally here.
    if($$settings{'Ns-as-ref'}){
      for(@GT){
        $_=$altRef if($_ =~/[Nn\.]/);
      }
    }

    # Remove any invariant site, if specified.
    # invariant means "keep invariant sites"
    # !invariant means "remove invariant sites"
    # However, there is no point in looking for these
    # sites if all alts are masked as Ns.
    if(!$is_allNs && !$$settings{invariant}){

      # Start off assuming that the site is not variant,
      # until proven otherwise.
      my $is_variant=0;
      for(my $i=0;$i<$numAlts;$i++){
        # TODO look at this position
        if($GT[$i] ne $altRef){
          $is_variant=1;
          last; # save a nanosecond of time here
        }
      }
      $hqSite=0 if(!$is_variant);

      #die Dumper ["@GT",$altRefIndex,$altRef,$hqSite,$is_variant] if($POS==150615);
    }
    
    # Special things happen if we see an hq site
    if($hqSite){
      # Print out the results
      print $bcfMatrixLine ."\n";

      # Move ahead $$settings{allowed} positions to 
      # separate flanking hq sites
      my $numSitesSkipped=seekToPosition($CONTIG,$POS+$$settings{allowed},$fp,$settings);

      $inputSitesCount+=$numSitesSkipped;
      $outputSitesCount++;
    }

    if($inputSitesCount % reportEvery == 0){
      my $hqPercent=sprintf("%0.4f",($outputSitesCount/$inputSitesCount*100))."%";
      logmsg "Reviewed $inputSitesCount sites so far with $outputSitesCount hqSites accepted ($hqPercent)";
    }
  }
  close $fp;

  my $hqPercent=sprintf("%0.4f",($outputSitesCount/$inputSitesCount*100))."%";
  logmsg "Finished reviewing $inputSitesCount sites with $outputSitesCount hqSites accepted ($hqPercent)";

  return ($inputSitesCount,$outputSitesCount) if wantarray;
  return $inputSitesCount;
}

# Seek ahead to a certain position in the VCF. If that pos
# is not found, go to the 1st pos in the next contig.
# Then, seek back one line if it's not the same pos
# going into the sub as going out.
sub seekToPosition{
  my($seekContig,$seekPos,$fp,$settings)=@_;

  my $numLinesAdvanced=0;
  my @lineLength=();
  while(my $line=<$fp>){
    push(@lineLength,length($line));
    chomp $line;
    $numLinesAdvanced++;

    my($CONTIG,$POS,$REF,@GT)=split(/\t/,$line);
    if($CONTIG ne $seekContig || $POS >= $seekPos){
      my $bytesToGoBack = $lineLength[-1];
      my $whence=1; 
      seek($fp,-$bytesToGoBack,$whence) or die "ERROR: could not seek in the input file ($bytesToGoBack, $whence): $!";
      $numLinesAdvanced--;
      last;
    }
  }

  return $numLinesAdvanced;
}

sub diploidGtToHaploid{
  my($gt,$REF,$settings)=@_;

  # GT are in the format of N/N or N
  my($gt1,$gt2)=split(/\//,$gt);
  $gt2||=$gt1; # if it was already haploid, temporarily change it to homozygous diploid
  for($gt1,$gt2){
    $_='N' if($_ eq ".");
  }
  # If heterozygous, then it is masked
  if($gt1 ne $gt2){
    $gt="N";
  } else {
    $gt=$gt1;
  }

  return $gt;
}

# Turn bed-defined ranges into range objects
sub readBedFiles{
  my($bcfqueryFile,$maskFile,$settings)=@_;
  my %range;

  # Find what seqnames there are out there first,
  # so that every expected range object will be defined.
  if(-e $bcfqueryFile){
    my %seqname;
    open(BCFQUERYFILE,"<",$bcfqueryFile) or die "ERROR: could not read $bcfqueryFile: $!";
    while(<BCFQUERYFILE>){
      next if(/^#/);
      my($seqname)=split(/\t/,$_);
      $seqname{$seqname}=1;
    }
    close BCFQUERYFILE;
    # Sort function found at http://www.perlmonks.org/index.pl?node_id=68185
    my @seqname=sort {
      my @a = split /(\d+)/, lc($a);
      my @b = split /(\d+)/, lc($b);
      my $M = @a > @b ? @a : @b;
      my $res = 0;
      for (my $i = 0; $i < $M; $i++) {
        return -1 if ! defined $a[$i];
        return 1 if  ! defined $b[$i];
        if ($a[$i] =~ /\d/) {
          $res = $a[$i] <=> $b[$i];
        } else {
          $res = $a[$i] cmp $b[$i];
        }
        last if $res;
      }
      return $res;
    } keys(%seqname);

    # Initialize ranges
    $range{$_}=Number::Range->new() for(@seqname);
  }

  # Read the bed files
  for my $bed(@$maskFile){
    open(BED,$bed) or die "ERROR: could not open $bed: $!";
    while(<BED>){
      chomp;
      my($seqname,$start,$stop)=split(/\t/);
      $range{$seqname}=Number::Range->new() if(!$range{$seqname});
      my $lo=min($start,$stop);
      my $hi=max($start,$stop);
      $range{$seqname}->addrange("$lo..$hi");
    }
    close BED;
  }

  return \%range;
}

sub usage{
  "Multiple VCF format to alignment
  $0: filters a bcftools query matrix. The first three columns of the matrix are contig/pos/ref, and the next columns are all GT.
  Usage: 
    $0 bcftools.tsv > filtered.tsv
  --ambiguities                 Keep sites with ambiguities
  --invariant                   Keep sites that are invariant
  --Ns-as-ref                   When considering ambiguities and invariant
                                sites, pretend Ns are equal to REF. This
                                will not change Ns to REF in the output.
                                If this option is not used, then a site with
                                an N will be considered variant.
  --allowed           0         How close SNPs can be from each other before 
                                being thrown out. Zero or one means they can
                                be adjacent.
  --tempdir           tmp       temporary directory
  --mask              file.bed  BED-formatted file of regions to exclude.
                                Multiple --mask flags are allowed for multiple
                                bed files.
  --numcpus           1         (not yet implemented)

  "
}
