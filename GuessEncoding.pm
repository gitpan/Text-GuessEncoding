package Text::GuessEncoding;

use warnings;
use strict;

=head1 NAME

Text::GuessEncoding - convert Text from almost any encoding to ASCII or UTF8

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.03';


=head1 SYNOPSIS

Text::GuessEncoding searches a string for non-ascii contents and
rewrites them using an ASCII replacement.  For Example the german a-Umlaut
character is replaced by "ae". The input string may or may not have its utf8
flag set correctly; the flag is ignored. The returned string has the utf8 flag 
always off, and contains no characters above codepoint 127 (which means it is inside 
the ASCII character set).  If called in a list context, C<to_ascii()> returns the mapping
table as a second value.  This mapping table is a hash, using all recognized
encodings as keys. (Any well-formed string should only have one encoding, but
one can never be sure.) Value per encoding is an array ref, listing all the
codepoints in the following form:
C<[ [ $codepoint, $replacement_bytecount, [ $offset, ... ] ], ... ]>
Offset positions refer to the output string, where byte counts are identical
with character counts.

Example:
  
  my $guess = new Text::GuessEncoding();
  ($ascii, $map) = $guess->to_ascii("J\x{fc}rgen \x{c3}\x{bc}\n");
  # $ascii = 'Juergen ue';
  # $map = { 'utf8' => [252, 2, [8]], 'latin1' => [252, 2, [1]] };

The input string contains both utf8 encoded u-umlaut glyph and a plain latin1 byte u-umlaut.
The output string is never flagged as utf8.

  ($utf8, $map) = $guess->to_utf8("J\x{fc}rgen \x{c3}\x{bc}\n");
  # $utf8 = 'J\N{U+fc}rgen \N{U+fc}';
  # $map = { 'utf8' => [7], 'latin1' => [1] };
  
C<to_utf8> returns a simpler mapping table, as the string preserves more inforation. 
Note that the offsets differ from to_ascii(), as no multi-character rewriting takes place.
The output string is always flagged as utf8.

    use Text::GuessEncoding;

    my $asciitext = Text::GuessEncoding::to_ascii($enctext);
    my ($asciitext,$mapping) = Text::GuessEncoding::to_ascii($enctext);

=head1 EXPORT

C<to_ascii()> - create plain text in 7-bit ASCII encoding.
C<to_utf8()> - return UTF-8 encoded text .

=head1 SUBROUTINES/METHODS

=head2 to_ascii

C<to_ascii()> is implemented in perl code as a post-processor of C<to_utf8()>.
It examines C<charnames::viacode($_)> and constructs some useful ascii replacements from these.
A number of frequently used codepoint values can be precompiled for speed.

=cut

sub to_ascii 
{
  my ($text) = @_;

  # run through the text, searching a byte with the high order bit set.
  # this then, is a non-ascii byte, and needs conversion.

  # We distinguish two cases here:
  # $text might know that it is utf8, or $text might believe it is not.

  if (utf8::is_utf8($text))
    {
      warn "to_ascii() running on a utf8 string";
    }
  else
    {
      use Data::Dumper;
      ## exmine the first 24 bytes to guess if this is a 16bit encoding
      warn "to_ascii() running on a non-utf8 string";
      my @bytes = unpack("C24", $text);
      print Dumper \@bytes;
    }

  while ($text =~ m{[[:^ascii:]]}g)
    {
      printf "non-ascii char at pos %d\n", pos($text);
    }
}

##
## if utf8_valid is positive, then it can only be utf-8.
##   (if also utf8_invalid and/or latin1_typ are positive, then it is a mixture)
## if only utf8_invalid or latin1_typ are positive, then it is latin1.
## if all 3 are zero, it is plain ascii.
##
## FIXME: should take an optional length parameter to limit runtime.
##
sub probe_file
{
  my ($fd, $name) = @_;
  print "probing $name\n" if $verbose;

  my %typ_latin = map { $_ => 1 } qw(169 171  174 176 177 178 179 181
  185 187 191 192 193 194 195 196 197 199 200 201 202 203 204 205 206 207 208 209
  210 211 212 213 214 215 216 217 218 219 220 
  223 224 225 226 227 228 229 230 231 232 233 234 235 236 237 238 239 240 241 242 243 244 245
  246 249 250 251 252 253 189 164);


  # when running incremental, $fd is probably not seekable.
  # so we need to buffer characters to be re-read after a lookahead.

  # http://de.wikipedia.org/wiki/UTF-8#Kodierung

  my $utf8_valid   = 0;		# parser happy.
  my $utf8_invalid = 0;		# something wrong.
  my $latin1_typ   = 0;		# valid chars in 128..255 range followed by a ascii byte
  my $ascii        = 0;		# char in 10..127 range
  my $utf8_size    = 0;		# how many bytes belong to this utf-8 char.
  my $utf8_len     = 0;		# how many more bytes belong to this utf-8 char.
  my $utf8_start   = 0;		# ord of utf_8 start char.

  while (defined(my $c = getc($fd)))
    {
      my $v = ord($c);
      if ($utf8_len)
        {
	  if (($v & 0xc0) == 0x80)	# 10xx xxxx
	    {
#	      printf "0 %02x\n", $v;
	      unless (--$utf8_len)
	        {
	          $utf8_valid++;
		  $utf8_size = 0;
		}
	    }
	  else
	    {
#	      printf "0x %02x %02x '$c' $utf8_size-$utf8_len\n", $utf8_start, $v;
              if (($utf8_size - $utf8_len) == 1 and $typ_latin{$utf8_start})
		{
		  if ($v > 7 && $v < 128)
		    {
		      $latin1_typ++;
		      $ascii++;
		    }
		  elsif ($typ_latin{$v})
		    {
		      $latin1_typ += 2;
		    }
		  else
		    {
		      $utf8_invalid++;
		    }
		}
	      else
		{
		  $utf8_invalid++;
		}
	      $utf8_len = $utf8_size = $utf8_start = 0;
	    }
	}
      elsif ($v > 7 && $v < 128)
        {
	  $ascii++;
	  next;
	}
      elsif (($v & 0xe0) == 0xc0)	 	# 110x xxxx
        {
	  $utf8_start = $v;
	  $utf8_size = 2;
	  $utf8_len = 1;
#	  printf "1 %02x\n", $v;
	}
      elsif (($v & 0xf0) == 0xe0)		# 1110 xxxx
        {
	  $utf8_start = $v;
	  $utf8_size = 3;
	  $utf8_len = 2;
#	  printf "2 %02x\n", $v;
	}
      elsif (($v & 0xf8) == 0xf0)		# 1111 0xxx
        {
	  $utf8_start = $v;
	  $utf8_size = 4;
	  $utf8_len = 3;
#	  printf "3 %02x\n", $v;
	}
      elsif ($typ_latin{$v})
        {
	  $latin1_typ++;
	}
      else
        {
	  $utf8_invalid++;
#	  printf "x %02x\n", $v;
	}
    }
  print "$name: utf8_valid=$utf8_valid utf8_invalid=$utf8_invalid latin1_typ=$latin1_typ ascii=$ascii\n";
}

=head1 AUTHOR

Juergen Weigert, C<< <jw at suse.de> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-text-toascii at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Text-GuessEncoding>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Text::GuessEncoding


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Text-GuessEncoding>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Text-GuessEncoding>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Text-GuessEncoding>

=item * Search CPAN

L<http://search.cpan.org/dist/Text-GuessEncoding/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2010 Juergen Weigert.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of Text::GuessEncoding
