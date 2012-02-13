package Binary;
use warnings;
use strict;
use Encode 'decode';
use Digest::MD5 'md5';
use Scalar::Util 'dualvar', 'looks_like_number';
use Carp 'croak';
use Data::Dump::Streamer 'Dump';
use Fatal ':void', 'seek';
use Config;
use Try::Tiny;

our $VERSION = '0.01';
our $DEBUG = 0;

sub eat_desc {
  my ($conv, $desc) = @_;
  my ($fh, $context, $str_context) = @$conv;
  if ($DEBUG) {
    # warn "$str_context\n";
  }
  # print "In eat_desc, conv=";
  # Dump $conv;
  
  if ($DEBUG and (caller)[0] eq 'Binary') {
    die "No context on internal call to eat_desc" if @$conv < 2;
    if (!$str_context) {
      warn "No str_context on internal call to eat_desc";
      warn "Caller: ".join('//', caller);
    }
  }
  # print "eat_desc, str_context=$str_context\n";
  $str_context //= '';

  # print "In eat_desc, desc=$desc, fh=$fh\n";

  my $ret;

  if (ref $desc eq 'ARRAY') {
    # *COPY*
    my @desc = @$desc;
    my $n=0;
    $ret = {_context => $context};
    while (@desc) {
      my ($name, $subdesc) = splice(@desc, 0, 2, ());
      #printf "Eating %s type %s\n", $name, $subdesc;
      # .+: Don't catch Z* and the like.
      if ($subdesc =~ m/\*(.+)$/) {
        #print "Substituting count in $subdesc\n";
        my $count = $ret->{$1};
        $subdesc =~ s/\*$1/$count/;
        #print "... now $subdesc\n";
      }
      $ret->{$name} = eat_desc([$fh, $ret, "$str_context.$name"],
                               $subdesc);
      #printf "Eating %s type %s, got %s\n", $name, $subdesc, $ret->{$name};
      $ret->{"$n.$name"} = $ret->{$name};
      $n++;
    }
  } elsif (not ref $desc and
           my ($subdesc, $count) = $desc =~ m/^(.*?)(\d+)$/ and
           $1 !~ m/^a|Z$/) {
    my @ret;
    for my $n (0..$count-1) {
      my $ret = eat_desc([$fh, \@ret, "$str_context.$n"], $subdesc);
      push @ret, $ret;
    }
    $ret = \@ret;
  } elsif (not ref $desc) {
    my ($len, $template);
    my %plain = ('Q'  => 8,
                 'Q<' => 8,
                 'Q>' => 8,
                 'q'  => 8,
                 'q<' => 8,
                 'q>' => 8,
                 'd>' => 8,
                 'd<' => 8,
                 'd'  => 8,
                 'f>' => 4,
                 'f<' => 4,
                 'f'  => 4,
                 's>' => 2,
                 's<' => 2,
                 's'  => 2,
                 'N'  => 4,
                 'n'  => 2,
                 'V!' => 4,
                 'V'  => 4,
                 'v'  => 2,
                 'L'  => 4,
                 'L<' => 4,
                 'L>' => 4,
                 'l>' => 4,
                 'l<' => 4,
                 'l'  => 4,
                 'c'  => 1,
                 'C'  => 1,
                );
    if (exists $plain{$desc}) {
      $ret = eat_unpack($conv, $desc, $plain{$desc});
    } elsif ($desc eq 'Z*') {
      while (1) {
        my $char = my_read($fh, 1, $str_context);
        # print "Z* reading: '$char'\n";
        if ($char eq "\0") {
          $ret = decode('ascii', $ret);
          last;
        } else {
          $ret .= $char;
        }
      }
    } elsif ($desc =~ /^(a|Z)(\d+)$/) {
      if ($2 == 0) {
        $ret = '';
      } else {
        $ret = eat_unpack($conv, $desc, $2);
      }
    } elsif ($desc eq 'a*' and ref $fh eq 'SCALAR') {
      $ret = $$fh;
      $$fh = '';
    } else {
      die "Don't know what to do with stringy/unpack desc '$desc' in eat_desc at $str_context";
    }
  } elsif (ref $desc eq 'CODE') {
    $ret = scalar $desc->($conv);
  } else {
    die "Don't know what to do with descriptor $desc at $str_context";
  }
  

  if ($DEBUG) {
    if (defined $ret) {
      warn "$str_context = $ret\n";
    } else {
      warn "$str_context = undef\n";
    }
  }

  return $ret;
}

sub eat_required {
  my ($conv, $base, $should_be, $error) = @_;
  my ($fh, $context, $str_context) = @$conv;
  $error //= $str_context;

  if ($DEBUG) {
    die "No context on call to eat_required" if @$conv < 2;
    if (!$str_context) {
      die "No str_context on eat_required";
      # warn "Caller: ".join('//', caller);
    }
    print "eat_required, str_context=$str_context\n";
  }

  my $initpos;
  if (ref($fh) eq 'GLOB') {
    $initpos = tell($fh);
  }
  my $val = eat_desc($conv, $base);
  Dump $val if ref $val;

  #my $matches;
  #if (ref $should_be) {
  #  die;
  #} elsif (looks_like_number $should_be) {
  #  $matches = ($val == $should_be);
  #} else {
  #  $matches = ($val eq $should_be);
  #}
  #unless ($matches) {
  unless ($val ~~ $should_be) {
    my $at;
    if (defined $initpos) {
      $at = sprintf " at byte %d = 0x%x", $initpos, $initpos;
    } else {
      $at = '';
    }
    $at .= " $str_context";
    $should_be = join(' or ', @$should_be) if ref($should_be) eq 'ARRAY';
    croak "$error: expected $should_be, got $val$at";
  }

  return $val;
}

sub eat_encoded_str {
  my ($conv, $bytelen, $encoding, $chop_zeroes) = @_;
  my ($fh, $context, $str_context) = @$conv;
  
  if (!looks_like_number($bytelen)) {
    ($bytelen) = eat_desc($conv, $bytelen);
  }
  # print "Eating encoded string: bytelen=$bytelen\n";
  my $str = my_read($fh, $bytelen, $str_context);
  $str = decode($encoding, $str, Encode::FB_CROAK);
  $str =~ s/\0+$// if $chop_zeroes;
  return $str;
}

sub eat_utf16be_null {
  my ($conv) = @_;
  my ($fh, undef, $str_context) = @$conv;

  my $str;
  while (1) {
    my $s = decode('utf16be', my_read($fh, 2, $str_context));
    last if $s eq "\0";
    $str .= $s;
  }
  return $str;
}

# Eat up padding until the current location in the file
# is of the form $ofs + n * $mul.
sub eat_pad_until {
  my ($conv, $mul, $ofs) = @_;
  my ($fh, undef, $str_context) = @$conv;
  $ofs = 0 if not defined $ofs;
  
  # Quick and dirty loop to start with.  For later, compute how far to read,
  # then read it all in one gulp.
  my $ret='';
  while (1) {
    my $pos = tell($fh);
    $pos -= $ofs;
    last if ($pos % $mul == 0);
    $ret .= my_read($fh, 1, $str_context);
  }

  return $ret;
}

sub eat_until_eof {
  my ($conv, $desc) = @_;
  my ($fh) = @$conv;
  
  my @ret;
  while (ref $fh eq 'SCALAR' ? length $$fh : !eof $$fh) {
    if (ref $fh eq 'SCALAR') {
      warn "Length remaining: ", length $$fh, "\n";
    }
    #my $pos = tell($fh);
    my $e;
    eval {
      $e = Binary::eat_desc($conv, $desc);
    };
    if ($@) {
      warn "Error in eat_until_eof: $@";
      #seek $fh, $pos, 0;
      last;
    }
    push @ret, $e;
  }
  
  return \@ret;
}

sub eat_unpack {
  my ($conv, $template, $len) = @_;
  my ($fh, $context, $address) = @$conv;

  if ($template =~ m/^Q/ and $Config{ivsize} < 64) {
    if (uc $template eq 'Q') {
      die "FIXME: Convert Q to Q< or Q>, whichever is native to this system";
    }
    if ($template eq 'Q<') {
      require Math::BigInt;
      my $parts = Binary::eat_desc(shift, 'V2');
      if ($parts->[1] == 0) {
          return $parts->[0];
      }

      return Math::BigInt->new($parts->[1])<<32 | Math::BigInt->new($parts->[0]);
    } elsif ($template eq 'Q>') {
      require Math::BigInt;
      my $parts = Binary::eat_desc(shift, 'N2');
      if ($parts->[0] == 0) {
          return $parts->[1];
      }

      return Math::BigInt->new($parts->[0])<<32 | Math::BigInt->new($parts->[1]);
    } else {
      die "Handle Q... template $template";
    }
  }

  # print "eat_unpack: fh=$fh, template=$template, len=$len\n";
  return unpack($template, my_read($fh, $len, $address));
}

my %read_bitmaps;
sub my_read {
  my ($fh, $length, $address) = @_;
  
  if (ref $fh eq 'GLOB') {
    # Filehandle

    # # FIXME: Somehow init the bitmap to all zeros of the correct length?
    # if (not defined $read_bitmaps{$fh}) {
    #   $read_bitmaps{$fh} = "";
    # }
    
    # return '' if not $length;
    
    # for (tell($fh)..tell($fh)+$length-1) {
    #   print "read bitmap vec tracking: $_\n";
    #   die "Huh, neg: \$_ = $_, length=$length, tell=".tell($fh) if $_<0;
    #   vec($read_bitmaps{$fh}, $_, 1) = 1;
    # }
    
    local $/=\$length;
    return '' if !$length;
    die "EOF! $address" if eof $fh;
    my $data = <$fh>;
    die "Can't read: $!" if not defined $data;
    if (length($data) != $length) {
      die sprintf "Short read (got %d bytes, expected %d): $!", length($data), $length;
    }
    return $data;
  } elsif (ref $fh eq 'SCALAR') {
    if ($$fh eq '' and $length > 0) {
      die "Cannot read anything from empty-string -- fell off end of input (length=$length)";
    }

    # String.
    # Dump($fh);
    if ($length > length($$fh)) {
      die "Next read would go off of end of string: want $length bytes, have only ", length($$fh), " remaining";
    }
    my $data = substr($$fh, 0, $length, '');
    # print "my_read: read data='$data', fh=$fh, len=$length\n";
    
    return $data;
  } else {
    Dump $fh;
    die "Huh - unhandled filehandle '$fh' in my_read";
  }
}

sub get_read_bitmaps {
  return \%read_bitmaps;
}
sub eat_at {
  my ($conv, $pos, $desc) = @_;
  my ($fh, $context, $addr) = @$conv;
  
  if (!looks_like_number $pos) {
    $pos = Binary::eat_desc([$fh, $context, "$addr.at"], $pos);
  }

  my $origpos = tell($fh);

  seek($fh, $pos, 0) or die "Cannot seek for eat_at: $!";
  (my $data, undef) = Binary::eat_desc([$fh, $context, $addr.".at[$pos]"], $desc);
  seek($fh, $origpos, 0);
  return $data;
}

sub eat_zero_len {
  my ($conv, $desc) = @_;
  my ($fh, $context) = @$conv;
  my $origpos = tell($fh);
  (my $data, undef) = Binary::eat_desc($conv, $desc);
  seek($fh, $origpos, 0) or die "Seeking failed in eat_zero_len: $!";
  return $data;
}

sub eat_counted_string {
  my ($conv, $count_size, $encoding) = @_;
  my ($fh, $context, $str_context) = @$conv;
  
  my $count;
  if (looks_like_number $count_size) {
    $count = $count_size;
  } else {
    $count = eat_desc([$fh, $context, "$str_context.count"], $count_size);
  }
  if ($DEBUG) {
    print "String size: $count\n";
  }
  my $string = eat_desc([$fh, $context, "$str_context.str"], "a$count");
  if ($encoding) {
    $string = decode($encoding, $string);
  }

  return $string;
}

sub eat_bitmask {
  my ($conv, $desc, %values) = @_;
  my ($fh, $context, $str_context) = @$conv;
  my $raw = eat_desc($conv, $desc);
  my %ret = (_raw => $raw);
  for (keys %values) {
    if ($raw & $_) {
      $ret{$values{$_}}++;
      $raw &= ~$_;
    }
  }
  if ($raw) {
    warn "Leftovers on bitmask -- $raw left at $str_context";
    $ret{_remaining} = $raw;
  }
  return \%ret;
}

sub eat_enum {
  my ($conv, $desc, $values) = @_;
  my ($fh, $context, $str_context) = @$conv;
  
  my $raw = eat_desc($conv, $desc);
  if (ref $values eq 'HASH' and exists $values->{$raw}) {
    return dualvar($raw, $values->{$raw});
  } elsif (ref $values eq 'ARRAY' and @$values >= $raw) {
    return dualvar($raw, $values->[$raw]);
  } else {
    carp(sprintf("Unknown value %d = 0x%x in enum $str_context", $raw, $raw));
    return $raw;
  }
}

sub eat_counted {
  my ($conv, $count, $desc) = @_;
  my ($fh, $context, $context_str) = @$conv;

  croak "undefined count in eat_counted at $context_str" if not defined $count;
  if (!looks_like_number $count) {
    $count = Binary::eat_desc([$fh, $context, "$context_str.count"], $count);
  }
  
  # Explicit init so it's an ar at all in the zero case.
  my $ret=[];

  for my $i (0..$count-1) {
    # We have a bit of a problem here -- what should the context be?
    # An array, $ret, would be consistent with other places, but it
    # makes it impossible to go upward, since there's no place to put
    # _context.
    $ret->[$i] = eat_desc([$fh, $context, "$context_str.$i"], $desc);
  }

  return $ret;
}

# This is somewhat complicated for sanity of implmentation, but on the
# other hand, it is also very very useful.  The terminator search
# happens *before* decoding.  Thus, the terminator is a raw string.
# To read utf16 with this, the terminator should be "\0\0".
sub eat_terminated_string {
  my ($conv, $encoding, $terminator) = @_;
  my ($fh, undef, $address) = @$conv;
  my $rawstr;
  my $tlen = length($terminator);
  while (1) {
    my $ret = my_read($fh, 1, $address);
    $rawstr .= $ret;
    if ($DEBUG) {
      # my $foo = $rawstr;
      # $foo =~ s/([^ -~])/sprintf "\\x%02x", ord $1/ge;
      # print "eat_terminated_string, rawstr: $foo\n";
    }
    if (substr($rawstr, -$tlen) eq $terminator) {
      my $ret;
      try {
        $ret = decode($encoding, substr($rawstr, 0, -$tlen), Encode::FB_CROAK);
      } catch {
        warn shift." at $address";
        return substr($rawstr, 0, -$tlen);
      };
      return $ret;
    }
  }
}

sub eat_parallel_array {
  my ($conv, $count, $desc) = @_;
  my ($fh, $context, $str_context, @rest_conv) = @$conv;

  if (!looks_like_number($count)) {
    $count = Binary::eat_desc([$fh, $context, "$str_context.count", @rest_conv], $count);
  }

  if ($DEBUG) {
    print "Eat_parallel_array: count=$count\n";
  }

  my $ret;
  my @desc_copy = @$desc;
  while (@desc_copy) {
    my $name = shift @desc_copy;
    my $subdesc = shift @desc_copy;
    print "eat_parallel_array: name=$name, subdesc=$subdesc\n" if $DEBUG;
    for my $n (0..$count-1) {
      $ret->[$n]{$name} = Binary::eat_desc([$fh, $ret, "$str_context.$name.$n", @rest_conv], $subdesc);
    }
  }

  return $ret;
}

sub eat_for_length {
  my ($conv, $length, $subdesc) = @_;
  my ($fh, $context, $addr) = @$conv;
  
  print "Doing eat_for_length, length = $length\n";

  # FIXME: Make the real filehandle case work.
  my $initial_length = length $$fh;
  my $n = 0;
  my @ret;
  while ($initial_length - length $$fh < $length) {
    push @ret,
      Binary::eat_desc([$fh, $context, "$addr.$n"], $subdesc);
    $n++;
    print "eat_for_length, length = $length, done so far = ", $initial_length - length $$fh, "\n";
  }

  return \@ret;
}

1;

