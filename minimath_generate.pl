#!/usr/bin/perl
use strict;
use warnings;
use feature qw(say);
use List::Util qw(min);
use List::MoreUtils qw(pairwise);

open OUT, ">minimath_generated.h" or die "Couldn't open the target header";

say OUT "// THIS IS AUTO-GENERATED BY $0. DO NOT EDIT BY HAND\n";

my @sizes = 2..5;

# the dot products, norms and basic arithmetic functions take the size as an
# argument. I'm assuming that the compiler will expand these out for each
# particular invocation
dotProducts();
norms();
vectorArithmetic();

foreach my $n(@sizes)
{
  matrixVectorSym($n);
  foreach my $m (@sizes){ matrixVectorGen($n, $m) }
  matrixMatrixSym($n);
  matrixMatrixGen($n);
}

# this is only defined for N=3. I haven't made the others yet and I don't yet need them
matrixMatrixMatrixSym(3);

close OUT;





sub dotProducts
{
  say OUT <<EOC;
static inline double dot_vec(int n, const double* restrict a, const double* restrict b)
{
  double dot = 0.0;
  for(int i=0; i<n; i++)
    dot += a[i]*b[i];
  return dot;
}
EOC
}

sub norms
{
  say OUT <<EOC;
static inline double norm2_vec(int n, const double* restrict a)
{
  double dot = 0.0;
  for(int i=0; i<n; i++)
    dot += a[i]*a[i];
  return dot;
}
EOC
}

sub vectorArithmetic
{
  my $vout = <<EOC;
// a + b
static inline void add_vec_vout(int n, const double* restrict a, const double* restrict b, double* restrict vout)
{
  for(int i=0; i<n; i++)
    vout[i] = a[i] + b[i];
}
// a - b
static inline void sub_vec_vout(int n, const double* restrict a, const double* restrict b, double* restrict vout)
{
  for(int i=0; i<n; i++)
    vout[i] = a[i] - b[i];
}

EOC

  say OUT $vout;
  say OUT _makeScaled_arithmetic($vout);

  my $arg0     = _getFirstDataArg($vout);
  my $vinplace = _makeInplace_mulVector($vout, $arg0);

  say OUT $vinplace;
  say OUT _makeScaled_arithmetic($vinplace);
  say OUT _makeVaccum ($vout);
}

sub matrixVectorSym
{
  my $n = shift;

  my $vout = <<EOC;
// $n-vector by symmetric ${n}x$n
static inline void mul_vec${n}_sym$n${n}_vout(const double* restrict v, const double* restrict s, double* restrict vout)
{
EOC

  # I now have the header, opening brace. Writing each row element output
  my %isymHash = (next => 0);

  for my $i(0..$n-1)
  {
    my $isym_row = _getSymmetricIndices_row(\%isymHash, $i, $n);
    my @cols = 0..$n-1;

    our ($a,$b);
    my @sum_components = pairwise {"s[$a]*v[$b]"} @$isym_row, @cols;
    $vout .= "  vout[$i] = " . join(' + ', @sum_components) . ";\n";
  }

  $vout .= "}\n";


  print OUT _multiplicationVersions($vout, $n, $n);
}


sub matrixVectorGen
{
  my $n = shift;
  my $m = shift;

  # I now make NxM matrix-vector multiplication. I describe matrices math-style
  # with the number of rows first (NxM has N rows, M columns). I store the
  # matrices row-first and treat vectors as row-vectors. Thus these functons
  # compute v*A where v is the row vector and A is the NxM matrix

  my $vout = <<EOC;
// $n-vector by ${n}x$m matrix multiplication
static inline void mul_vec${n}_gen$n${m}_vout(const double* restrict v, const double* restrict m, double* restrict vout)
{
EOC

  # I now have the header, opening brace. Writing each row element output
  for my $i(0..$m-1)
  {
    my @js = 0..$n-1;
    my @im = map {$i + $_*$m} @js;

    our ($a,$b);
    my @sum_components = pairwise {"m[$a]*v[$b]"} @im, @js;
    $vout .= "  vout[$i] = " . join(' + ', @sum_components) . ";\n";
  }

  $vout .= "}\n";
  print OUT _multiplicationVersions($vout, $m, $n);


# now the transposed version
  $vout = <<EOC;
// $n-vector by ${m}x$n-transposed matrix multiplication
static inline void mul_vec${n}_gen$m${n}t_vout(const double* restrict v, const double* restrict mt, double* restrict vout)
{
EOC

  # I now have the header, opening brace. Writing each row element output
  for my $i(0..$m-1)
  {
    my @js = 0..$n-1;
    my @im = map {$i*$n + $_} @js;

    our ($a,$b);
    my @sum_components = pairwise {"mt[$a]*v[$b]"} @im, @js;
    $vout .= "  vout[$i] = " . join(' + ', @sum_components) . ";\n";
  }

  $vout .= "}\n";
  print OUT _multiplicationVersions($vout, $m,$n);
}

sub matrixMatrixSym
{
  my $n = shift;

  # I now make NxM matrix-vector multiplication. I describe matrices math-style
  # with the number of rows first (NxM has N rows, M columns). I store the
  # matrices row-first and treat vectors as row-vectors. Thus these functons
  # compute v*A where v is the row vector and A is the NxM matrix

  my $vout = <<EOC;
// general Nx$n matrix by symmetric ${n}x$n, written into a new Nx$n
static inline void mul_genN${n}_sym${n}${n}_vout(int n, const double* restrict v, const double* restrict s, double* restrict vout)
{
  for(int i=0; i<n; i++)
    mul_vec${n}_sym${n}${n}_vout(v + $n*i, s, vout + $n*i);
}
EOC

  print OUT _multiplicationVersions($vout);
}

sub matrixMatrixMatrixSym
{
  my $n = shift;
  die 'matrixMatrixMatrixSym ONLY defined for $n==3 right now' if $n != 3;


  print OUT <<'EOC';
// (%i2) sym3 : matrix([m0,m1,m2],
//                      [m1,m3,m4],
//                      [m2,m4,m5]);

// (%o2) matrix([m0,m1,m2],[m1,m3,m4],[m2,m4,m5])
// (%i3) sym3_a : matrix([a0,a1,a2],
//                       [a1,a3,a4],
//                       [a2,a4,a5]);

// (%o3) matrix([a0,a1,a2],[a1,a3,a4],[a2,a4,a5])
// (%i4) sym3_b : matrix([b0,b1,b2],
//                       [b1,b3,b4],
//                       [b2,b4,b5]);

// (%o4) matrix([b0,b1,b2],[b1,b3,b4],[b2,b4,b5])
// (%i5) sym3_a . sym3_b . sym3_a;

// (%o5) matrix([a2*(a2*b5+a1*b4+a0*b2)+a1*(a2*b4+a1*b3+a0*b1) + a0*(a2*b2+a1*b1+a0*b0), a2*(a4*b5+a3*b4+a1*b2)+a1*(a4*b4+a3*b3+a1*b1) + a0*(a4*b2+a3*b1+a1*b0), a2*(a5*b5+a4*b4+a2*b2)+a1*(a5*b4+a4*b3+a2*b1) + a0*(a5*b2+a4*b1+a2*b0)],
//              [a4*(a2*b5+a1*b4+a0*b2)+a3*(a2*b4+a1*b3+a0*b1) + a1*(a2*b2+a1*b1+a0*b0), a4*(a4*b5+a3*b4+a1*b2)+a3*(a4*b4+a3*b3+a1*b1) + a1*(a4*b2+a3*b1+a1*b0), a4*(a5*b5+a4*b4+a2*b2)+a3*(a5*b4+a4*b3+a2*b1) + a1*(a5*b2+a4*b1+a2*b0)],
//              [a5*(a2*b5+a1*b4+a0*b2)+a4*(a2*b4+a1*b3+a0*b1) + a2*(a2*b2+a1*b1+a0*b0), a5*(a4*b5+a3*b4+a1*b2)+a4*(a4*b4+a3*b3+a1*b1) + a2*(a4*b2+a3*b1+a1*b0), a5*(a5*b5+a4*b4+a2*b2)+a4*(a5*b4+a4*b3+a2*b1) + a2*(a5*b2+a4*b1+a2*b0)])
EOC

  my $vout = <<'EOC';
// symmetric A * B * A
static inline void mul_sym33_sym33_sym33_vout(const double* restrict a, const double* restrict b, double* restrict vout)
{
  double t0 = a2*b5+a1*b4+a0*b2;
  double t1 = a2*b4+a1*b3+a0*b1;
  double t2 = a2*b2+a1*b1+a0*b0;
  double t3 = a4*b2+a3*b1+a1*b0;
  double t4 = a4*b5+a3*b4+a1*b2;
  double t5 = a4*b4+a3*b3+a1*b1;

  vout[0] = a2*t0+a1*t1+a0*t2;
  vout[1] = a4*t0+a3*t1+a1*t2;
  vout[2] = a5*t0+a4*t1+a2*t2;
  vout[3] = a4*t4+a3*t5+a1*t3;
  vout[4] = a5*t4+a4*t5+a2*t3;
  vout[5] = a5*(a5*b5+a4*b4+a2*b2)+a4*(a5*b4+a4*b3+a2*b1) + a2*(a5*b2+a4*b1+a2*b0);
}
EOC

  print OUT $vout;
}

sub matrixMatrixGen
{
  my $n = shift;

  # I now make NxM matrix-vector multiplication. I describe matrices math-style
  # with the number of rows first (NxM has N rows, M columns). I store the
  # matrices row-first and treat vectors as row-vectors. Thus these functons
  # compute v*A where v is the row vector and A is the NxM matrix

  my $vout = <<EOC;
// general Nx${n} matrix by general ${n}x${n}, written back into the Nx${n}
static inline void mul_genN${n}_gen${n}${n}_vout(int n, double* restrict v, const double* restrict m, double* restrict vout)
{
  for(int i=0; i<n; i++)
    mul_vec${n}_gen${n}${n}_vout(v + $n*i, m, vout + $n*i);
}

// general Nx${n} matrix by general ${n}x${n}, written back into the Nx${n}
static inline void mul_genN${n}_gen${n}${n}t_vout(int n, double* restrict v, const double* restrict mt, double* restrict vout)
{
  for(int i=0; i<n; i++)
    mul_vec${n}_gen${n}${n}t_vout(v + $n*i, mt, vout + $n*i);
}

EOC

  print OUT _multiplicationVersions($vout);
}







sub _multiplicationVersions
{
  my $vout = shift;
  my $n    = shift;
  my $m    = shift;

  my $arg0 = _getFirstDataArg($vout);

  my $funcs = $vout . "\n";
  $funcs .= (defined $n ?
             _makeInplace_mulVector($vout, $arg0, $n, $m) : _makeInplace_mulMatrix($vout) ) . "\n";
  $funcs .= _makeVaccum ($vout) . "\n";
  $funcs .= (defined $n ?
             _makeScaled_mulVector ($funcs) : _makeScaled_mulMatrix ($funcs) ) . "\n";

  return $funcs;
}

sub _getSymmetricIndices_row
{
  my $hash     = shift;
  my $i        = shift;
  my $n        = shift;

  my @isym;
  for my $j (0..$n-1)
  {
    my $key = join(',', sort($i,$j));
    if( !exists $hash->{$key} )
    {
      $hash->{$key} = $hash->{next};
      $hash->{next}++;
    }

    push @isym, $hash->{$key};
  }

  return \@isym;
}

sub _getFirstDataArg
{
  my $v = shift;

  # I have a string with a bunch of functions. Get the first argument. I ASSUME
  # THE FIRST ARGUMENT HAS THE SAME NAME IN ALL OF THESE
  my ($arg0) = $v =~ m/^static inline.*\(.*?double\* restrict ([a-z0-9_]+),/m or die "Couldn't recognize function in '$v'";
  return $arg0;
}

sub _makeInplace_mulVector
{
  my $v       = shift;
  my $arg0    = shift;
  my $n       = shift;
  my $m       = shift;

  # rename functions
  $v =~ s/_vout//gm;

  # get rid of the 'vout argument'
  $v =~ s/, double\* restrict vout//gm;

  # un-const first argument
  $v =~ s/^(static inline.*\(.*?)const (double.*)$/$1$2/gm;

  # use the first argument instead of vout
  $v =~ s/vout/$arg0/gm;

  # if we're asked to make some temporary variables, do it
  if(defined $n)
  {
    # if no $m is given, use $m;
    $m //= $n;

    my $nt = min($n-1,$m);

    # use the temporaries instead of the main variable when possible
    foreach my $t(0..$nt-1)
    {
      $v =~ s/(=.*)${arg0}\[$t\]/$1t[$t]/mg;
    }

    # define the temporaries. I need one fewer than n
    my $tempDef = "  double t[$nt] = {" . join(', ', map {"${arg0}[$_]"} 0..$nt-1) . "};";
    $v =~ s/^{$/{\n$tempDef/mg;
  }

  return $v;
}
sub _makeInplace_mulMatrix
{
  my $v       = shift;

  # rename functions
  $v =~ s/_vout//gm;

  # get rid of the 'vout argument'
  $v =~ s/, double\* restrict vout//gm;

  # un-const first argument
  $v =~ s/^(static inline.*\(.*?)const (double.*)$/$1$2/gm;

  # use the first argument instead of vout
  $v =~ s/,[^\),]*vout[^\),]*([\),])/$1/gm;

  return $v;
}

sub _makeVaccum
{
  my $v    = shift;

  # rename functions
  $v =~ s/_vout/_vaccum/gm;

  # vout -> vaccum
  $v =~ s/vout/vaccum/gm;

  # make sure we accumulate
  $v =~ s/(vaccum\[.*?\]\s*)=/$1+=/gm;

  return $v;
}

sub _makeScaled_arithmetic
{
  my $f = shift;

  # rename functions
  $f =~ s/^(static inline .*)(\s*\()/${1}_scaled$2/gm;

  # add the scale argument
  $f =~ s/^(static inline .*)\)$/$1, double scale)/gm;

  # apply the scaling
  $f =~ s/([+-]) b/$1 scale*b/gm;

  return $f;
}

sub _makeScaled_mulVector
{
  my $f = shift;

  # rename functions
  $f =~ s/^(static inline .*)(\s*\()/${1}_scaled$2/gm;

  # add the scale argument
  $f =~ s/^(static inline .*)\)$/$1, double scale)/gm;

  # apply the scaling
  $f =~ s/(.*=\s*)([^{}]*?);$/${1}scale * ($2);/gm;

  return $f;
}

sub _makeScaled_mulMatrix
{
  my $f = shift;

  # rename functions
  $f =~ s/^(static inline .*)(\s*\()/${1}_scaled$2/gm;

  # add the scale argument
  $f =~ s/^(static inline .*)\)$/$1, double scale)/gm;

  # apply the scaling. This is simply an argument to the vector function I call
  $f =~ s/^(\s*mul_.*)(\).*)/$1, scale$2/gm;

  # apply the scaling. Call the _scaled vector function
  $f =~ s/^(\s*mul_.*?)(\s*\()/${1}_scaled$2/gm;

  return $f;
}
