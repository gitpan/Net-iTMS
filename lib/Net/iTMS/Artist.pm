package Net::iTMS::Artist;
#
# Written by Thomas R. Sibley, <http://zulutango.org:82/>
#
use warnings;
use strict;

use vars '$VERSION';
$VERSION = '0.11';

use Net::iTMS::Error;

=head1 NAME

Net::iTMS::Artist - Represents an artist in the iTunes Music Store

=head1 SYNOPSIS

    use Net::iTMS::Artist;

    my $artist = Net::iTMS::Artist->new($iTMS, $id);
    
    print "Artist: ", $artist->name, "\n";

    # $album will be a Net::iTMS::Album object
    for my $album ($artist->discography) {
        print $album->title, " (", $album->genre->name, ")\n";

        # $track will be a Net::iTMS::Song object
        for my $track ($album->tracks) {    # also $album->songs
            print "\t ", $track->number, ": ", $track->title, "\n";
        }
    }

=head1 DESCRIPTION

Net::iTMS::Artist represents an artist in the iTMS and encapsulates the
associated data.  If a piece of information hasn't been fetched from the
iTMS, it will transparently fetch and store it for later use before
returning.

If one of the methods C<id>, C<name>, C<website>, C<genre>, C<path>,
C<selected_albums>, or C<total_albums> is called, the information
for the others will be fetched in the same request.  This means, for
these methods, the first call to one will have a time hit for the
HTTP request, but subsequent calls won't.

=head2 Methods

All methods return C<undef> on error and (should) set an error message,
which is available through the C<error> method.  (Unless I note otherwise.)

=over 12

=item new($itms, $artistId)

The first argument must be an instance of Net::iTMS, the second an
iTMS artist ID.

Returns a blessed hashref (object) for Net::iTMS::Artist.

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

Returns the ID of the artist (C<artistId>).

=item name

Returns the name of the artist.

=item website

Returns the website URL of the artist (undef if there isn't one specified).

=item genre

Returns a L<Net::iTMS::Genre> object representing the artist's primary genre.

=item path

Returns an arrayref of hashrefs representing the artist's "path" in the iTMS.
The hashrefs contain the name of the node in the path and the iTMS URL of that
node.

For example, Elliott Smith's (id = 2893902) "path" is "Alternative > Elliott Smith",
which is represented in Perl by:

    # URLs trimmed for example
    [
      {
        'url' => 'http://ax.phobos.apple.com.edgesuite.net/.../viewGenre?genreId=20',
        'name' => 'Alternative'
      },
      {
        'url' => 'http://ax.phobos.apple.com.edgesuite.net/.../viewArtist?artistId=2893902',
        'name' => 'Elliott Smith'
      }
    ]

This is pretty much only useful if you're trying to imitate the iTunes interface.

=item selected_albums

Returns an array or arrayref (depending on context) of L<Net::iTMS::Album> objects
for a selection of albums by the artist (currently ordered by best selling).

=item total_albums

Returns the total number of albums by this artist available in the iTMS.

=item discography

Returns an array or arrayref (depending on context) of L<Net::iTMS::Album> objects
for all the albums of the artist available on the iTMS.

=cut
sub id { return $_[0]->{id} }

sub name {
    my $self = shift;
    $self->_get_basic_info
        if not exists $self->{name};
    return $self->{name};
}

sub genre {
    my $self = shift;
    $self->_get_basic_info
        if not exists $self->{genre};
    return $self->{genre};
}

sub website {
    my $self = shift;
    $self->_get_basic_info
        if not exists $self->{website};
    return $self->{website};
}

sub path {
    my $self = shift;
    $self->_get_basic_info
        if not exists $self->{path};
    return wantarray ? @{$self->{path}} : $self->{path};
}

sub selected_albums {
    my $self = shift;
    $self->_get_basic_info
        if not exists $self->{selected_albums};
    return wantarray ? @{$self->{selected_albums}} : $self->{selected_albums};
}

sub total_albums {
    my $self = shift;
    $self->_get_basic_info
        if not exists $self->{total_albums};
    return $self->{total_albums};
}

sub discography {
    my $self = shift;
    $self->_get_discography
        if not exists $self->{discography};
    return wantarray ? @{$self->{discography}} : $self->{discography};
}

#
# This populates the name, genre, path, website, and selected albums data
#
sub _get_basic_info {
    my $self = shift;
    
    my $twig = $self->{_itms}->{_request}->url('viewArtist', $self->id);
    
    my $root = $twig->root;
    my $path = $root->first_child('Path');
    my $sv   = $root->first_child('ScrollView');
    
    #
    # Name
    #
    $self->{name} = $path->last_child('PathElement')
                         ->att('displayName');

    #
    # Path
    #
    for my $child ($path->children('PathElement')) {
        push @{$self->{path}}, {
            name => $child->att('displayName'),
            url  => $child->trimmed_text,
        };
    }
    
    #
    # Genre
    #
    $self->{genre} = $self->{_itms}->get_genre(
                            $root->att('genreId'),
                            name => $path->first_child('PathElement')
                                         ->att('displayName')
                     );
    
    $path->delete;
    
    #
    # Website URL
    #
    my $website = $sv->first_child('MatrixView')
                     ->first_child('View')
                     ->first_child('MatrixView')
                     ->first_child('VBoxView')
                     ->first_child('OpenURL');
    
    $self->{website} = $website->att('url')
        if defined $website;
    
    #
    # Selected albums
    #
    $self->{selected_albums} = [ ];
    
    my $grid = $sv->first_child('MatrixView')
                  ->first_child('View')
                  ->first_child('MatrixView')
                  ->first_child('VBoxView')
                  ->first_child('VBoxView');

    if (defined $grid) {
        for my $hbox ($grid->children('HBoxView')) {
            for my $vbox ($hbox->children('VBoxView')) {
                my $xml = $vbox->first_child('MatrixView')
                               ->first_child('ViewAlbum');

                next if not defined $xml;

                my $thumb = { };

                if (my $pic = $xml->first_child('PictureView')) {
                    $thumb = {
                        height => $pic->att('height'),
                        width  => $pic->att('width'),
                        url    => $pic->att('url'),
                    };
                }
                
                push @{$self->{selected_albums}},
                     $self->{_itms}->get_album(
                            $xml->att('id'),
                            title  => $xml->att('draggingName'),
                            artist => $self,
                            thumb  => $thumb,
                     );
            }
        }
    }
    
    # Get range of albums if there is one
    for my $r ($sv->first_child('MatrixView')
                  ->first_child('View')
                  ->first_child('MatrixView')
                  ->first_child('VBoxView')
                  ->descendants('B')) {
        if ($r->trimmed_text =~ /^Albums: (\d+)-(\d+) of (\d+)$/) {
            $self->{selected_albums_start} = $1;
            $self->{selected_albums_end}   = $2;
            $self->{total_albums}          = $3;
        }
    }
    
    $self->{total_albums} = scalar @{$self->{selected_albums}}
        if not $self->{total_albums};
        
    $sv->delete;
    $twig->purge;
}

#
# This populates the name, genre, path, website, and selected albums data
#
sub _get_discography {
    my $self = shift;
    
    my $twig = $self->{_itms}->{_request}->url('browseArtist', $self->id);
    my $root = $twig->root;
    
    my $plist = ($root->descendants('plist'))[0]
                      ->first_child('dict')
                      ->first_child('array');
    
    $self->{discography} = [ ];
    
    for my $dict ($plist->children('dict')) {
        my %data;
        for my $key ($dict->children('key')) {
            $data{$key->trimmed_text} = $key->next_sibling->trimmed_text;
        }
        
        push @{$self->{discography}},
             $self->{_itms}->get_album(
                    $data{playlistId},
                    title       => $data{playlistName},
                    artist      => $self,
             );
    }
    $plist->delete;

    $twig->purge;
}

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

L<Net::iTMS>, L<Net::iTMS::Album>, L<Net::iTMS::Song>, L<Net::iTMS::Genre>

=cut

42;
