#!/usr/bin/perl

use BlastAnal;
use Utils;
use strict;
use Getopt::Long;
use File::Basename;

open(LOG,">blastSimilarity.log");

my $debug = 0;
$| = 1;

my ($regex,$pValCutoff,$lengthCutoff,$percentCutoff,$outputType,$program,$rpsblast,
    $database,$seqFile,$blast_version,$startNumber,$stopNumber,$dataFile,$remMaskedRes,
    $saveAllBlastFiles,$saveGoodBlastFiles,$doNotParse,$blastParamsFile, $doNotExitOnBlastFailure, $blastVendor, $printSimSeqsFile,$blastBinDir, $validOutput, $exitCode);

&GetOptions("pValCutoff=f" => \$pValCutoff, 
            "lengthCutoff=i"=> \$lengthCutoff,
            "percentCutoff=i" => \$percentCutoff,
            "outputType=s" => \$outputType,
            "blastProgram=s" => \$program,
            "database=s" => \$database,
            "seqFile=s" => \$seqFile,
            "dataFile=s" => \$dataFile,
            "adjustMatchLength!" => \$remMaskedRes,
            "blastParamsFile=s" => \$blastParamsFile,
            "saveAllBlastFiles=s" => \$saveAllBlastFiles,
            "saveGoodBlastFiles=s" => \$saveGoodBlastFiles,
            "doNotParse=s" => \$doNotParse,
            "printSimSeqsFile=s" => \$printSimSeqsFile,
	    );

die "Usage: blastSimilarity > --pValCutoff=<float> --lengthCutoff=<int> --percentCutoff=<int> --outputType=(summary|span|both) --blastProgram=<blastprogram> --database=<blast database> --seqFile=<sequenceFile>  --blastParams 'extra blast parameters' --adjustMatchLength! --saveAllBlastFiles! --saveGoodBlastFiles! --doNotParse! --printSimSeqsFile!\n" unless ( $program && $database && $seqFile);

###set the defaullts...
$pValCutoff = $pValCutoff ? $pValCutoff : 1e-5;
$lengthCutoff = $lengthCutoff ? $lengthCutoff : 10;
$percentCutoff = $percentCutoff ? $percentCutoff : 20;  ##low for blastp
$outputType = $outputType ? $outputType : "both";
$dataFile = $dataFile ? $dataFile : "blastSimilarity.out";
$regex = $regex ? $regex : '(\S+)';

my $blastParams = &parseBlastParams($blastParamsFile);

$blastVendor = "ncbi";
$blastBinDir = "/usr/bin/ncbi-blast-2.13.0+/bin";
$doNotExitOnBlastFailure = "false";

open(OUT, ">$dataFile") or print LOG "cannot open output file $dataFile for writing";
select OUT; $| = 1;
select STDOUT;

print LOG "processing $seqFile\n";
open(F, "$seqFile") || print LOG "Couldn't open seqfile $seqFile";
my $tmpid = "";
my $seq;
my $cmd;

my $pgm = basename($program);
$cmd = "$blastBinDir/$pgm -db $database -query $seqFile $blastParams";

print LOG "$cmd\n\n";
print LOG "Parser parameters and fields:\n";
print LOG "Cutoff parameters:\n\tP value: $pValCutoff\n\tLength: $lengthCutoff\n\tPercent Identity: $percentCutoff\n\n";
print LOG "# Sum: subject_Identifier:score:pvalue:minSubjectStart:maxSubjectEnd:minQueryStart:maxQueryEnd:numberOfMatches:totalMatchLength:numberIdentical:numberPositive:isReversed:readingFrame:non-redundant query match length:non-redundant subject match length:percent of shortest sequence matched\n";
print LOG "#   HSP: subject_Identifier:numberIdentical:numberPositive:matchLength:score:PValue:subjectStart:subjectEnd:queryStart:queryEnd:isReversed:readingFrame\n\n";

while(<F>){
    if(/^\>(\S+)/){
    $tmpid = $1;
    }
}
processEntry($cmd, $tmpid, $program);

close F;
close OUT;
close LOG;

######################### subroutines ###########################

sub parseBlastParams {
    my ($blastParamsFile) = @_;

    open(C, "$blastParamsFile") or print LOG "cannot open blastParams file $blastParamsFile";
    while(<C>){
	next if /^\s*#/;
	chomp;
	$blastParams .= "$_ ";
    }
    close(C);
    return $blastParams;
}

sub processEntry {
  my($cmd, $accession, $program) = @_;

  print LOG "processing $accession\n";
  my $validOutput;
  my $noHits;
  my $retry = 2;
  my $try = 1;
  do {
    # Create Non-xml output for checking and zipping
    system("$cmd > out.txt");
    ($validOutput, $noHits) =
	&checkOutput($accession);
  } while (!$validOutput && ($try++ < $retry));

  if (!$validOutput) {
      if($doNotExitOnBlastFailure eq "true"){
      print OUT "\>$accession (ERROR: BLAST failed ($try times).";
      return; 
    } else {
	system("cat out.txt > blast.out");
	if ($? != 0) {die "Failed to move contents of out.txt to blast.out"};
    }
  }
  if ($noHits==1) {
      print OUT "\>$accession (0 subjects)\n" unless ($printSimSeqsFile eq "true");
  } else {
	&analyzeBlast($accession);
  }
}

sub checkOutput {
    my ($accession) = @_;

    my ($validOutput, $noHits);

    if (`grep "no valid contexts" out.txt`) {
      print LOG "\>$accession blast failed on low complexity seq\n";
      $validOutput = 1;
      $noHits = 1;
    } elsif (my $res = `grep -A1 -E "nonnegok|novalidctxok|shortqueryok" out.txt`) {
        print LOG "\>$accession blast failed with: $res \n";
	$validOutput = 1;
	$noHits = 1;
    } elsif (`grep "Sequences producing" out.txt`) {
         $validOutput = 1;
	 $noHits = 0;
    }
}
  
sub analyzeBlast{
  my($accession) = @_;
  my $printSum = 0;
  my $printSpan = 0;
  if($outputType =~ /sum/i){
      $printSum = 1;
  }elsif($outputType =~ /span/i){
      $printSpan = 1;
  }elsif($outputType =~ /both/i){
      $printSum = 1;
      $printSpan = 1;
  }

  if($doNotParse eq "true"){ ##in this case must  be saving all blast files...
    my $blastOutFile = "$accession";
    system("touch '$blastOutFile'");
    if ($? != 0) {die "Failed to create blastOutFile $blastOutFile"};
    system("cat out.txt > '$blastOutFile'");
    if ($? != 0) {die "Failed to move contents of out.txt to blastOutFile $blastOutFile"};
    system("gzip -f '$blastOutFile'");
    if ($? != 0) {die "Failed to zip blastOutFile $blastOutFile"};
    system("/usr/bin/fixZip.pl -string '$blastOutFile.gz'");
    if ($? != 0) {die "Failed to run fixZip.pl on zipped blastOutFile $blastOutFile"}
    system("rm '$blastOutFile.gz'");
    if ($? != 0) {die "Failed to rm old zipfile $blastOutFile.gz"};
    return;
  }
  my $blast = BlastAnal->new($debug);
  my @blastn_out = `$cmd`;
  $blast->parseBlast($lengthCutoff,$percentCutoff,$pValCutoff,$regex,\@blastn_out,$remMaskedRes,($program =~ /rpsblast/ ? 1 : undef));
  
  if ($printSimSeqsFile eq "true"){
    &printSSFile($accession, $blast);
    return;
  }
  
  print OUT "\>$accession (".$blast->getSubjectCount()." subjects)\n";
  
  foreach my $s ($blast->getSubjects()){
    print OUT $s->getSimilaritySummary(":")."\n" if $printSum;
    print OUT $s->getSimilaritySpans(":")."\n" if $printSpan;
  }

  if(($saveAllBlastFiles eq "true" && $doNotParse eq "false") || ($saveGoodBlastFiles eq "true" && $blast->getSubjectCount() >= 1)){
    my $blastOutFile = "$accession";
    system("touch '$blastOutFile'");
    if ($? != 0) {die "Failed to create blastOutFile $blastOutFile"};
    system("cat out.txt > '$blastOutFile'");
    if ($? != 0) {die "Failed to move contents of out.txt to blastOutFile $blastOutFile"};
    system("gzip -f '$blastOutFile'");
    if ($? != 0) {die "Failed to zip blastOutFile $blastOutFile"};
    system("/usr/bin/fixZip.pl -string '$blastOutFile.gz'");
    if ($? != 0) {die "Failed to run fixZip.pl on zipped blastOutFile $blastOutFile"};
  } 
}

sub breakSequence{
  my($seq) = @_;
  my $s;
  my $formSeq = "";
  $seq =~ s/\s//g;  ##cleans up newlines and spaces
  for($s=0;$s<length($seq);$s+=80){
    $formSeq .= substr($seq,$s,80) . "\n";
  }
  return $formSeq;
}

sub printSSFile {
  my ($accession, $blast) = @_;

  my @q = split (/\|/, $accession); 
  my $qTaxAbbrev = shift(@q); # taxon is before the first pipe.  beware accession might also have pipes

  foreach my $s ($blast->sortSubjectsByPValue()){

    my $s_accession = $s->getID();
    next if $s_accession eq $accession;

    my ($mant, $exp);
    if ($s->getPValue() =~ /e/) {
      my $pValue = $s->getPValue() =~ /^e/ ?  '1' . $s->getPValue()  : $s->getPValue() ;
      ($mant, $exp) = split(/e/, $pValue);
    } else {
	$mant = int($s->getPValue());
	$exp = 0;
    }

    my @s = split (/\|/, $s->getID());
    my $sTaxAbbrev = shift(@s);

    my $perIdent = sprintf("%.0f", (($s->getTotalIdentities()/$s->getTotalMatchLength())*100));
    my $perMatch = sprintf("%.0f", (int(($s->getLength() < $s->getQueryLength() ? $s->getNonoverlappingSubjectMatchLength() / $s->getLength() : $s->getNonoverlappingQueryMatchLength() / $s->getQueryLength()) * 10000) / 100));

    # accessions must include taxon abbrev prefix
    print OUT "$accession $s_accession $qTaxAbbrev $sTaxAbbrev $mant $exp $perIdent $perMatch\n";
  }
  }
