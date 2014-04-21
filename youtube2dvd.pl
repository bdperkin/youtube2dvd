#!/usr/bin/perl -w
#
# %{NAME}.pl - YouTube video downloader and DVD authoring tool.
# Copyright (C) 2014-2014  Brandon Perkins <bperkins@redhat.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
# USA.
#

################################################################################
# Import some semantics into the current package from the named modules
################################################################################
use strict;                               # Restrict unsafe constructs
use warnings;                             # Control optional warnings
use File::Compare;                        # Compare files or filehandles
use File::Find::Rule;                     # Alternative interface to File::Find
use File::LibMagic;                       # Determine MIME types of data or
                                          # files using libmagic
use File::Path;                           # Create or remove directory trees
use Getopt::Long;                         # Getopt::Long - Extended processing
                                          # of command line options
use IO::Select;                           # OO interface to the select system
                                          # call
use IPC::Open3;                           # open a process for reading, writing,
                                          # and error handling using open3()
use URI::Split qw(uri_split uri_join);    # URI::Split - Parse and compose URI
                                          # strings
use WWW::Curl::Easy;                      # WWW::Curl - Perl extension interface
                                          # for libcurl
use XML::XPath;                           # XML::XPath - a set of modules for
                                          # parsing and evaluating XPath
                                          # statements

################################################################################
# Declare constants
################################################################################
binmode STDOUT, ":utf8";    # Out/Err/Input UTF-8 using the :utf8
binmode STDERR, ":utf8";    # out/err/input layer.  This ensures that the
binmode STDIN,  ":utf8";    # out/err/input is completelyUTF-8, and removes any
                            # debug warnings.

$ENV{PATH} = "/usr/bin:/bin";

my $sitemap = "http://www.lego.com/en-us/videos/sitemap?xml=1";

my $headers = "";
my $body    = "";

my $cn = "Cannot";

################################################################################
# Specify module configuration options to be enabled
################################################################################
# Allow single-character options to be bundled. To distinguish bundles from long
# option names, long options must be introduced with '--' and bundles with '-'.
# Do not allow '+' to start options.
Getopt::Long::Configure(qw(bundling no_getopt_compat));

################################################################################
# Initialize variables
################################################################################
my $DBG            = 1;  # Set debug output level:
                         #   0 -- quiet
                         #   1 -- normal
                         #   2 -- verbose
                         #   3 -- debug
my $curloptverbose = 0;  # Set the parameter to 1 to get the library to display
                         # a lot of verbose information about its operations.
                         # Very useful for libcurl and/or protocol debugging and
                         # understanding. The verbose information will be sent
                         # to stderr, or the stream set with CURLOPT_STDERR. The
                         # default value for this parameter is 0.
my $vidcounter     = 0;  # Counter for videos
my $totalvideos    = 0;  # Total number of videos

################################################################################
# Parse command line options.  This function adheres to the POSIX syntax for CLI
# options, with GNU extensions.
################################################################################
# Initialize GetOptions variables
my $optattempts = 3;
my $optcurlverbose;
my $optdebug;
my $optdownload = ".";
my $optgallery  = ".*";
my $optlist;
my $optquiet;
my $optverbose;

GetOptions(
    "a=i"        => \$optattempts,
    "attempts=i" => \$optattempts,
    "C"          => \$optcurlverbose,
    "curlvrbs"   => \$optcurlverbose,
    "d"          => \$optdebug,
    "debug"      => \$optdebug,
    "D=s"        => \$optdownload,
    "download=s" => \$optdownload,
    "g=s"        => \$optgallery,
    "gallery=s"  => \$optgallery,
    "l"          => \$optlist,
    "list"       => \$optlist,
    "q"          => \$optquiet,
    "quiet"      => \$optquiet,
    "t=s"        => \$optgallery,
    "theme=s"    => \$optgallery,
    "v"          => \$optverbose,
    "verbose"    => \$optverbose,
);

################################################################################
# Set output level
################################################################################
# If multiple outputs are specified, the most verbose will be used.
if ($optquiet) {
    $DBG = 0;
} else {
    $| = 1;
}

if ($optverbose) {
    $DBG = 2;
}
if ($optdebug) {
    $DBG = 3;
}

################################################################################
# Main function
################################################################################
if ( $DBG > 0 ) {
    print "Loading...";
}
if ( $DBG > 2 ) { print "Initializing WWW::Curl::Easy...\n"; }
my $browser = WWW::Curl::Easy->new;    # an alias for WWW::Curl::Easy::init

if ($optcurlverbose) {
    $curloptverbose = 1;
}
if ( $DBG > 2 ) { print "Setting CURLOPT_VERBOSE to $curloptverbose...\n"; }
$browser->setopt( CURLOPT_VERBOSE, $curloptverbose );

if ( $DBG > 2 ) {
    print "CURLVERSION_NOW is: " . $browser->version(CURLVERSION_NOW) . "\n";
}

# Configure browser and get sitemap
if ( $DBG > 2 ) { print "Setting CURLOPT_URL to $sitemap...\n"; }
my $code = $browser->setopt( CURLOPT_URL, $sitemap );
if ( $DBG > 2 ) { print "Setting CURLOPT_WRITEHEADER variable...\n"; }
$code = $browser->setopt( CURLOPT_WRITEHEADER, \$headers );
if ( $DBG > 2 ) { print "Setting CURLOPT_FILE variable...\n"; }
$code = $browser->setopt( CURLOPT_FILE, \$body );
if ( $DBG > 2 ) { print "Performing GET...\n"; }
$code = $browser->perform();
my $err = $browser->errbuf;    # report any error message

if ($code) {
    die "\n$cn get "
      . $sitemap . " -- "
      . $code . " "
      . $browser->strerror($code) . " "
      . $err . "\n";
} ## end if ($code)

unless ( $browser->getinfo(CURLINFO_CONTENT_TYPE) =~ m/^application\/xml/ ) {
    die "\nDid not receive XML, got -- "
      . $browser->getinfo(CURLINFO_CONTENT_TYPE) . "\n";
} else {
    if ( $DBG > 1 ) {
        print "Got videos from " . $sitemap . "\n";
    }
}

my $info = $browser->getinfo(CURLINFO_SIZE_DOWNLOAD);
if ( $DBG > 2 ) { print "Got CURLINFO_SIZE_DOWNLOAD as $info.\n"; }

# Parse sitemap data
if ( $DBG > 2 ) { print "Initializing XML::XPath...\n"; }
my $xp = XML::XPath->new($body);

my %gallery;
my %gallerycount;

if ( $DBG > 2 ) { print "Finding URLs within URL Set...\n"; }
my $urlnodes = $xp->find('/urlset/url');
if ( $DBG > 2 ) { print "Getting node list...\n"; }
foreach my $url ( $urlnodes->get_nodelist ) {
    $vidcounter++;
    $totalvideos = $vidcounter;
    if ( $DBG > 1 ) {
        print "\rLoading...$totalvideos ";
    }
    if ( $DBG > 0 ) {
        print ".";
    }
    my $locnode  = $url->find('loc');
    my $vidnodes = $url->find('video:video');
    foreach my $video ( $vidnodes->get_nodelist ) {
        my $video_thumbnail_loc     = $video->find('video:thumbnail_loc');
        my $video_title             = $video->find('video:title');
        my $video_description       = $video->find('video:description');
        my $video_content_loc       = $video->find('video:content_loc');
        my $video_duration          = $video->find('video:duration');
        my $video_publication_date  = $video->find('video:publication_date');
        my $video_expiration_date   = $video->find('video:expiration_date');
        my $video_view_count        = $video->find('video:view_count');
        my $video_family_friendly   = $video->find('video:family_friendly');
        my $video_gallery_loc       = $video->find('video:gallery_loc');
        my $video_gallery_loc_title = $video->find('video:gallery_loc/@title');

        my $vt    = $video_title->string_value;
        my $vglt  = $video_gallery_loc_title->string_value;
        my $urlsv = $url->string_value;
        my $lnsv  = $locnode->string_value;
        my $vtl   = $video_thumbnail_loc->string_value;
        my $vde   = $video_description->string_value;
        my $vcl   = $video_content_loc->string_value;
        my $vdu   = $video_duration->string_value;
        my $vpd   = $video_publication_date->string_value;
        my $ved   = $video_expiration_date->string_value;
        my $vvc   = $video_view_count->string_value;
        my $vff   = $video_family_friendly->string_value;
        my $vgl   = $video_gallery_loc->string_value;

        if ( $DBG > 1 ) {
            my $prtstdout = sprintf( "[ %.30s ] %-.45s\r", $vglt, $vt );
            $prtstdout =~ s/[^[:ascii:]]//g;
            print $prtstdout;
        }

        if ( $DBG > 2 ) {
            print "$vidcounter\t\t" . $urlsv . "\n";
            print "$vidcounter\tloc\t" . $lnsv . "\n";
            print "$vidcounter\t\tvideo:thumbnail_loc\t" . $vtl . "\n";
            print "$vidcounter\t\tvideo:title\t" . $vt . "\n";
            print "$vidcounter\t\tvideo:description\t" . $vde . "\n";
            print "$vidcounter\t\tvideo:content_loc\t" . $vcl . "\n";
            print "$vidcounter\t\tvideo:duration\t" . $vdu . "\n";
            print "$vidcounter\t\tvideo:publication_date\t" . $vpd . "\n";
            print "$vidcounter\t\tvideo:expiration_date\t" . $ved . "\n";
            print "$vidcounter\t\tvideo:view_count\t" . $vvc . "\n";
            print "$vidcounter\t\tvideo:family_friendly\t" . $vff . "\n";
            print "$vidcounter\t\tvideo:gallery_loc\t" . $vgl . "\n";
            print "$vidcounter\t\tvideo:gallery_loc/\@title\t" . $vglt . "\n";
        } ## end if ( $DBG > 2 )

        my $vgpath = $vgl;
        my @revvgpath = reverse( split( /\//, $vgpath ) );
        $gallery{ $revvgpath[0] } = $vglt;
        if ( $gallerycount{ $revvgpath[0] } ) {
            $gallerycount{ $revvgpath[0] }++;
        } else {
            $gallerycount{ $revvgpath[0] } = 1;
        }
        unless ($optlist) {
            if ( $revvgpath[0] =~ m/^$optgallery$/i ) {
                if ( $DBG > 0 ) {
                    print "!";
                }
                my ( $scheme, $auth, $path, $query, $frag ) =
                  uri_split($locnode);
                my $dirname = $optdownload . $path;
                unless ( -d "$dirname" ) {
                    unless ( mkpath($dirname) ) {
                        die "$cn create content directory $dirname: $!\n";
                    }
                }
                my $try = 0;
                my $chk = 1;
                while ( $try lt $optattempts ) {
                    my $tryname = $dirname . "/" . $try;
                    my $chkname = $dirname . "/" . $chk;
                    unless ( -d "$tryname" ) {
                        unless ( mkpath($tryname) ) {
                            die "$cn create content directory $tryname: $!\n";
                        }
                    }

                    xml2txt( $tryname, $chkname, "loc.txt", $lnsv );

                    xml2txt( $tryname, $chkname, "thumbnail_loc.txt", $vtl );
                    my $wgetthumb;
                    if ($vtl) {
                        $wgetthumb =
                          wget( $tryname, $chkname, basename($vtl), $vtl );
                        if ($wgetthumb) {
                            unlink( $tryname . "/" . basename($vtl) );
                        }
                    } else {
                        if ( $DBG > 0 ) {
                            warn "No URI found for $tryname thumbnail_loc!\n";
                        }
                    }

                    xml2txt( $tryname, $chkname, "title.txt", $vt );

                    xml2txt( $tryname, $chkname, "description.txt", $vde );

                    xml2txt( $tryname, $chkname, "content_loc.txt", $vcl );
                    my $wgetcont;
                    if ($vcl) {
                        $wgetcont =
                          wget( $tryname, $chkname, basename($vcl), $vcl );
                        if ($wgetcont) {
                            unlink( $tryname . "/" . basename($vcl) );
                        }
                    } else {
                        if ( $DBG > 0 ) {
                            warn "No URI found for $tryname content_loc!\n";
                        }
                    }

                    xml2txt( $tryname, $chkname, "duration.txt", $vdu );

                    xml2txt( $tryname, $chkname, "publication_date.txt", $vpd );

                    xml2txt( $tryname, $chkname, "expiration_date.txt", $ved );

                    xml2txt( $tryname, $chkname, "gallery_loc.txt", $vgl );

                    xml2txt( $tryname, $chkname, "gallery_title.txt", $vglt );

                    $try++;
                    $chk++;
                    if ( $chk eq $optattempts ) {
                        $chk = 0;
                    }

                    unless ( $wgetthumb || $wgetcont ) {
                        convert( $tryname, $chkname, basename($vcl), "mpg" );
                        convert( $tryname, $chkname, basename($vcl), "ac3" );
                        convert( $tryname, $chkname, basename($vcl), "m2v" );
                        convert( $tryname, $chkname, basename($vcl), "wav" );
                        convert( $tryname, $chkname, basename($vcl), "pcm" );
                    } ## end unless ( $wgetthumb || $wgetcont)
                } ## end while ( $try lt $optattempts)
            } ## end if ( $revvgpath[0] =~ ...)
        } ## end unless ($optlist)
    } ## end foreach my $video ( $vidnodes...)
} ## end foreach my $url ( $urlnodes...)

$browser->cleanup();    # optional

if ($optlist) {
    if ( $DBG > 0 ) {
        print "\n";
    }
    foreach my $title (
        sort { $gallerycount{$b} <=> $gallerycount{$a} }
        keys %gallerycount
      )
    {
        my $prtstdout = sprintf(
            "\t* [%3d] %-20s %s\n", $gallerycount{$title}, $title,
            $gallery{$title}
        );
        $prtstdout =~ s/[^[:ascii:]]//g;
        print $prtstdout;
    } ## end foreach my $title ( sort { ...})
    exit;
} ## end if ($optlist)

foreach my $title ( keys %gallery ) {
    if ($optgallery) {
        if ( $title =~ m/^$optgallery$/i ) {
            normalize($title);
        }
    } else {
        normalize($title);
    }
} ## end foreach my $title ( keys %gallery)

$vidcounter = 0;    # Counter for videos
foreach my $url ( $urlnodes->get_nodelist ) {
    $vidcounter++;
    if ( $DBG > 1 ) {
        print "\rLoading...$vidcounter/$totalvideos ";
    }
    if ( $DBG > 0 ) {
        print ".";
    }
    my $locnode  = $url->find('loc');
    my $vidnodes = $url->find('video:video');
    foreach my $video ( $vidnodes->get_nodelist ) {
        my $video_thumbnail_loc     = $video->find('video:thumbnail_loc');
        my $video_title             = $video->find('video:title');
        my $video_description       = $video->find('video:description');
        my $video_content_loc       = $video->find('video:content_loc');
        my $video_duration          = $video->find('video:duration');
        my $video_publication_date  = $video->find('video:publication_date');
        my $video_expiration_date   = $video->find('video:expiration_date');
        my $video_view_count        = $video->find('video:view_count');
        my $video_family_friendly   = $video->find('video:family_friendly');
        my $video_gallery_loc       = $video->find('video:gallery_loc');
        my $video_gallery_loc_title = $video->find('video:gallery_loc/@title');

        my $vt    = $video_title->string_value;
        my $vglt  = $video_gallery_loc_title->string_value;
        my $urlsv = $url->string_value;
        my $lnsv  = $locnode->string_value;
        my $vtl   = $video_thumbnail_loc->string_value;
        my $vde   = $video_description->string_value;
        my $vcl   = $video_content_loc->string_value;
        my $vdu   = $video_duration->string_value;
        my $vpd   = $video_publication_date->string_value;
        my $ved   = $video_expiration_date->string_value;
        my $vvc   = $video_view_count->string_value;
        my $vff   = $video_family_friendly->string_value;
        my $vgl   = $video_gallery_loc->string_value;

        if ( $DBG > 1 ) {
            my $prtstdout = sprintf( "[ %.30s ] %-.45s\r", $vglt, $vt );
            $prtstdout =~ s/[^[:ascii:]]//g;
            print $prtstdout;
        }

        if ( $DBG > 2 ) {
            print "$vidcounter\t\t" . $urlsv . "\n";
            print "$vidcounter\tloc\t" . $lnsv . "\n";
            print "$vidcounter\t\tvideo:thumbnail_loc\t" . $vtl . "\n";
            print "$vidcounter\t\tvideo:title\t" . $vt . "\n";
            print "$vidcounter\t\tvideo:description\t" . $vde . "\n";
            print "$vidcounter\t\tvideo:content_loc\t" . $vcl . "\n";
            print "$vidcounter\t\tvideo:duration\t" . $vdu . "\n";
            print "$vidcounter\t\tvideo:publication_date\t" . $vpd . "\n";
            print "$vidcounter\t\tvideo:expiration_date\t" . $ved . "\n";
            print "$vidcounter\t\tvideo:view_count\t" . $vvc . "\n";
            print "$vidcounter\t\tvideo:family_friendly\t" . $vff . "\n";
            print "$vidcounter\t\tvideo:gallery_loc\t" . $vgl . "\n";
            print "$vidcounter\t\tvideo:gallery_loc/\@title\t" . $vglt . "\n";
        } ## end if ( $DBG > 2 )

        my $vgpath = $vgl;
        my @revvgpath = reverse( split( /\//, $vgpath ) );
        $gallery{ $revvgpath[0] } = $vglt;
        unless ($optlist) {
            if ( $revvgpath[0] =~ m/^$optgallery$/i ) {
                if ( $DBG > 0 ) {
                    print "!";
                }
                my ( $scheme, $auth, $path, $query, $frag ) =
                  uri_split($locnode);
                my $dirname = $optdownload . $path;
                unless ( -d "$dirname" ) {
                    unless ( mkpath($dirname) ) {
                        die "$cn create content directory $dirname: $!\n";
                    }
                }
                my $try = 0;
                my $chk = 1;
                while ( $try lt $optattempts ) {
                    my $tryname = $dirname . "/" . $try;
                    my $chkname = $dirname . "/" . $chk;
                    unless ( -d "$tryname" ) {
                        unless ( mkpath($tryname) ) {
                            die "$cn create content directory $tryname: $!\n";
                        }
                    }

                    $try++;
                    $chk++;
                    if ( $chk eq $optattempts ) {
                        $chk = 0;
                    }

                    convert( $tryname, $chkname, basename($vcl), "pcm" );
                    convert( $tryname, $chkname, basename($vcl), "mpa" );
                    convert(
                        $tryname,       $chkname,
                        basename($vcl), "mplex.mpg"
                    );
                } ## end while ( $try lt $optattempts)
            } ## end if ( $revvgpath[0] =~ ...)
        } ## end unless ($optlist)
    } ## end foreach my $video ( $vidnodes...)
} ## end foreach my $url ( $urlnodes...)

foreach my $title ( keys %gallery ) {
    if ($optgallery) {
        if ( $title =~ m/^$optgallery$/i ) {
            dvdgen($title);
        }
    } else {
        dvdgen($title);
    }
} ## end foreach my $title ( keys %gallery)

# Dump XML data into text files
sub xml2txt {
    my ( $tryname, $chkname, $filename, $filedata ) = @_;
    if ( !-f "$tryname/$filename" ) {
        unless ( open( TXTFILE, ">$tryname/$filename" ) ) {
            die "$cn create text file $filename in $tryname: $!\n";
        }
        binmode TXTFILE, ":utf8";
        print TXTFILE $filedata . "\n";
        close(TXTFILE);
    } ## end if ( !-f "$tryname/$filename")
    check( $tryname, $chkname, $filename );
} ## end sub xml2txt

# Get the base file name based on a full path
sub basename {
    my $fulluri  = $_[0];
    my @fullpath = split( /\//, $fulluri );
    my @revpath  = reverse(@fullpath);
    return $revpath[0];
} ## end sub basename

# Dump binary data into local files
sub wget {
    my ( $tryname, $chkname, $filename, $dluri ) = @_;
    if ( !-f "$tryname/$filename" ) {
        my $localfile = "$tryname/$filename";
        my $fileb;
        my $retry = 0;
        while ( $retry < $optattempts ) {
            $retry++;
            if ( $DBG > 2 ) { print "Setting CURLOPT_URL to $dluri...\n"; }
            $browser->setopt( CURLOPT_URL, $dluri );
            unless ( open( $fileb, ">", $localfile ) ) {
                die "$cn open $localfile for writing: $!\n";
            }
            binmode($fileb);
            if ( $DBG > 2 ) {
                print "Setting CURLOPT_WRITEDATA variable...\n";
            }
            $browser->setopt( CURLOPT_WRITEDATA, $fileb );
            if ( $DBG > 1 ) {
                print "+";
                if ( $DBG > 2 ) {
                    print
                      "Getting $dluri and saving content at $localfile...\n";
                }
            } ## end if ( $DBG > 1 )
            $code = $browser->perform();
            $err  = $browser->errbuf;      # report any error message

            if ($code) {
                warn "\n$cn get "
                  . $dluri . " -- "
                  . $code . " "
                  . $browser->strerror($code) . " "
                  . $err . "\n";
            } ## end if ($code)

            my $ct = "application\/xml";
            if ( $dluri =~ m/\.jpg$/ ) {
                $ct = "image\/jpeg";
            } elsif ( $dluri =~ m/\.mp4$/ ) {
                $ct = "video\/mp4";
            } else {
                die "$cn guess content-type based on $dluri\n";
            }

            unless ( $browser->getinfo(CURLINFO_CONTENT_TYPE) =~ m/^$ct/ ) {
                warn "\nDid not receive $ct, got -- "
                  . $browser->getinfo(CURLINFO_CONTENT_TYPE) . "\n";
                return 1;
            } else {
                if ( $DBG > 1 ) {
                    print "Got videos from " . $dluri . "\n";
                }
            }

            my $info = $browser->getinfo(CURLINFO_SIZE_DOWNLOAD);
            if ( $DBG > 2 ) { print "Got CURLINFO_SIZE_DOWNLOAD as $info.\n"; }

            if ( $retry > $optattempts ) {
                die "$cn get $dluri -- $code "
                  . $browser->strerror($code) . " "
                  . $browser->errbuf . "\n"
                  unless ( $code == 0 );
            } else {
                warn "$cn get $dluri -- $code "
                  . $browser->strerror($code) . " "
                  . $browser->errbuf . "\n"
                  unless ( $code == 0 );
            } ## end else [ if ( $retry > $optattempts)]
            close($fileb);
            if ( $DBG > 1 ) {
                print "done.\n";
            }
        } ## end while ( $retry < $optattempts)
    } ## end if ( !-f "$tryname/$filename")
    check( $tryname, $chkname, $filename );
    return 0;
} ## end sub wget

sub convert {
    my ( $tryname, $chkname, $filename, $task ) = @_;
    my $tryf = "$tryname/$filename";
    my $chkf = "$chkname/$filename";
    my $tfcf = "$tryf and $chkf";
    if ( !-f "$tryf" && !-d "$tryf" ) {
        die "$cn find file or directory $tryf: $!\n";
    }
    my $cmd;

    if ( -f $tryf . ".$task" || -d $tryf . ".$task" ) {
        if ( $DBG > 2 ) {
            print "File or directory" . $tryf . ".$task already exists.";
        }
        check( $tryname, $chkname, $filename . ".$task" );
        return 0;
    } ## end if ( -f $tryf . ".$task"...)

    if ( $task =~ m/^mpg$/ ) {
        my $nullaudio = "";
        $cmd =
            "/usr/bin/ffprobe -v info -select_streams a \""
          . $tryf
          . "\" 2>&1 | /usr/bin/grep '^    Stream #' |"
          . " /usr/bin/grep ': Audio: ' > /dev/null";
        if ( $DBG > 2 ) {
            warn("Checking for audio stream in $tryf with: \"$cmd\"");
        }
        my $rc = system($cmd);
        if ($rc) {
            warn(   "$tryf does not have an audio track,"
                  . " setting it to have one..." );
            $nullaudio = " -f lavfi -i aevalsrc=0 -shortest"
              . " -c:v copy -c:a aac -strict experimental ";
        } ## end if ($rc)
        $cmd =
            " /usr/bin/ffmpeg -y -i \""
          . $tryf . "\" "
          . $nullaudio
          . " -target ntsc-dvd -q:a 0 -q:v 0 \""
          . $tryf
          . ".$task" . "\"";
    } elsif ( $task =~ m/^ac3$/ ) {
        $cmd =
            " /usr/bin/ffmpeg -y -i \""
          . $tryf . ".mpg"
          . "\" -acodec copy -vn \""
          . $tryf
          . ".$task" . "\"";
    } elsif ( $task =~ m/^m2v$/ ) {
        $cmd =
            " /usr/bin/ffmpeg -y -i \""
          . $tryf . ".mpg"
          . "\" -vcodec copy -an \""
          . $tryf
          . ".$task" . "\"";
    } elsif ( $task =~ m/^wav$/ ) {
        $cmd =
            " /usr/bin/mplayer -noautosub -nolirc -benchmark "
          . "-vc null -vo null "
          . "-ao pcm:waveheader:fast:file=\""
          . $tryf
          . ".$task" . "\" \""
          . $tryf . ".ac3" . "\"";
    } elsif ( $task =~ m/^pcm$/ ) {
        $cmd =
            "if [ ! -f \""
          . $tryf
          . ".$task"
          . "\" ]; then "
          . " /usr/bin/cp -a \""
          . $tryf . ".wav" . "\" \""
          . $tryf
          . ".$task" . "\"" . "; fi "
          . " && /usr/bin/normalize --no-progress -n \""
          . $tryf
          . ".$task"
          . "\"  2>&1 | "
          . "/usr/bin/grep ' has zero power, ignoring...' ; "
          . "if [ \$? -eq 0 ]; "
          . "then echo \"skipping file "
          . $tryf
          . ".$task" . "\"; "
          . "else echo \"normalizing file "
          . $tryf
          . ".$task"
          . "\" && "
          . "/usr/bin/normalize -m \""
          . $tryf
          . ".$task" . "\" ; " . "fi";
    } elsif ( $task =~ m/^mpa$/ ) {
        $cmd =
            " /usr/bin/ffmpeg -y -i \""
          . $tryf . ".pcm"
          . "\" -f ac3 -vn \""
          . $tryf
          . ".$task" . "\"";
    } elsif ( $task =~ m/^mplex\.mpg$/ ) {
        $cmd =
            " /usr/bin/mplex -f 8 -o \""
          . $tryf
          . ".$task\" \""
          . $tryf . ".m2v" . "\" \""
          . $tryf . ".mpa" . "\"";
    } elsif ( $task =~ m/^dvda$/ ) {
        $cmd =
            "if [ -d \""
          . $tryf . "."
          . $task
          . "\" ]; then /usr/bin/rm -r "
          . $tryf . "."
          . $task
          . "; fi && /usr/bin/mkdir "
          . $tryf . "."
          . $task . " && "
          . "/usr/bin/dvdauthor -x \""
          . $tryf
          . "\" -o "
          . $tryf . "."
          . $task;
    } elsif ( $task =~ m/^iso$/ ) {
        $cmd =
            "if [ -f \""
          . $tryf . "."
          . $task
          . "\" ]; then /usr/bin/rm "
          . $tryf . "."
          . $task
          . "; fi && "
          . "/usr/bin/find "
          . $tryf
          . " -exec /usr/bin/touch"
          . " -a -m -r \""
          . $optdownload
          . "\" {} \\\; && "
          . "/usr/bin/genisoimage -quiet -dvd-video -o "
          . $tryf . "."
          . $task . " "
          . $tryf;
    } else {
        die "Task \"$task\" is unkown!";
    }

    runcmd($cmd);

    check( $tryname, $chkname, $filename . ".$task" );
} ## end sub convert

# Normalize PCM files in a directory
sub normalize {
    my ($title) = @_;
    if ( $DBG > 1 ) {
        print "Normalizing $title audio...";
    }
    my @gallerydirs =
      File::Find::Rule->directory->name($title)->in($optdownload);
    foreach my $gallerydir (@gallerydirs) {
        if ( $DBG > 2 ) { print "Found directory $gallerydir\n"; }
        my $try = 0;
        my $chk = 1;
        while ( $try lt $optattempts ) {
            my @tryfiles = ();
            my @trydirs =
              File::Find::Rule->directory->name($try)->in($gallerydir);
            foreach my $trydir (@trydirs) {
                if ( $DBG > 2 ) { print "Found sub-directory $trydir\n"; }
                my @pcmfiles =
                  File::Find::Rule->file->name("*.pcm")->in($trydir);
                foreach my $pcmfile (@pcmfiles) {

                    if ( $DBG > 2 ) { print "Found PCM file $pcmfile\n"; }
                    push( @tryfiles, $pcmfile );
                }
            } ## end foreach my $trydir (@trydirs)
            my $cmd = "/usr/bin/normalize -m ";
            foreach (@tryfiles) {
                $cmd = $cmd . " \"" . $_ . "\"";
            }

            if ( $DBG > 2 ) {
                print "Running command: $cmd\n";
            }
            runcmd($cmd);
            $try++;
            $chk++;
            if ( $chk eq $optattempts ) {
                $chk = 0;
            }
        } ## end while ( $try lt $optattempts)
    } ## end foreach my $gallerydir (@gallerydirs)
    if ( $DBG > 1 ) {
        print "done normalizing $title audio.";
    }
} ## end sub normalize

# Generate DVD from files in a directory
sub dvdgen {
    my ($title) = @_;
    if ( $DBG > 1 ) {
        print "Generating DVD $title...";
    }
    my @gallerydirs =
      File::Find::Rule->directory->name($title)->in($optdownload);
    foreach my $gallerydir (@gallerydirs) {
        if ( $DBG > 2 ) { print "Found directory $gallerydir\n"; }
        my $dvddir = $gallerydir . "/dvd";
        my $try    = 0;
        my $chk    = 1;
        while ( $try lt $optattempts ) {
            my $tryname = $dvddir . "/" . $try;
            my $chkname = $dvddir . "/" . $chk;
            unless ( -d "$tryname" ) {
                unless ( mkpath($tryname) ) {
                    die "$cn create content directory $tryname: $!\n";
                }
            }
            my $manifest = $tryname . "/manifest.txt";
            unless ( open( MANIFEST, ">$manifest" ) ) {
                die "Cannot open manifest file $manifest for writing: $!\n";
            }

            my @contentlist;
            $vidcounter = 0;    # Counter for videos
            foreach my $url ( $urlnodes->get_nodelist ) {
                $vidcounter++;
                if ( $DBG > 1 ) {
                    print "\rLoading...$vidcounter/$totalvideos ";
                }
                if ( $DBG > 0 ) {
                    print ".";
                }
                my $locnode = $url->find('loc');
                my $lnsv    = $locnode->string_value;
                my ( $scheme, $auth, $path, $query, $frag ) =
                  uri_split($locnode);
                my $dirname = $optdownload . $path;
                my $tryname = $dirname . "/" . $try;
                my $chkname = $dirname . "/" . $chk;

                my $vidnodes = $url->find('video:video');
                foreach my $video ( $vidnodes->get_nodelist ) {
                    my $video_content_loc = $video->find('video:content_loc');
                    my $video_gallery_loc = $video->find('video:gallery_loc');
                    my $vcl               = $video_content_loc->string_value;
                    my $vgl               = $video_gallery_loc->string_value;
                    my $vgpath            = $vgl;
                    my @revvgpath         = reverse( split( /\//, $vgpath ) );
                    if ( $revvgpath[0] =~ m/^$optgallery$/i ) {
                        my $contentfile = sprintf(
                            "%s/%s.mplex.mpg\n", $tryname,
                            basename($vcl)
                        );
                        push( @contentlist, $contentfile );
                    } ## end if ( $revvgpath[0] =~ ...)
                } ## end foreach my $video ( $vidnodes...)
            } ## end foreach my $url ( $urlnodes...)

            foreach my $contentfile ( reverse(@contentlist) ) {
                print MANIFEST $contentfile;
            }

            close(MANIFEST);

            my $dvdaxml = $tryname . "/dvdauthor.xml";
            unless ( open( DVDAXML, ">$dvdaxml" ) ) {
                die "Cannot open DVD authoring tool "
                  . "XML file $dvdaxml for writing: $!\n";
            }

            my $jt = 1;
            my $nt = 0;
            my $g2 = 0;

            unless ( open( MANIFEST, "$manifest" ) ) {
                die "Cannot open manifest file $manifest for reading: $!\n";
            }
            while (<MANIFEST>) {
                $nt++;
            }
            close(MANIFEST);

            print DVDAXML "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n";
            print DVDAXML "<dvdauthor>\n";
            print DVDAXML "  <vmgm>\n";
            print DVDAXML "    <!--First Play-->\n";
            print DVDAXML "    <fpc>jump menu entry title;</fpc>\n";
            print DVDAXML "    <menus>\n";
            print DVDAXML "      <video format=\"ntsc\" aspect=\"4:3\"";
            print DVDAXML " resolution=\"720xfull\" />\n";
            print DVDAXML "      <subpicture lang=\"EN\" />\n";
            print DVDAXML "      <pgc entry=\"title\">\n";
            print DVDAXML "        <pre>\n";
            print DVDAXML "g2 = $g2; jump title 1;\n";
            print DVDAXML "</pre>\n";
            print DVDAXML "      </pgc>\n";
            print DVDAXML "    </menus>\n";
            print DVDAXML "  </vmgm>\n";
            print DVDAXML "  <titleset>\n";
            print DVDAXML "    <menus>\n";
            print DVDAXML "      <video format=\"ntsc\" aspect=\"16:9\"";
            print DVDAXML " widescreen=\"nopanscan\" />\n";
            print DVDAXML "      <subpicture>\n";
            print DVDAXML "        <stream id=\"0\" mode=\"widescreen\" />\n";
            print DVDAXML "        <stream id=\"1\" mode=\"letterbox\" />\n";
            print DVDAXML "      </subpicture>\n";
            print DVDAXML "    </menus>\n";
            print DVDAXML "    <titles>\n";
            print DVDAXML "      <video format=\"ntsc\" aspect=\"16:9\"";
            print DVDAXML " widescreen=\"nopanscan\" />\n";

            unless ( open( MANIFEST, "$manifest" ) ) {
                die "Cannot open manifest file $manifest for reading: $!\n";
            }
            while (<MANIFEST>) {
                my $mpg = $_;
                chomp $mpg;
                $jt++;
                if ( $jt > $nt ) {
                    $jt = 1;
                    $g2 = 0;
                } else {
                    $g2 = 1;
                }

                print DVDAXML "      <pgc>\n";
                print DVDAXML "        <vob file=\"$mpg\" pause=\"2\" />\n";
                if ( $g2 == 1 ) {
                    print DVDAXML "        <post>if(g2 == $g2) {jump title";
                    print DVDAXML " $jt;} jump title $jt;</post>\n";
                } else {
                    print DVDAXML
                      "        <post>g2 = $g2; jump title 1;</post>\n";
                }
                print DVDAXML "      </pgc>\n";
            } ## end while (<MANIFEST>)
            close(MANIFEST);

            print DVDAXML "    </titles>\n";
            print DVDAXML "  </titleset>\n";
            print DVDAXML "</dvdauthor>\n";

            close(DVDAXML);

            convert(
                $tryname,        $chkname,
                "dvdauthor.xml", "dvda"
            );
            convert(
                $tryname,             $chkname,
                "dvdauthor.xml.dvda", "iso"
            );

            $try++;
            $chk++;
            if ( $chk eq $optattempts ) {
                $chk = 0;
            }
        } ## end while ( $try lt $optattempts)
    } ## end foreach my $gallerydir (@gallerydirs)
    if ( $DBG > 1 ) {
        print "done generating DVD $title.";
    }
} ## end sub dvdgen

# Check for differences in files, if none, make hard links
sub check {
    my ( $tryname, $chkname, $filename ) = @_;
    my $tryf = "$tryname/$filename";
    my $chkf = "$chkname/$filename";
    my $tfcf = "$tryf and $chkf";
    if ( !-f "$tryf" && !-d "$tryf" ) {
        die "$cn find file or directory $tryf: $!\n";
    }

    if ( -f "$tryf" ) {
        my @stattry = stat("$tryf");
        if ( $stattry[3] != $optattempts ) {
            if ( !-f "$chkf" ) {
                if ( $DBG > 0 ) {
                    warn "$cn find file $chkf: $!\n";
                }
            } else {
                my @statchk = stat("$chkf");
                if ( $statchk[3] != $optattempts ) {
                    my $ft             = File::LibMagic->new();
                    my $type_from_file = $ft->describe_filename("$tryf");

                    my $ct = "application\/xml";
                    if ( $tryf =~ m/\.ac3$/ ) {
                        $ct = "ATSC A\/52 aka AC-3 aka Dolby Digital stream";
                    } elsif ( $tryf =~ m/\.iso$/ ) {
                        $ct = "UDF filesystem data";
                    } elsif ( $tryf =~ m/\.jpg$/ ) {
                        $ct = "JPEG image data";
                    } elsif ( $tryf =~ m/\.m2v$/ ) {
                        $ct = "MPEG sequence, v2, MP\@ML progressive";
                    } elsif ( $tryf =~ m/\.mp4$/ ) {
                        $ct = "ISO Media, MPEG v4 system, ";
                    } elsif ( $tryf =~ m/\.mpa$/ ) {
                        $ct = "ATSC A\/52 aka AC-3 aka Dolby Digital stream";
                    } elsif ( $tryf =~ m/\.mpg$/ ) {
                        $ct = "MPEG sequence, v2, program multiplex";
                    } elsif ( $tryf =~ m/\.pcm$/ ) {
                        $ct = "RIFF \\(little-endian\\) data, WAVE audio";
                    } elsif ( $tryf =~ m/\.txt$/ ) {
                        $ct = " text";
                    } elsif ( $tryf =~ m/\.wav$/ ) {
                        $ct = "RIFF \\(little-endian\\) data, WAVE audio";
                    } else {
                        die "$cn guess file-type based on $tryf\n";
                    }

                    unless (
                        $type_from_file =~ m/$ct/
                        || (   $tryf =~ m/\.txt$/
                            && $type_from_file =~
                            m/very short file \(no magic\)/ )
                      )
                    {
                        die
                          "File type of $tryf expected to be \"$ct\", but was "
                          . "found to be \"$type_from_file\"!";
                    } ## end unless ( $type_from_file =~...)

                    if ( $tryf =~ m/\.iso$/ && $type_from_file =~ m/$ct/ ) {
                        my $tryd = "$tryname/mnt";
                        my $chkd = "$chkname/mnt";
                        unless ( -d "$tryd" ) {
                            unless ( mkpath($tryd) ) {
                                die "$cn create mount directory $tryd: $!\n";
                                runcmd( "/usr/bin/mountpoint $tryd > /dev/null "
                                      . "; if [ \$? -eq 0 ]; then "
                                      . "/usr/bin/fusermount -z -u $tryd; fi" );
                            } else {
                            }
                        } ## end unless ( -d "$tryd" )
                        unless ( -d "$chkd" ) {
                            unless ( mkpath($chkd) ) {
                                die "$cn create mount directory $chkd: $!\n";
                            } else {
                                runcmd( "/usr/bin/mountpoint $chkd > /dev/null "
                                      . "; if [ \$? -eq 0 ]; then "
                                      . "/usr/bin/fusermount -z -u $chkd; fi" );
                            }
                        } ## end unless ( -d "$chkd" )
                        runcmd("/usr/bin/fuseiso $tryf $tryd");
                        runcmd("/usr/bin/fuseiso $chkf $chkd");
                        check( $tryname, $chkname, "mnt" );
                        runcmd("/usr/bin/fusermount -u $tryd");
                        runcmd("/usr/bin/fusermount -u $chkd");
                        if ( -d "$tryd" ) {
                            unless ( rmdir($tryd) ) {
                                die "$cn remove mount directory $tryd: $!\n";
                            }
                        }
                        if ( -d "$chkd" ) {
                            unless ( rmdir($chkd) ) {
                                die "$cn remove mount directory $chkd: $!\n";
                            }
                        }
                    } else {
                        unless ( compare( "$tryf", "$chkf" ) ) {
                            if ( $DBG > 0 ) {
                                print "=";
                                if ( $DBG > 1 ) {
                                    print "Files $tfcf match.\n";
                                }
                            } ## end if ( $DBG > 0 )
                            unless ( unlink("$chkf") ) {
                                die "$cn remove $chkf: $!\n";
                            }
                            unless ( link( "$tryf", "$chkf" ) ) {
                                die "$cn link $tryf to $chkf: $!\n";
                            }
                        } else {
                            if ( $DBG > 0 ) {
                                warn "Files $tfcf do NOT match.\n";
                            }
                            unless ( unlink("$tryf") ) {
                                die "$cn remove $tryf: $!\n";
                            }
                            unless ( unlink("$chkf") ) {
                                die "$cn remove $chkf: $!\n";
                            }
                        } ## end else
                    } ## end else [ if ( $tryf =~ m/\.iso$/...)]
                } else {
                    if ( $DBG > 0 ) {
                        print "=";
                        if ( $DBG > 2 ) {
                            print "Files $tfcf have all symbolic links.\n";
                        }
                    } ## end if ( $DBG > 0 )
                } ## end else [ if ( $statchk[3] != $optattempts)]
            } ## end else [ if ( !-f "$chkf" ) ]
        } else {
            if ( $DBG > 0 ) {
                print "=";
                if ( $DBG > 2 ) {
                    print "File $tryf has all symbolic links.\n";
                }
            } ## end if ( $DBG > 0 )
        } ## end else [ if ( $stattry[3] != $optattempts)]
    } elsif ( -d "$tryf" ) {
        if ( !-d "$chkf" ) {
            if ( $DBG > 0 ) {
                warn "$cn find directory $chkf: $!\n";
            }
        } else {
            if ( runcmd("/usr/bin/diff -r \"$tryf\" \"$chkf\"") ) {
                runcmd(
                    "if [ -d \"$tryf\" ]; then /usr/bin/rm -r \"$tryf\"; fi");
                runcmd(
                    "if [ -d \"$chkf\" ]; then /usr/bin/rm -r \"$chkf\"; fi");
                die("$tryf and $chkf directories do not match!");
            } else {
                if ( $DBG > 1 ) {
                    warn("$tryf and $chkf directories match.");
                }
            }
        } ## end else [ if ( !-d "$chkf" ) ]
    } else {
        die "Cannot determine what $tryf is: $!\n";
    }
} ## end sub check

sub runcmd {
    my ($cmd) = @_;

    if ( $DBG > 2 ) {
        print "Running command: $cmd\n";
    }

    my ( $wtr, $rdr, $err );
    use Symbol 'gensym';
    $err = gensym;

    my $pid = open3( $wtr, $rdr, $err, $cmd );
    my $select = new IO::Select;
    $select->add( $rdr, $err );

    while ( my @ready = $select->can_read ) {
        foreach my $fh (@ready) {
            my $data;
            my $length = sysread $fh, $data, 4096;

            if ( !defined $length || $length == 0 ) {
                $select->remove($fh);
            } else {
                if ( $fh == $rdr ) {
                    if ( $DBG > 2 ) {
                        print "$data\n";
                    }
                } elsif ( $fh == $err ) {
                    if ( $DBG > 1 ) {
                        print "$data\n";
                    }
                } else {
                    return undef;
                }
            } ## end else [ if ( !defined $length ...)]
        } ## end foreach my $fh (@ready)
    } ## end while ( my @ready = $select...)

    waitpid( $pid, 0 );
    my $child_exit_status = $? >> 8;
    if ($child_exit_status) {
        die "Command \"$cmd\" exited with code $child_exit_status: $!";
    }
    return 0;
} ## end sub runcmd

if ( $DBG > 0 ) {
    print "done.\n";
}
