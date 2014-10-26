package Net::iTMS::Genre;
#
# Written by Thomas R. Sibley, <http://zulutango.org:82/>
#
use warnings;
use strict;

use vars '$VERSION';
$VERSION = '0.11';

use Net::iTMS::Error;

=head1 NAME

Net::iTMS::Genre - Represents a genre in the iTunes Music Store

=head1 DESCRIPTION

A Net::iTMS::Genre object represents a genre in the iTMS.  Currently,
it's only a shell object, but in future releases it will be able to
be used to "browse" genres (C<< $genre->artists >>, C<< $genre->top_songs >>,
etc.).

=head2 Methods

=over 12

=item new($itms, $genreId)

The first argument must be an instance of Net::iTMS, the second an iTMS
genre ID.

Returns a blessed hashref (object) for Net::iTMS::Genre.

=cut
sub new {
    my ($class, $itms, $id, %prefill) = @_;
    
    my $self = bless {
        id    => $id,
        error => '',
        debug => defined $itms->{debug} ? $itms->{debug} : 0,
        _itms => $itms,
    }, $class;
    
    if (%prefill) {
        $self->{$_} = $prefill{$_}
            for keys %prefill;
    }
    
    return $self;
}

=item id

Returns the ID of the genre (C<genreId>).

=item name

Returns the name of the genre.

=cut

sub id { return $_[0]->{id} }
sub name { return $_[0]->{name} }

=back

=head1 LICENSE

Copyright 2004, Thomas R. Sibley.

This work is licensed under the Creative Commons
Attribution-NonCommercial-ShareAlike License revision 2.0.  To view a copy
of this license, visit L<http://creativecommons.org/licenses/by-nc-sa/2.0/>
or send a letter to:

    Creative Commons
    559 Nathan Abbott Way
    Stanford, California 94305, USA.

=head1 AUTHOR

Thomas R. Sibley, L<http://zulutango.org:82/>

=head1 SEE ALSO

L<Net::iTMS>, L<Net::iTMS::Song>, L<Net::iTMS::Album>, L<Net::iTMS::Artist>

=cut

42;
