#!/usr/bin/perl
# H2 CPU disassembler
# Either read from file, or given an individual number, disable it
#
# TODO:
#   * command line options
#     - single word to disassemble
#     - entire file with filename defaulting to mem_h2.hexadecimal
#     - different input bases
#     - help message
#     - package (separate from this file) for both the assembler
#       and disassembler.
#     - disassemble until jump 0
#     - disassemble range
#   * the actual disassembler
#   * verbosity levels

use warnings;
use strict;

my $inputfile  = "mem_h2.hexadecimal";
my $outputfile = "mem_h2.dis";
my $inputbase = 16;
my $memsize   = 8192;

my $linecount = 0; 

sub disassemble($){
  my $code   = $_[0];
  my $dis    = "invalid";
  
  if($code & 0x8000){
    $dis = "literal\t" . ($code & 0x7FFF);
  } elsif($code & 0x6000){
    $dis = "alu\t" . ($code & 0x3FFF);
  } elsif($code & 0x4000){
    $dis = "call\t" . ($code & 0x3FFF);
  } elsif($code & 0x2000){
    $dis = "jumpc\t". ($code & 0x3FFF);
  } else {
    $dis = "jump\t". ($code & 0x3FFF);
  }

  return $dis;
}

my $previouscode = 0;
my $isrun = 0;

open INPUT, "<", $inputfile or die "unable to open $inputfile for reading\n";
open OUTPUT,">", $outputfile or die "unable to open $outputfile for writing\n";
while(<INPUT>){
  my $inputline = $_;
  my $code = 0;

  $inputline =~ s/\s+//g;
  if ($inputbase == 16){
    $code = hex $inputline;
  } else {
    die "invalid or unimplemented input base.\n";
  }

  if($isrun){
    if($code != $previouscode){
      $isrun = 0;
    }
  } elsif($code == $previouscode){
    printf OUTPUT "%04d:\t%s\t%05d\t%s\n", 
      $linecount, $inputline, $code , &disassemble($code); 
    print OUTPUT "....:\t...\t.....\t...\n";
    $isrun = 1;
  } elsif($code != $previouscode) {
    printf OUTPUT "%04d:\t%s\t%05d\t%s\n", 
      $linecount, $inputline, $code , &disassemble($code); 
  }
  $previouscode = $code;
  $linecount++;
}

if (not ($linecount == $memsize)){
  print "invalid input size? expected more, only $linecount given.\n";
}
close INPUT;
close OUTPUT;
