package Net::iTMS;
#
# Written by Thomas R. Sibley, <http://zulutango.org:82/>
#
#   Information on properly fetching the URLs and decrypting
#   the content thanks to Jason Rohrer.
#
use warnings;
use strict;

use vars '$VERSION';
$VERSION = '0.09';

use LWP::UserAgent;
use HTTP::Request;

use Crypt::CBC;
use Crypt::Rijndael;
use Digest::MD5;

=head1 NAME

Net::iTMS - Low(ish)-level interface to the iTunes Music Store (iTMS)

=head1 SYNOPSIS

    use Net::iTMS;

    my $iTMS    = Net::iTMS->new;
    my $results = $iTMS->search_for('Elliott Smith');
    
    my %tracklist = %{$results->TrackList};
    # See the Net::iTMS::XML doc for other methods

=head1 DESCRIPTION

Net::iTMS is a low-but-not-too-low-level interface to the iTunes Music
Store.  It handles the fetching, decrypting, and uncompressing of content
as well as provides a few convenience methods.

Further development will most likely include more convenience methods for
common tasks.  If there is a method you'd particularly like to see, contact
me (see website in AUTHOR section) about it, and I'll consider writing it.

Patches are welcome.  : )

=head2 Methods

All methods return C<undef> on error and (should) set an error message,
which is available through the C<error> method.  (Unless I note otherwise.)

B<Nota Bene:> Most of information-fetching methods return, by default, 
a L<Net::iTMS::XML> object which can be used to selectively extract
information from the XML.  If a different XML "parser" is in use,
the return value could be something totally different.

=over 12

=item C<< new([ debug => 1, [...] ]) >>

Takes an argument list of C<key => value> pairs.  The options available
are:

=over 24

=item C<< tmpdir => '/some/path' >>

Used to specify the path to the directory where temporary files should be
created.  Default's to L<File::Temp>'s default.

=item C<< debug => 0 or 1 >>

If set to a true value, debug messages to be printed to STDERR.

=item C<< parser => 'Foo::Bar' >>

"Parser" to use in place of the default L<Net::iTMS::XML>.  Don't
change this unless you know what you're doing.

=back

Returns a blessed hashref (object) for Net::iTMS.

=cut
sub new {
    my ($class, %opt) = @_;

    my $ua = LWP::UserAgent->new;
    $ua->agent('iTunes/4.2 (Macintosh; U; PPC Mac OS X 10.2)');
    
    my $parser = defined $opt{parser} ? $opt{parser} : 'Net::iTMS::XML';
    eval qq{ require $parser }; die $@ if $@;
    
    return bless {
        error   => '',
        debug   => defined $opt{debug} ? $opt{debug} : 0,
        tmpdir  => defined $opt{tmpdir} ? $opt{tmpdir} : undef,
        _parser => $parser,
        _ua     => $ua,
        _url    => {
            search => 'http://phobos.apple.com/WebObjects/MZSearch.woa/wa/com.apple.jingle.search.DirectAction/search?term=',
            viewAlbum => 'http://ax.phobos.apple.com.edgesuite.net/WebObjects/MZStore.woa/wa/viewAlbum?playlistId=',
            viewArtist => 'http://ax.phobos.apple.com.edgesuite.net/WebObjects/MZStore.woa/wa/viewArtist?artistId=',
            biography => 'http://ax.phobos.apple.com.edgesuite.net/WebObjects/MZStore.woa/wa/com.apple.jingle.app.store.DirectAction/biography?artistId=',
            influencers => 'http://ax.phobos.apple.com.edgesuite.net/WebObjects/MZStore.woa/wa/com.apple.jingle.app.store.DirectAction/influencers?artistId=',
            browseArtist => 'http://ax.phobos.apple.com.edgesuite.net/WebObjects/MZStore.woa/wa/com.apple.jingle.app.store.DirectAction/browseArtist?artistId=',
        },
    }, $class;
}

=item C<search_for($terms)>

Does a simple search of the catalog.

=cut
sub search_for {
    my ($self, $query) = @_;
    
    return $self->fetch_iTMS_info($self->_url('search') . $query);
}

=item C<get_album($albumId)>

Takes an albumId and fetches the album information page.

=cut
sub get_album {
    my ($self, $id) = @_;
    
    return $id
            ? $self->fetch_iTMS_info($self->_url('viewAlbum') . $id)
            : $self->_set_error('No album ID passed.');
}

=item C<get_artist($artistId)>

Takes an artistId and fetches the artist information page.

=cut
sub get_artist {
    my ($self, $id) = @_;
    
    return $id
            ? $self->fetch_iTMS_info($self->_url('viewArtist') . $id)
            : $self->_set_error('No artist ID passed.');
}

=item C<get_artist_biography($artistId)>

Takes an artistId and fetches the artist's iTMS biography, if there
is one.

=cut
sub get_artist_biography {
    my ($self, $id) = @_;
    
    return $id
            ? $self->fetch_iTMS_info($self->_url('biography') . $id)
            : $self->_set_error('No artist ID passed.');
}

=item C<get_artist_influencers($artistId)>

Takes an artistId and fetches the artist's iTMS influencers, if there
are any.

=cut
sub get_artist_influencers {
    my ($self, $id) = @_;
    
    return $id
            ? $self->fetch_iTMS_info($self->_url('influencers') . $id)
            : $self->_set_error('No artist ID passed.');
}

=item C<get_artist_discography($artistId)>

Takes an artistId and fetches all the albums (really a browseArtist
request).

=cut
sub get_artist_discography {
    my ($self, $id) = @_;
    
    return $id
            ? $self->fetch_iTMS_info($self->_url('browseArtist') . $id)
            : $self->_set_error('No artist ID passed.');
}

=item C<< fetch_iTMS_info($url, [ gunzip => 1, decrypt => 0 ]) >>

This is one of the lower-level methods used mostly internally for
convenience.  Still, it might be of use to implement something I
haven't thought of.

It takes a URL (that should be for the iTMS) as the first argument
and an optional hashref of options as the second argument.  The
available options are:

=over 24

=item C<< gunzip => 0 or 1 >>

A true value means the (presumably) gzipped content is gunzipped.  A false
value means it is not.

Default is 1 (unzip content).

=item C<< decrypt => 0, 1, or 2 >>

A true value other than 2 means the content retrieved from the URL is first
decrypted after fetching if it appears to be encrypted (that is, if no
initialization vector was passed as a response header for the request).
A false value means no decryption is done at all.  A value of 2 means
decryption will be forced no matter what.

Default is 1 ("intelligent" decrypt), which should work for most, if not all,
cases.

=back

=cut
sub fetch_iTMS_info {
    my ($self, $url) = @_;
    
    my $opt = defined $_[2] ? $_[2] : { };
    
    my $xml = $self->_fetch_iTMS_data($url, $opt)
                or return undef;
    
    $self->_debug($xml);
    $self->_debug("Parsing $url");
    
    return $self->{_parser}->new($xml)->parse
                || $self->_set_error('Error parsing XML!');
}

=item C<error>

Returns a string containing an error message (if there is one).
Usually useful after a method has returned C<undef> for finding
out what went wrong.

=cut
sub error {
    my $self = shift;
    return $self->{error};
}

sub _fetch_iTMS_data {
    my ($self, $url, $userOpt) = @_;
    
    return $self->_set_error('No URL specified!')
            if not $url;
    
    my $opt = { gunzip => 1, decrypt => 1 };
    if (defined $userOpt) {
        for (qw/gunzip decrypt/) {
            $opt->{$_} = $userOpt->{$_} if exists $userOpt->{$_};
        }
    }
    
    $self->_debug('Sending HTTP request...');
    # Create and send request
    my $req = HTTP::Request->new(GET => $url);
    $self->_set_request_headers($req);
    
    my $res = $self->{_ua}->request($req);

    if (not $res->is_success) {
        return $self->_set_error('HTTP request failed!' . "\n\n" . $req->as_string);
    }

    $self->_debug('Successful request!');
    
    if ($opt->{decrypt}) {
        $self->_debug('Decrypting content...');
        
        # Since the key is static, we can just hard-code it here
        my $iTunesKey = pack 'H*', '8a9dad399fb014c131be611820d78895';

        #
        # Create the AES CBC decryption object using the iTunes key and the
        # initialization vector (x-apple-crypto-iv)
        #
        my $cbc = Crypt::CBC->new({
                        key             => $iTunesKey,
                        cipher          => 'Rijndael',
                        iv              => pack ('H*', $res->header('x-apple-crypto-iv')),
                        regenerate_key  => 0,
                        padding         => 'standard',
                        prepend_iv      => 0,
                  });

        # Try to intelligently determine whether content is actually
        # encrypted.  If it isn't, skip the decryption unless the caller
        # explicitly wants us to decrypt (the decrypt option = 2).
        
        my $decrypted;
        
        if ($opt->{decrypt} == 2 or $res->header('x-apple-crypto-iv')) {
            $decrypted = $cbc->decrypt($res->content);
        } else {
            $self->_debug('  Content looks unencrypted... skipping decryption');
            $decrypted = $res->content;
        }

        if ($opt->{gunzip}) {
            $self->_debug('Uncompressing content...');

            return $self->_gunzip_data($decrypted);
        } else {
            return $decrypted;
        }
    }
    elsif ($opt->{gunzip}) {
        $self->_debug('Uncompressing content...');
        
        return $self->_gunzip_data($res->content);
    }
    else {
        return $res->content;
    }
}

sub _gunzip_data {
    my ($self, $data) = @_;
    
    # Write gzipped data to temporary file
    my $template = 'net-itms.XXXXXXXXX';
    my $dir = defined $self->{tmpdir}
                ? $self->{tmpdir}
                : '.';
    
    use File::MkTemp qw(mkstempt);
    
    $self->_debug('Writing gzipped data to temp file...');
    
    my ($fh, $fname) = mkstempt($template, $dir);
    binmode $fh;    # For win32 users
    print $fh $data;
    $fh->close;
        
    # Use Compress::Zlib to decompress it
    use Compress::Zlib qw(gzopen Z_STREAM_END);
    
    my $gz = gzopen("$dir/$fname", 'rb')
                or return $self->_set_error('Open of _gunzip_data tmpfile failed!');
    
    my ($xml, $buffer);

    $xml .= $buffer
        while $gz->gzread($buffer) > 0;

    if ($gz->gzerror != Z_STREAM_END) {
        return $self->_set_error('Error while uncompressing gzipped data: "',
                                    $gz->gzerror, '"');
    }
    $gz->gzclose;
    
    $self->_debug('Removing tmpfile...');
    unlink "$dir/$fname";
    
    return $xml;
}

sub _set_request_headers {
    my $req = $_[1];
    $req->header('Accept-Language'  => 'en-us, en;q=0.50');
    $req->header('Cookie'           => 'countryVerified=1');
    $req->header('Accept-Encoding'  => 'gzip, x-aes-cbc');
}

sub _url {
    my ($self, $url) = @_;

    return defined $self->{_url}->{$url}
                ? $self->{_url}->{$url}
                : $self->_set_error('No URL found!');
}

sub _debug {
    my $self = shift;
    print STDERR @_, "\n" if $self->{debug};
    return 1;
}

sub _set_error {
    my $self = shift;
    $self->{error} = join '', @_;
    $self->_debug($self->{error});
    return undef;
}

=back

=head1 TODO / FUTURE DIRECTION

I'm thinking of totally changing the public interface.

The subclasses Net::iTMS::Album, Net::iTMS::Artist, Net::iTMS::Song, et al.
would represent individual artists, albums, and songs.

Code would then look like:

    my $iTMS = Net::iTMS->new;

    my $artist = $iTMS->get_artist(123456);
    # or maybe...
    my $artist = $iTMS->find_artist('Elliott Smith');

    print "Artist: ", $artist->name, "\n";

    for my $album ($artist->discography) {
        print $album->title, "(", $album->year, ")\n";

        for my $track ($album->tracks) {    # also $album->songs
            print "\t ", $track->number, ": ", $track->title, "\n";
        }
    }

instead of

    my $iTMS = Net::iTMS->new;

    my $artist = $iTMS->get_artist(123456);
    print "Artist: ", $artist->{name}, "\n";
    
    for my $album ($iTMS->get_artist_discography(123456)) {
        print $album->{playlistName}, ..., "\n";
        
        my $tracks = $iTMS->get_album($album->{playlistId})
                          ->genericPlist;
        
        for my $track (@$tracks) {
            print "\t ", $track->{trackNumber}, ": ", $track->{songName}, "\n";
        }
    }
    
Could this be made B<efficient> -- that is, minimal # of HTTP requests?
Would it require a major rewrite of existing XML munging code?  It would
certainly be easier to work with.

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

=cut

42;
