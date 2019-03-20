package App::linerange;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use List::Util qw(max);

use Exporter qw(import);
our @EXPORT_OK = qw(linerange);

our %SPEC;

$SPEC{linerange} = {
    v => 1.1,
    summary => 'Retrieve line ranges from a filehandle',
    description => <<'_',

The routine performs a single pass on the filehandle, retrieving specified line
ranges.


_
    args => {
        fh => {
            schema => 'filehandle*',
            req => 1,
        },
        spec => {
            summary => 'Line range specification',
            description => <<'_',

A comma-separated list of line numbers ("N") or line ranges ("N1..N2" or
"N1-N2", or "N1+M" which means N2 is N1+M-1 if N1 is positive or N1-M-1 if N1 is
negative), where N, N1, and N2 are line number specification and M is a
non-negative number. Line number begins at 1; it can also be a negative integer
(-1 means the last line, -2 means second last, and so on). N1..N2 is the same as
N2..N1.

Examples:

* 3 (third line)
* 1..5 (first to fifth line)
* 3+0 (third line)
* 3+1 (third to fourth line)
* -3+1 (third last to fourth last)
* 5..1 (first to fifth line)
* -5..-1 (fifth last to last line)
* -1..-5 (fifth last to last line)
* 5..-3 (fifth line to third last)
* -3..5 (fifth line to third last)

_
            schema => 'str*',
            req => 1,
            pos => 0,
        },
    },
    examples => [
        {
            summary => 'Get lines 1-10',
            args => {spec=>'1-10'},
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Get lines 1 to 10, .. is synonym for -',
            args => {spec=>'1 .. 10'},
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Get lines 1-10 as well as 21-30',
            args => {spec=>'1-10, 21 - 30'},
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'You can specify negative number, get the 5th line until 2nd last',
            args => {spec=>'5 .. -2'},
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'You can specify negative number, get the 10th last until last',
            args => {spec=>'-10 .. -1'},
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],
};

sub linerange {
    my %args = @_;

    my $fh = $args{fh} // \*ARGV;

    my @ranges;
    my @buffer;
    my $bufsize = 0;
    my $exit_after_line = 0;
    for my $spec2 (split /\s*,\s*/, $args{spec}) {
        $spec2 =~ /\A\s*([+-]?[0-9]+)\s*(?:(\.\.|-|\+)\s*([+-]?[0-9]+)\s*)?\z/
            or return [400, "Invalid line number/range specification '$spec2'"];

        my $ln1 = $1;
        my $ln2 = $3 // $1;
        if (defined $2 && $2 eq '+') {
            return [400, "Invalid line range specification '$spec2'"]
                unless $ln2 >= 0;
            $ln2 = $ln1 + ($ln1 < 0 ? -1:1) * $ln2;
        }

        if ($ln1 == 0 || $ln2 == 0) {
            return [400, "Invalid line number 0 in ".
                        "range specification '$spec2'"];
        } elsif ($ln1 > 0 && $ln2 > 0) {
            push @ranges, $ln1 > $ln2 ? [$ln2, $ln1] : [$ln1, $ln2];
            unless ($exit_after_line < 0) {
                $exit_after_line = $ln1 if $exit_after_line < $ln1;
                $exit_after_line = $ln2 if $exit_after_line < $ln2;
            }
        } elsif ($ln1 < 0 && $ln2 < 0) {
            $bufsize = -$ln1 if $bufsize < -$ln1;
            $bufsize = -$ln2 if $bufsize < -$ln2;
            push @ranges, $ln1 > $ln2 ? [$ln1, $ln2] : [$ln2, $ln1];
            $exit_after_line = -1;
        } else {
            $exit_after_line = -1;
            if ($ln1 > 0) {
                $bufsize = -$ln2 if $bufsize < -$ln2;
                push @ranges, [$ln1, $ln2];
            } else {
                $bufsize = -$ln1 if $bufsize < -$ln1;
                push @ranges, [$ln2, $ln1];
            }
        }
    }

    my %reslines; # result lines, key = linenum
    my $linenum = 0;
    while (defined(my $line = <$fh>)) {
        $linenum++;
        last if $exit_after_line >= 0 && $linenum > $exit_after_line;
        if ($bufsize) {
            push @buffer, $line;
            if (@buffer > $bufsize) { shift @buffer }
        }
        for my $range (@ranges) {
            next unless
                $range->[0] > 0 && $linenum >= $range->[0] &&
                ($range->[1] < 0 ||
                 $range->[1] > 0 && $linenum <= $range->[1]);
            $reslines{$linenum} = $line;
        }
    }

    my $bufstartline = $linenum - @buffer + 1;

    # remove positive-only ranges
    @ranges = grep { $_->[1] < 0 } @ranges;

    # add/remove result lines that are in the buffer
    for my $stage (0..1) {
        for my $range (@ranges) {
            my $bufpos1 = $range->[0] > 0 ?
                max($range->[0] - $bufstartline, 0) :
                $linenum + $range->[0] + 1 - $bufstartline;
            my $bufpos2 = $linenum + $range->[1] + 1 - $bufstartline;
            ($bufpos1, $bufpos2) = ($bufpos2, $bufpos1) if $bufpos1 > $bufpos2;
            if ($stage == 0) {
                for my $offset ((0 .. $bufpos1-1), ($bufpos2+1 .. $#buffer)) {
                    delete $reslines{ $bufstartline + $offset };
                }
            } else {
                for my $offset ($bufpos1 .. $bufpos2) {
                    $reslines{ $bufstartline + $offset } = $buffer[$offset];
                }
            }
        }
    }

    [200, "OK", [map {$reslines{$_}} sort {$a <=> $b} keys %reslines]];
}

1;
# ABSTRACT:

=cut
