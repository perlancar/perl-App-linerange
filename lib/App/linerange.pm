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

A comma-separated list of empty strings ("", which means all lines), specific
line numbers ("N") or line ranges ("N1..N2" or "N1-N2", or "N1+M" which means N2
is set to N1+M), where N, N1, and N2 are line number specification. Line number
begins at 1; it can also be a negative integer (-1 means the last line, -2 means
second last, and so on). N1..N2 is the same as N2..N1. Each line or range can
optionally be followed by "/M" to mean every M'th line (where M is an integer
starting from 1).

Examples:

* 3 (third line)
* 1..5 (first to fifth line)
* 3+0 (third line)
* 3+1 (third to fourth line)
* -3+1 (third last to second last)
* 5..1 (first to fifth line)
* -5..-1 (fifth last to last line)
* -1..-5 (fifth last to last line)
* 5..-3 (fifth line to third last)
* -3..5 (fifth line to third last)
* /3 (every 3rd line, i.e. 3, 6, 9, ...)
* /2 (every other line, i.e. 2, 4, 6, ...)
* 2..-1/3 (every 3rd line starting from line 2, i.e. 4, 7, 10, ...)

_
            schema => 'str',
            default => '',
            pos => 0,
        },
    },
    examples => [
        {
            summary => 'By default, if spec is empty, get all lines',
            args => {},
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Get every other lines',
            args => {spec=>'/2'},
            test => 0,
            'x.doc.show_result' => 0,
        },
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
        {
            summary => 'Instead of N1-N2, you can use N1+M to mean N1-(N1+M), get 3rd line',
            args => {spec=>'3+0'},
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Instead of N1-N2, you can use N1+M to mean N1-(N1+M), get 3rd to 5th line',
            args => {spec=>'3+2'},
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Instead of N1-N2, you can use N1+M to mean N1-(N1+M), get 3rd last to last line',
            args => {spec=>'-3+2'},
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
    my $exit_after_linum = 0; # set this to a positive line number if we can optimize

    my @simple_specs = split /\s*,\s*/, $args{spec};
    @simple_specs = ('') unless @simple_specs;

    for my $spec2 (@simple_specs) {
        $spec2 =~ m!\A\s*
                   (?:
                       ([+-]?[0-9]+)        # 1) start
                       \s*
                       (?:
                           (\.\.|-|\+)\s*   # 2) range 'operator'
                           ([+-]?[0-9]+)\s* # 3) end
                       )?
                   )?
                   (?:
                       /\s*
                       ([0-9]+)             # 4) every
                   )?
                   \z!x
            or return [400, "Invalid line number/range specification '$spec2'"];

        my ($ln1, $ln2, $every);
        if (!defined $1 && !defined $2) {
            $ln1 = 1;
            $ln2 = -1;
        } else {
            $ln1 = $1;
            $ln2 = $3 // $1;
            if (defined $2 && $2 eq '+') {
                $ln2 = $ln1 + $ln2;
                if ($ln1 > 0) {
                    $ln2 = 1 if $ln2 < 1;
                } else {
                    $ln2 = -1 if $ln2 > -1;
                }
            }
        }
        $every = $4 // 1;
        if ($every == 0) {
            return [400, "Invalid 0 in every in range specification '$spec2', ".
                        "start from 1"];
        }

        if ($ln1 == 0 || $ln2 == 0) {
            return [400, "Invalid line number 0 in ".
                        "range specification '$spec2', start from 1"];
        } elsif ($ln1 > 0 && $ln2 > 0) {
            push @ranges, $ln1 > $ln2 ?
                [$ln2, $ln1, $every] : [$ln1, $ln2, $every];
            unless ($exit_after_linum < 0) {
                $exit_after_linum = $ln1 if $exit_after_linum < $ln1;
                $exit_after_linum = $ln2 if $exit_after_linum < $ln2;
            }
        } elsif ($ln1 < 0 && $ln2 < 0) {
            $bufsize = -$ln1 if $bufsize < -$ln1;
            $bufsize = -$ln2 if $bufsize < -$ln2;
            push @ranges, $ln1 > $ln2 ?
                [$ln1, $ln2, $every] : [$ln2, $ln1, $every];
            $exit_after_linum = -1;
        } else {
            $exit_after_linum = -1;
            if ($ln1 > 0) {
                $bufsize = -$ln2 if $bufsize < -$ln2;
                push @ranges, [$ln1, $ln2, $every];
            } else {
                $bufsize = -$ln1 if $bufsize < -$ln1;
                push @ranges, [$ln2, $ln1, $every];
            }
        }
    }

    my %reslines; # result lines, key = linenum
    my $linenum = 0;
    while (defined(my $line = <$fh>)) {
        $linenum++;
        last if $exit_after_linum >= 0 && $linenum > $exit_after_linum;
        if ($bufsize) {
            push @buffer, $line;
            if (@buffer > $bufsize) { shift @buffer }
        }
        for my $range (@ranges) {
            # check if line is included by range (N1-N2)
            next unless
                $range->[0] > 0 && $linenum >= $range->[0] &&
                ($range->[1] < 0 ||
                 $range->[1] > 0 && $linenum <= $range->[1]);
            # check if line is included by every (N3)
            say "D:linenum=$linenum, range=".join(",",@$range).", ".($linenum-1 - $range->[0]+1)." % $range->[2] == ".(($linenum-1 + $range->[0]-1) % $range->[2]);
            next unless $range->[0] > 0 && (($linenum-1 - $range->[0]+1) % $range->[2] == $range->[2]-1);
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
                    # check with every again
                    next unless ($offset % $range->[2] == $range->[2]-1);
                    #say "D:adding result line in buffer: offset=$offset, linenum=".($bufstartline + $offset);
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
