package Net::iTMS::XML;
#
# Written by Thomas R. Sibley, <http://zulutango.org:82/>
#
use warnings;
use strict;

use vars '$VERSION';
$VERSION = '0.03';

require XML::Twig;

=head1 NAME

Net::iTMS::XML - Methods to process iTMS XML

=head1 SYNOPSIS

    use Net::iTMS::XML;

    my $p = Net::iTMS::XML->new(file => 'viewAlbum.xml');
    # or...
    my $p = Net::iTMS::XML->new($string_with_xml);
    
    my @path = @{$p->Path};
    my %tracklist = %{$p->TrackList};
    
    # ...etc...
    # To see the structure...
    use Data::Dumper;
    print Dumper(\%tracklist), "\n";

=head1 DESCRIPTION

Net::iTMS::XML creates an XML::Twig object for the provided data.  It is
then up to you to call the various methods provided and deal with the returned
data structures (arrayrefs, hashrefs, and the occasionally string or two).

Currently the structure of the data returned isn't documented (except in code).
The easiest way to figure out the structure is to use L<Data::Dumper> or a
similar module to print out the structure for you.  See the SYNOPSIS for an
example.

=head2 Methods

All methods (excepting C<new>, C<purge>, and a few others) take the first argument
as a hash.  Currently the only key in use is C<cleanup>, which determines whether or
not the method deletes the branch it's been working on.  Default is 1, to delete
it (which means undefined results (probably program death) if you call a method
that uses an already deleted branch).

=over 12

=item C<< new(file => 'viewAlbum.xml') >>

=item C<< new($xml) >>

If the first argument is 'file' (case insensitive), then the second argument
is taken to be the name of a file from which to read the XML.  If the first
argument is anything else, it is taken to be a string of the XML to be parsed.

Returns a blessed hashref (object) for Net::iTMS::XML.

=cut
sub new {
    my $class = shift;
    my $twig  = XML::Twig->new;
    
    my %data;
    if (lc($_[0]) eq 'file' and $_[1]) {
        $twig->parsefile($_[1]);
        $data{file} = $_[1];
    } else {
        # Assume the first argument is the XML
        my $xml = shift;
        $twig->parse($xml);
        $data{xml} = $xml;
    }
    
    return bless {
        twig => $twig,
        _dispatch => {
            album   => \&_parse_album,
            search  => \&_parse_search,
        },
        %data,
    }, $class;
}

=item C<< parse >>

Included for compatibility reasons.  Returns the object it was called from
for convenience of using this module via L<Net::iTMS>.

=cut
sub parse {
    return shift;
}

=item C<< pageType >>

Returns a string containing the value of the XML document's pageType attribute.

=cut
sub pageType {
    my $self = shift;
    return $self->root->att('pageType');
}

=item C<< Path >>

Returns an arrayref of hashrefs containing the name and url of the C<< <Path> >>
elements in the XML.

=cut
sub Path {
    my ($self, %opt) = @_;
    my $root = $self->{twig}->root;
    
    $opt{cleanup} = defined $opt{cleanup}
                        ? $opt{cleanup}
                        : 1;
    
    # Get information about the genre (Path)
    my $path      = $root->first_child('Path');
    my @children  = $path->children('PathElement');
    my $info      = [ ];
    
    for my $child (@children) {
        push @$info, {
            name => $child->att('displayName'),
            url  => $child->trimmed_text,
        };
    }
    
    $path->delete if $opt{cleanup};

    return $info;
}

=item C<< TrackList >>

Returns a semi-complex hashref representing the track listing provided in
the XML document.

=cut
sub TrackList {
    my ($self, %opt) = @_;
    my $root = $self->{twig}->root;
    
    $opt{cleanup} = defined $opt{cleanup}
                        ? $opt{cleanup}
                        : 1;
    
    # The track listing
    my $tracks = $root->first_child('TrackList');
    
    my $tracksInfo = $tracks->first_child('plist')
                            ->first_child('dict');
    my $info = { };
    
    for my $child ($tracksInfo->children('key')) {
        if ($child->trimmed_text eq 'priceFormat') {
            $info->{priceFormat}
                = $child->next_elt('string')->trimmed_text;
        }
        elsif ($child->trimmed_text eq 'listType') {
            $info->{listType}
                = $child->next_elt('string')->trimmed_text;
        }
        elsif ($child->trimmed_text eq 'items') {
            my $trackList = $child->next_elt('array');
            for my $t ($trackList->children('dict')) {
                my $trackdata = { };
                for my $key ($t->children('key')) {
                    $trackdata->{$key->trimmed_text} = $key->next_sibling->trimmed_text;
                }
                push @{$info->{tracks}}, $trackdata;
            }
        }
    }

    $tracks->delete if $opt{cleanup};

    return $info;
}

=item C<< albumsFromSearch >>

Returns a semi-complex hashref of the albums found from a basic search.
Undefined results if called on XML not from a basic search.

=cut
sub albumsFromSearch {
    my ($self, %opt) = @_;
    my $root = defined $opt{root}
                    ? $opt{root}
                    : $self->{twig}->root;
    
    $opt{cleanup} = defined $opt{cleanup}
                        ? $opt{cleanup}
                        : 1;
    
    my $info = [ ];
    
    # Get general information about the album (ScrollView)
    my $ScrollView = $root->first_child('ScrollView');
    
    my $mv = $ScrollView->first_child('MatrixView')
                        ->first_child('VBoxView')
                        ->first_child('MatrixView');
    if (defined $mv) {
        for ($mv->first_child('VBoxView')
                ->first_child('MatrixView')
                ->first_child('MatrixView')
                ->children('VBoxView')) {

            my $album  = $_->first_child('MatrixView')
                           ->first_child('ViewAlbum');

            next if not defined $album;

            my %tmp = (
                title   => $album->att('draggingName'),
                id      => $album->att('id'),
                playlistId => $album->att('id'),
                cover   => { },
                artist  => { },
                genre   => { },
            );

            if (my $pic = $album->first_child('PictureView')) {
                $tmp{cover} = {
                    height => $pic->att('height'),
                    width  => $pic->att('width'),
                    url    => $pic->att('url'),
                };
            }

            if (my $artist = $_->first_child('MatrixView')
                               ->first_child('VBoxView')
                               ->first_child('TextView')
                               ->first_child('ViewArtist')) {
                $tmp{artist} = {
                    name => $artist->trimmed_text,
                    id   => $artist->att('id'),
                };

                if (my $genre = $artist->parent
                                       ->next_sibling('TextView')
                                       ->first_child('ViewGenre')) {

                    my $name = $genre->trimmed_text;
                    $name =~ s/^Genre:\s+//i;

                    $tmp{genre} = {
                        name => $name,
                        id   => $genre->att('id'),
                    };
                }
            }
            push @$info, \%tmp;
        }
    }
    
    $ScrollView->delete if $opt{cleanup};
    
    return $info;
}

=item C<< album >>

Returns an hashref of information about the album.  Undefined results
if called on XML not from a viewAlbum request.

=cut
sub album {
    my ($self, %opt) = @_;
    my $root = $self->{twig}->root;
    
    $opt{cleanup} = defined $opt{cleanup}
                        ? $opt{cleanup}
                        : 1;
    
    my $info = { };
    
    # Get basic information about the album
    $info->{$_} = $root->att($_) for qw/artistId genreId playlistId/;
    
    my $SV = $root->first_child('ScrollView');

    # We could just depend on the right twig being the first
    # in the document everytime, but let's not
    my $album;
    for my $child ($SV->descendants('ViewAlbum')) {
        if (defined $child->{att}{draggingName}
                and $child->first_child_matches('PictureView')) {
            # This is the one we want, so break out
            $album = $child;
            last;
        }
    }
    
    $info->{title} = $album->att('draggingName');

    my $pic = $album->first_child('PictureView');
    $info->{cover} = {
        height => $pic->att('height'),
        width  => $pic->att('width'),
        url    => $pic->att('url'),
    };
    
    $pic->delete;
    $album->delete;
    
    my $artist;
    for my $child ($SV->descendants('ViewArtist')) {
        if (defined $child->{att}{id}
                and $child->{att}{id} eq $info->{artistId}) {
            # This is the one we want, so break out
            $artist = $child;
            last;
        }
    }
    
    if (defined $artist) {
        $info->{artist} = $artist->trimmed_text;
        $artist->delete;
    }
    
    for my $text ($SV->first_child('MatrixView')
                        ->first_child('VBoxView')
                        ->first_child('MatrixView')
                        ->first_child('VBoxView')
                        ->children('TextView')) {
        if ($text->contains_only_text and $text->trimmed_text ne '') {
            push @{$info->{info}}, $text->trimmed_text;
        }
        
    }
    
    my $notes = $SV->first_child('MatrixView')
                      ->first_child('VBoxView')
                      ->last_child('HBoxView');
    if (defined $notes) {
        $notes = $notes->first_child('VBoxView');
        if (defined $notes) {
            for my $text ($notes->first_child('TextView')
                                ->next_siblings('TextView')) {
                push @{$info->{notes}}, $text->trimmed_text;
            }
        }
    }
    
    $info->{id} = $info->{playlistId};
    
    $SV->delete if $opt{cleanup};
    
    return $info;
}


=item C<< artist >>

Returns an hashref of information about the artist.  Undefined results
if called on XML not from a viewArtist request.

=cut
sub artist {
    my ($self, %opt) = @_;
    my $root = $self->{twig}->root;
        
    $opt{cleanup} = defined $opt{cleanup}
                        ? $opt{cleanup}
                        : 1;
    
    my $info = { };
    
    # Get basic information about the album
    $info->{$_} = $root->att($_) for qw/artistId genreId/;
    $info->{id} = $info->{artistId};
    
    my $SV = $root->first_child('ScrollView');

    # Artist name
    $info->{name} = $SV->first_child('MatrixView')
                       ->first_child('View')
                       ->first_child('MatrixView')
                       ->first_child('TextView')
                       ->trimmed_text;
    
    # Website URL
    my $website = $SV->first_child('MatrixView')
                     ->first_child('View')
                     ->first_child('MatrixView')
                     ->first_child('VBoxView')
                     ->first_child('OpenURL');
    
    $info->{website} = $website->att('url')
        if defined $website;
    
    # Get the albums from this request
    $info->{albums} = [ ];
    
    my $mv = $SV->first_child('MatrixView')
                ->first_child('View')
                ->first_child('MatrixView')
                ->first_child('VBoxView')
                ->first_child('VBoxView');
    
    if (defined $mv) {
        for my $hbox ($mv->children('HBoxView')) {
            for my $vbox ($hbox->children('VBoxView')) {
                my $album  = $vbox->first_child('MatrixView')
                                  ->first_child('ViewAlbum');

                next if not defined $album;

                my %tmp = (
                    title   => $album->att('draggingName'),
                    id      => $album->att('id'),
                    playlistId => $album->att('id'),
                    cover   => { },
                );

                if (my $pic = $album->first_child('PictureView')) {
                    $tmp{cover} = {
                        height => $pic->att('height'),
                        width  => $pic->att('width'),
                        url    => $pic->att('url'),
                    };
                }
                
                push @{$info->{albums}}, \%tmp;
            }
        }
    }
    
    # Get range of albums if there is one
    for my $b ($SV->first_child('MatrixView')
                  ->first_child('View')
                  ->first_child('MatrixView')
                  ->first_child('VBoxView')
                  ->descendants('B')) {
        if ($b->trimmed_text =~ /^Albums: (\d+)-(\d+) of (\d+)$/) {
            $info->{albumStartNum} = $1;
            $info->{albumEndNum}   = $2;
            $info->{albumTotal}    = $3;
        }
    }
    
    $SV->delete if $opt{cleanup};
    
    return $info;
}

=item C<< purge >>

Purges the current root twig.

=cut
sub purge {
    my $self = shift;
    return $self->{twig}->purge;
}

=back

=head1 LICENSE

This work is licensed under the Creative Commons
Attribution-NonCommercial-ShareAlike License. To view a copy of this
license, visit L<http://creativecommons.org/licenses/by-nc-sa/1.0/>
or send a letter to:

    Creative Commons
    559 Nathan Abbott Way
    Stanford, California 94305, USA.

=head1 AUTHOR

Copyright (C) 2004, Thomas R. Sibley - L<http://zulutango.org:82/>.

=head1 SEE ALSO

L<Net::iTMS>

=cut

42;
