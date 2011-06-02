package QtQA::Test::More;
use strict;
use warnings;

use Test::More;

use base 'Exporter';
our @EXPORT_OK = qw(
    is_or_like
);

sub is_or_like      ## no critic (Subroutines::RequireArgUnpacking) - needed for goto
{
    my ($actual, $expected, $testname) = @_;

    return if !defined($expected);

    if (ref($expected) eq 'Regexp') {
        if ($testname) {
            $testname .= ' (regex match)';
            $_[2]      = $testname;
        }
        goto &like;
    }

    if ($testname) {
        $testname .= ' (exact match)';
        $_[2]      = $testname;
    }
    goto &is;
}

=head1 NAME

QtQA::Test::More -  a handful of test utilities in the spirit of Test::More

=head1 SYNOPSIS

  use Test::More;
  use QtQA::Test::More;

  # use regular Test::More functions where appropriate...
  is( $actual, $expected, 'value is as expected' );

  # ... and additional QtQA::Test::More functions where useful
  is_or_like( $actual, $expected, 'value matches expected' );

This module holds various test helper functions which have been found useful
when writing autotests for the scripts in this repository.

Any code which is used in more than one test, and not readily provided by an existing
CPAN module, is a candidate for addition to this module.

This module does not export any methods by default.

=head1 METHODS

=over

=item B<is_or_like>( ACTUAL, EXPECTED, [ TESTNAME ] )

If EXPECTED is a reference to a Regexp, calls L<Test::More::like> with the given
parameters.

Otherwise, calls L<Test::More::is>.

In the testlog, TESTNAME will have the string ' (exact match)' or ' (regex match)'
appended to it, so that it is clear which form of comparison was used.

This function is intended for use in specifying sets of testdata where most of the
data can be specified precisely, but some cases require matching instead.  For
example:

  # check various system commands work as expected
  my %TESTDATA = (
    # basic check for working shell
    'echo' => {
      command          => [ '/bin/sh', '-c', 'echo Hello' ],
      expected_stdout  => "Hello\n",    # precisely specified
      expected_stderr  => "",           # precisely specified
    },
    # make sure mktemp respects --tmpdir and TEMPLATE as we expect
    'mktemp' => {
      command          => [ '/bin/mktemp', '--dry-run', '--tmpdir=/custom', 'my-dir.XXXXXX' ],
      expected_stdout  => qr{\A /custom/my-dir \. [a-zA-Z0-9]{6} \n \z}xms, # can't be precise
      expected_stderr  => "",                                               # precisely specified
    },
  );

  # ... and later:
  while (my ($testname, $testdata) = each %TESTDATA) {
    my ($stdout, $stderr) = capture { system( @{$testdata->{command}} ) };

    is_or_like( $stdout, $testdata->{ expected_stdout } );
    is_or_like( $stderr, $testdata->{ expected_stderr } );
  }


=back

=cut

1;
