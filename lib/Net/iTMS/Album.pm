package Net::iTMS::Album;
#
# Written by Thomas R. Sibley, <http://zulutango.org:82/>
#
use warnings;
use strict;

use vars '$VERSION';
$VERSION = '0.10';

use Net::iTMS::Error;

=head1 NAME

Net::iTMS::Album - Represents an album in the iTunes Music Store

=head1 SYNOPSIS

    use Net::iTMS::Album;

    my $album = Net::iTMS::Album->new($iTMS, $id);
    
    print "Album: ", $album->title, "\n";

    # $track will be a Net::iTMS::Song object
    for my $track ($album->tracks) {    # also $album->songs
        print "\t ", $track->number, ": ", $track->title, "\n";
    }

=head1 DESCRIPTION

Net::iTMS::Album represents an album in the iTMS and encapsulates the
associated data.  If a piece of information hasn't been fetched from the
iTMS, it will transparently fetch and store it for later use before
returning.

If any method, excepting C<id> and C<thumb>, is called, the information
for the others will be fetched in the same request.  This means, for
these methods, the first call to one will have a time hit for the
HTTP request, but subsequent calls won't.

=head2 Methods

=over 12

=item new($itms, $albumId)

The first argument must be an instance of Net::iTMS, the second an
iTMS album ID.

Returns a blessed hashref (object) for Net::iTMS::Album.

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

Returns the ID of the album (C<albumId>).

=item title

=item name

Returns the title of the album.

=item artist

Returns a L<Net::iTMS::Artist> object for the album's artist.

=item genre

Returns a L<Net::iTMS::Genre> object for the album's genre.

=item cover

Returns a hashref with the keys C<url>, C<width>, and C<height> which
are for the album's cover.

=item thumb

Returns a hashref with the keys C<url>, C<width>, and C<height> which
are for the thumbnail of the album's cover.

=item path

Returns an arrayref of hashrefs representing the album's "path" in the iTMS.
The hashrefs contain the name of the node in the path and the iTMS URL of that
node.

=item tracks

=item songs

Returns an array or arrayref (depending on context) of L<Net::iTMS::Song> objects
representing the tracklist of the album (in order of track number).

=cut
sub id { return $_[0]->{id} }

sub title {
    my $self = shift;
    $self->_get_basic_info
        if not exists $self->{title};
    return $self->{title};
}

sub name { return $_[0]->title }

sub artist {
    my $self = shift;
    $self->_get_basic_info
        if not exists $self->{artist};
    return $self->{artist};
}

sub genre {
    my $self = shift;
    $self->_get_basic_info
        if not exists $self->{genre};
    return $self->{genre};
}

sub cover {
    my $self = shift;
    $self->_get_basic_info
        if not exists $self->{cover};
    return $self->{cover};
}

sub thumb {
    my $self = shift;
    return $self->{thumb};
}

sub tracks {
    my $self = shift;
    $self->_get_basic_info
        if not exists $self->{tracks};
    return wantarray ? @{$self->{tracks}} : $self->{tracks};
}

sub songs { return $_[0]->tracks }

sub info {
    my $self = shift;
    $self->_get_basic_info
        if not exists $self->{info};
    return wantarray ? @{$self->{info}} : $self->{info};
}

sub notes {
    my $self = shift;
    $self->_get_basic_info
        if not exists $self->{notes};
    return wantarray ? @{$self->{notes}} : $self->{notes};
}

sub path {
    my $self = shift;
    $self->_get_basic_info
        if not exists $self->{path};
    return wantarray ? @{$self->{path}} : $self->{path};
}

#
# This populates the basic data from a viewAlbum request
#
sub _get_basic_info {
    my $self = shift;
    
    my $twig = $self->{_itms}->{_request}->url('viewAlbum', $self->id);
    
    my $root = $twig->root;
    my $path = $root->first_child('Path');
    my $sv   = $root->first_child('ScrollView');
    
    $self->{genre} = $self->{_itms}->get_genre($root->att('genreId'));
    
    #
    # Path
    #
    for my $child ($path->children('PathElement')) {
        push @{$self->{path}}, {
            name => $child->att('displayName'),
            url  => $child->trimmed_text,
        };
    }
    
    $path->delete;

    #
    # Name and cover
    #
    # We could just depend on the right twig being the first
    # in the document everytime, but let's not
    #
    my $album;
    for my $child ($sv->descendants('ViewAlbum')) {
        if (defined $child->{att}{draggingName}
                and $child->first_child_matches('PictureView')) {
            # This is the one we want, so break out
            $album = $child;
            last;
        }
    }
    
    $self->{title} = $album->att('draggingName');

    my $pic = $album->first_child('PictureView');
    $self->{cover} = {
        height => $pic->att('height'),
        width  => $pic->att('width'),
        url    => $pic->att('url'),
    };
    
    $pic->delete;
    $album->delete;
    
    #
    # Artist
    #
    if (not defined $self->{artist}) {
        my $artist;
        for my $child ($sv->descendants('ViewArtist')) {
            if (defined $child->{att}{id}
                    and $child->{att}{id} eq $root->att('artistId')) {
                # This is the one we want, so break out
                $artist = $child;
                last;
            }
        }

        if (defined $artist) {
            $self->{artist} = $self->{_itms}->get_artist(
                                    $root->att('artistId'),
                                    name => $artist->trimmed_text,
                              );
            $artist->delete;
        }
    }
    
    #
    # Info
    #        
    for my $text ($sv->first_child('MatrixView')
                     ->first_child('VBoxView')
                     ->first_child('MatrixView')
                     ->first_child('VBoxView')
                     ->children('TextView')) {
        if ($text->contains_only_text and $text->trimmed_text ne '') {
            push @{$self->{info}}, $text->trimmed_text;
        }
    }
    
    #
    # Notes
    #
    my $notes = $sv->first_child('MatrixView')
                   ->first_child('VBoxView')
                   ->last_child('HBoxView');

    if (defined $notes) {
        $notes = $notes->first_child('VBoxView');
        if (defined $notes) {
            for my $text ($notes->first_child('TextView')
                                ->next_siblings('TextView')) {
                push @{$self->{notes}}, $text->trimmed_text;
            }
        }
        $notes->delete;
    }
    
    $sv->delete;
    
    #
    # Tracks
    #
    my $plist = $root->first_child('TrackList')
                     ->first_child('plist')
                     ->first_child('dict')
                     ->first_child('array');
    
    $self->{tracks} = [ ];
    
    for my $dict ($plist->children('dict')) {
        my %data;
        for my $key ($dict->children('key')) {
            $data{$key->trimmed_text} = $key->next_sibling->trimmed_text;
        }

        $data{releaseDate} =~ s/A-Za-z//g;
        
        push @{$self->{tracks}},
             $self->{_itms}->get_song(
                    $data{songId},
                    title       => $data{songName},
                    album       => $self,
                    artist      => $self->{artist},
                    genre       => $self->{_itms}->get_genre(
                                        $data{genreId},
                                        name => $data{genre},
                                   ),
                    year        => $data{year},
                    number      => $data{trackNumber},
                    count       => $data{trackCount},
                    disc_number => $data{discNumber},
                    disc_count  => $data{discCount},
                    explicit    => $data{explicit},
                    comments    => $data{comments},
                    copyright   => $data{copyright},
                    preview_url => $data{previewUrl},
                    released    => $data{releaseDate},
                    price       => $data{priceDisplay},
                    vendor      => $data{vendorId},
             );
    }
    $plist->delete;
    $twig->purge;
}

=back

=head1 LICENSE

Copyright 2004, Thomas R. Sibley.

This work is licensed under the Creative Commons
Attribution-NonCommercial-ShareAlike License. To view a copy of this
license, visit L<http://creativecommons.org/licenses/by-nc-sa/2.0/>
or send a letter to:

    Creative Commons
    559 Nathan Abbott Way
    Stanford, California 94305, USA.

=head1 AUTHOR

Thomas R. Sibley, L<http://zulutango.org:82/>

=head1 SEE ALSO

L<Net::iTMS>, L<Net::iTMS::Song>, L<Net::iTMS::Artist>, L<Net::iTMS::Genre>

=cut

42;
