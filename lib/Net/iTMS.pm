package Net::iTMS;
#
# Written by Thomas R. Sibley, <http://zulutango.org:82/>
#
use warnings;
use strict;

use vars '$VERSION';
$VERSION = '0.11';

use Net::iTMS::Error;
use Net::iTMS::Request;
use Net::iTMS::Artist;
use Net::iTMS::Album;
use Net::iTMS::Song;
use Net::iTMS::Genre;
use Net::iTMS::Search;

=head1 NAME

Net::iTMS - Interface to the information within the iTunes Music Store (iTMS)

=head1 SYNOPSIS

    my $iTMS = Net::iTMS->new;
    
    my $artist = $iTMS->get_artist(2893902);
    print "Artist: ", $artist->name, "\n";
    
    for my $album ($artist->discography) {
        print $album->title, "\n";

        for my $track ($album->tracks) {
            print "\t ", $track->number, ": ", $track->title, "\n";
        }
    }

=head1 DESCRIPTION

Net::iTMS is the main class (that is, the one you should be using) for
interacting with Apple's iTunes Music Store (L<http://apple.com/itunes/store/>).

Currently, it provides means to access individual artist, album, and song
information in the iTMS.

=head2 Methods

All methods return C<undef> on error and (should) set an error message,
which is available through the C<error> method.

=over 12

=item C<< new([ debug => 1, [...] ]) >>

Takes an argument list of C<key => value> pairs.  The options available
are:

=over 24

=item C<< tmpdir => '/some/path' >>

Used to specify the path to the directory where temporary files should be
created.  Defaults to L<File::Temp>'s default.

=item C<< debug => 0 or 1 >>

If set to a true value, debug messages to be printed to STDERR.

=item C<< show_xml => 0 or 1 >>

If set to a true value, L<Net::iTMS::Request> will print to STDERR the XML
fetched during each request.

=back

Returns a blessed hashref (object) for Net::iTMS.

=cut
sub new {
    my ($class, %opt) = @_;

    return bless {
        error    => '',
        debug    => defined $opt{debug} ? $opt{debug} : 0,
        _request => Net::iTMS::Request->new(%opt),
    }, $class;
}

=item C<get_artist($artistId)>

Takes an artistId and returns a L<Net::iTMS::Artist> object.
=cut
sub get_artist {
    my ($self, $id, %opt) = @_;
    
    return $id
            ? Net::iTMS::Artist->new($self, $id, %opt)
            : $self->_set_error('No artist ID passed.');
}

=item C<get_genre($genreId)>

Takes a genreId and returns a L<Net::iTMS::Genre> object.

=cut
sub get_genre {
    my ($self, $id, %opt) = @_;
    
    return $id
            ? Net::iTMS::Genre->new($self, $id, %opt)
            : $self->_set_error('No artist ID passed.');
}

=item C<get_album($albumId)>

Takes an albumId and returns a L<Net::iTMS::Album> object.

=cut
sub get_album {
    my ($self, $id, %opt) = @_;
    
    return $id
            ? Net::iTMS::Album->new($self, $id, %opt)
            : $self->_set_error('No album ID passed.');
}

=item C<get_song($songId)>

Takes a songId and returns a L<Net::iTMS::Song> object.

=cut
sub get_song {
    my ($self, $id, %opt) = @_;
    
    return $id
            ? Net::iTMS::Song->new($self, $id, %opt)
            : $self->_set_error('No song ID passed.');
}

=item C<search_for($terms)>

Takes a search string (query) and returns a L<Net::iTMS::Search>
object.

=cut
sub search_for {
    my ($self, $query, %opt) = @_;

    return $query
            ? Net::iTMS::Search->new($self, $query, %opt)
            : $self->_set_error('No terms passed.');
}

=back

=head1 TODO

    Net::iTMS::Artist
        * biography
        * influencers

    Net::iTMS::Genre
        * browse, etc

    Net::iTMS::Album
        * browseAlbum URL... see what information
        
    Net::iTMS::Song
        * songMetaData... how to use this?  keep getting server errors

    Programmatic tests, instead of hand testing by me.
    
    Better caching (more selective updates)
    
    Redo SYNOPSISes

=head1 BUGS

None known at the current time, but there are bound to be some.

Please report all bugs via RT at
L<https://rt.cpan.org/NoAuth/ReportBug.html?Queue=Net-iTMS>.

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

=cut

42;
