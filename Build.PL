use Module::Build;

Module::Build->new(
    module_name         => 'Net::iTMS',
    dist_author         => 'Thomas Sibley, http://zulutango.org:82/',
    dist_abstract       => 'For interacting with and retrieving information from the iTunes Music Store',
    license             => 'unrestricted',

    # I don't know the earliest module versions that will
    # work... sorry
    requires            => {
        'LWP::UserAgent'    => 0,
        'HTTP::Request'     => 0,
        'Crypt::CBC'        => 0,
        'Crypt::Rijndael'   => 0,
        'Digest::MD5'       => 0,
        'File::MkTemp'      => 0,
        'Compress::Zlib'    => 0,
        'XML::Twig'         => 0,
    },    
    create_makefile_pl  => 'passthrough',
)->create_build_script;
