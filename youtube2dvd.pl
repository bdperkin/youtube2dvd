#! /usr/bin/perl -wT
#
# youtube2dvd.pl - youtube.com video downloader and DVD authoring tool.
# Copyright (C) 2018-2018  Brandon Perkins <bperkins@redhat.com>
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
use diagnostics;                 # Produce verbose warning diagnostics
use strict;                      # Pragma to restrict unsafe constructs
use warnings;                    # Pragma to give control over warnings
use Data::Dumper qw[Dumper];     # Stringified perl data structures
use Digest::MD5 qw[md5_hex];     # Interface to the MD5 Algorithm
use File::Temp qw[tempdir];      # Return name of a temporary file safely
use File::Which qw[which];       # Implementation of the which utility as an API
use Getopt::Long qw[GetOptions]; # Extended processing of command line options
use IPC::Cmd qw[can_run];        # Finding and running system commands made easy
use IPC::Run3 qw[run3];          # Run a subprocess with input/ouput redirection
use JSON::Path qw[jpath1];       # Search nested ref structures using JSONPath
use Log::Log4perl;               # Log4j implementation for Perl
use Regexp::Common qw[URI];      # Commonly requested regular expressions

################################################################################
# Declare constants
################################################################################
binmode STDOUT, ":utf8";    # Out/Err/Input UTF-8 using the :utf8
binmode STDERR, ":utf8";    # out/err/input layer.  This ensures that the
binmode STDIN,  ":utf8";    # out/err/input is completelyUTF-8, and removes any
                            # debug warnings.
$ENV{PATH} = "/usr/bin";

################################################################################
# Specify module configuration options to be enabled
################################################################################
# Allow single-character options to be bundled. To distinguish bundles from long
# option names, long options must be introduced with '--' and bundles with '-'.
# Do not allow '+' to start options.
Getopt::Long::Configure(qw(bundling no_getopt_compat));

################################################################################
# Parse command line options.  This function adheres to the POSIX syntax for CLI
# options, with GNU extensions.
################################################################################
# Initialize GetOptions variables
my ( $optdebug, $optquiet, $opturl, $optverbose );

GetOptions(
    "d"       => \$optdebug,
    "debug"   => \$optdebug,
    "q"       => \$optquiet,
    "quiet"   => \$optquiet,
    "u=s"     => \$opturl,
    "v"       => \$optverbose,
    "verbose" => \$optverbose,
);

################################################################################
# Set output level
################################################################################
# If multiple outputs are specified, the most verbose will be used.
$| = 0;
my $LEVEL = "INFO";

if ($optquiet) {
    $|     = 0;
    $LEVEL = "WARN";
}
if ($optverbose) {
    $|     = 1;
    $LEVEL = "DEBUG";
}
if ($optdebug) {
    $|     = 1;
    $LEVEL = "TRACE";
}

################################################################################
# Configure and initialize logging
################################################################################
my %logconf = (
    "log4perl.category" => "$LEVEL, SCREEN",
    "log4perl.appender.SCREEN" =>
      "Log::Log4perl::Appender::ScreenColoredLevels",
    "log4perl.appender.SCREEN.layout" => "SimpleLayout",
    "log4perl.appender.SCREEN.stderr" => 1
);

Log::Log4perl::init( \%logconf );
my $logger = Log::Log4perl->get_logger('SCREEN');
$logger->debug( "Logger initialized at " . $LEVEL . " level" );

################################################################################
# Convert files from one format to another
################################################################################
sub convert {
    my ( $basename, $task ) = @_;
    my $tempdir = $main::tempdir;
    my $cmd;

    if ( -f $basename . "." . $task || -d $basename . "." . $task ) {
        $logger->debug(
            "File or directory" . $basename . "." . $task . " already exists" );
        return 0;
    }

    if ( $task =~ m/^mpg$/ ) {
        my $nullaudio = "";
        $cmd =
            getcmd("ffprobe")
          . " -v info -select_streams a \""
          . $basename
          . "\" 2>&1 | "
          . getcmd("grep")
          . " '^    Stream #' | "
          . getcmd("grep")
          . " ': Audio: ' > /dev/null";
        $logger->trace("Checking for audio stream in $basename with: \"$cmd\"");
        my $rc = system($cmd);
        if ($rc) {
            $logger->error_warn( "$basename does not have an audio track,"
                  . " setting it to have one..." );
            $nullaudio = " -f lavfi -i aevalsrc=0 -shortest"
              . " -c:v copy -c:a aac -strict experimental ";
        } ## end if ($rc)
        $cmd =
            getcmd("ffmpeg")
          . " -y -i \""
          . $basename . "\" "
          . $nullaudio
          . "-target ntsc-dvd -q:a 0 -q:v 0 \""
          . $basename . "."
          . $task . "\"";
    } elsif ( $task =~ m/^ac3$/ ) {
        $cmd =
            getcmd("ffmpeg")
          . " -y -i \""
          . $basename . ".mpg"
          . "\" -acodec copy -vn \""
          . $basename . "."
          . $task . "\"";
    } elsif ( $task =~ m/^m2v$/ ) {
        $cmd =
            getcmd("ffmpeg")
          . " -y -i \""
          . $basename . ".mpg"
          . "\" -vcodec copy -an \""
          . $basename . "."
          . $task . "\"";
    } elsif ( $task =~ m/^wav$/ ) {
        $cmd =
            getcmd("mplayer")
          . " -noautosub -nolirc -benchmark "
          . "-vc null -vo null "
          . "-ao pcm:waveheader:fast:file=\""
          . $basename . "."
          . $task . "\" \""
          . $basename
          . ".ac3\"";
    } elsif ( $task =~ m/^pcm$/ ) {
        $cmd =
            "if [ ! -f \""
          . $basename . "."
          . $task
          . "\" ]; then "
          . getcmd("cp")
          . " -a \""
          . $basename
          . ".wav\" \""
          . $basename . "."
          . $task
          . "\"; fi && "
          . getcmd("normalize")
          . " --no-progress -n \""
          . $basename . "."
          . $task
          . "\" 2>&1 | "
          . getcmd("grep")
          . " ' has zero power, ignoring...' ; "
          . "if [ \$? -eq 0 ]; "
          . "then echo \"skipping file "
          . $basename . "."
          . $task . "\"; "
          . "else echo \"normalizing file "
          . $basename . "."
          . $task
          . "\" && "
          . getcmd("normalize")
          . " -m \""
          . $basename . "."
          . $task
          . "\" ; fi";
    } elsif ( $task =~ m/^mpa$/ ) {
        $cmd =
            getcmd("ffmpeg")
          . " -y -i \""
          . $basename . ".pcm"
          . "\" -f ac3 -vn \""
          . $basename . "."
          . $task . "\"";
    } elsif ( $task =~ m/^mplex\.mpg$/ ) {
        $cmd =
            getcmd("mplex")
          . " -f 8 -o \""
          . $basename . "."
          . $task . "\" \""
          . $basename
          . ".m2v\" \""
          . $basename
          . ".mpa\"";
    } elsif ( $task =~ m/^dvda$/ ) {
        $cmd =
            "if [ -d \""
          . $basename . "."
          . $task
          . "\" ]; then "
          . getcmd("rm") . " -r "
          . $basename . "."
          . $task
          . "; fi && "
          . getcmd("mkdir") . " "
          . $basename . "."
          . $task . " && "
          . getcmd("dvdauthor")
          . " -x \""
          . $basename
          . "\" -o "
          . $basename . "."
          . $task;
    } elsif ( $task =~ m/^iso$/ ) {
        $cmd =
            "if [ -f \""
          . $basename . "."
          . $task
          . "\" ]; then "
          . getcmd("rm") . " "
          . $basename . "."
          . $task
          . "; fi && "
          . getcmd("find") . " "
          . $basename
          . " -exec "
          . getcmd("touch")
          . " -a -m -r \""
          . $tempdir
          . "\" {} \\\; && "
          . getcmd("genisoimage")
          . " -quiet -dvd-video -o "
          . $basename . "."
          . $task . " "
          . $basename;
    } else {
        die "Task \"$task\" is unkown!";
    }

    runcmd($cmd);

} ## end sub convert

################################################################################
# Validate external command
################################################################################
sub getcmd {
    my ($extcmd) = @_;

    $logger->trace( "Checking if command \"" . $extcmd . "\" exists" );
    my $extcmdpath = which($extcmd);
    unless ($extcmdpath) {
        $logger->error_die( $extcmd . " is not installed: $!" );
    }

    $logger->trace( "Checking if command \"" . $extcmdpath . "\" can run" );
    my $full_path = can_run($extcmdpath);
    unless ($full_path) {
        $logger->error_die( $extcmdpath . " cannot be run: $!" );
    }

    $logger->trace( "\"" . $extcmd . "\" found at \"" . $full_path . "\"" );
    return $full_path;
} ## end sub getcmd

################################################################################
# Execute external command
################################################################################
sub runcmd {
    my (@cmd) = @_;
    my ( $in, $out, $err );

    $logger->info( "Running command: " . $cmd[0] );
    run3( @cmd, \$in, \$out, \$err );
    my $result = $?;
    if ($out) {
        $logger->trace( "STDOUT:\n" . $out );
    }
    if ($err) {
        $logger->debug( "STDERR:\n" . $err );
    }
    if ($result) {
        $logger->warn($out);
        $logger->error($err);
        $logger->error_die( "Return code: " . $result );
    }
    if ($out) {
        $logger->trace( "Returning utput from command:\n" . $out );
        return $out;
    } else {
        $logger->trace("Returning empty output from command");
        return "";
    }
} ## end sub runcmd

################################################################################
# Validate URL
################################################################################
sub validurl {
    my ($url) = @_;
    my $regexp = qr($RE{URI}{HTTP}{-scheme=>qr/https?/}{-keep});

    $logger->trace( "Validating URL \"" . $url . "\"" );
    if ( $url =~ $regexp ) {
        $url = $1;
        $logger->trace( "URL \"" . $url . "\" is valid" );
        return $url;
    }
    $logger->error( "URL \"" . $url . "\" is not valid" );
    return 0;
} ## end sub validurl

################################################################################
# Main function
################################################################################
unless ($opturl) {
    $logger->error_die("URL not provided: $!");
}

if ( validurl($opturl) ) {
    if ( $opturl =~ /\A(.*)\z/s ) {
        $opturl = $1;
        $logger->trace( "URL \"" . $opturl . "\" is not tainted" );
    } else {
        $logger->error_die( "URL \"" . $opturl . "\" is tainted: $!" );
    }
    if ( $opturl =~ m/^http(s)?:\/\/(www\.)?youtube\.com\// ) {
        $logger->debug( "Using URL \"" . $opturl . "\"" );
    } else {
        $logger->error_die(
            "\"" . $opturl . "\" is not a valid youtube URL: $!" );
    }
} ## end if ( validurl($opturl))

$logger->trace("Creating temporary directory");
our $tempdir = tempdir( DIR => "." );

$logger->debug( "Created temporary directory \"" . $tempdir . "\"" );

my $ytdlcmd =
    getcmd("youtube-dl")
  . " -f webm/mp4 --prefer-free-formats "
  . "--write-description --write-info-json --write-annotations "
  . "--write-thumbnail --write-all-thumbnails";
if ($optquiet) {
    $ytdlcmd = $ytdlcmd . " --quiet";
}
if ( $optverbose || $optdebug ) {
    $ytdlcmd = $ytdlcmd . " --verbose";
}
$ytdlcmd =
    $ytdlcmd
  . " -o \'"
  . $tempdir
  . "/\%(playlist_index)s - \%(title)s.\%(ext)s\' \""
  . $opturl . "\"";
runcmd($ytdlcmd);

my @jsonfiles;
unless ( opendir( TEMPDIR, $tempdir ) ) {
    $logger->error_die("Cannot open $tempdir: $!");
}
while ( readdir(TEMPDIR) ) {
    $logger->trace("$tempdir/$_");
    if ( $_ =~ m/\.info\.json$/ ) {
        push( @jsonfiles, $_ );
    }
} ## end while ( readdir(TEMPDIR) )
closedir(TEMPDIR);

my $manifest = $tempdir . "/manifest.txt";
unless ( open( MANIFEST, ">$manifest" ) ) {
    die "Cannot open manifest file $manifest for writing: $!\n";
}

foreach ( sort(@jsonfiles) ) {
    my $basename = "$tempdir/$_";
    $basename =~ s/\.info\.json$//g;
    $basename =~ /\A(.*)\z/s
      or $logger->error_die( $basename . " is tainted: $!" ); $basename = $1;
    my $newfilename = $tempdir . "/" . md5_hex($basename);
    my $jsonname    = $basename . ".info.json";
    $logger->trace($jsonname);
    unless ( open( JSONFILE, $jsonname ) ) {
        $logger->error_die("Cannot open $jsonname: $!");
    }
    my $data = <JSONFILE>;
    close(JSONFILE);
    $logger->trace( Dumper $data );
    my $_filename = jpath1( $data, '$._filename' );
    $logger->trace( Dumper $_filename );
    runcmd(
        getcmd("cp") . " -a \"" . $_filename . "\" \"" . $newfilename . "\"" );
    $logger->trace( Dumper $newfilename );
    my $jpgfile = $basename . ".jpg";
    $logger->trace( Dumper $jpgfile );
    convert( $newfilename, "mpg" );
    convert( $newfilename, "ac3" );
    convert( $newfilename, "m2v" );
    convert( $newfilename, "wav" );
    convert( $newfilename, "pcm" );
    convert( $newfilename, "mpa" );
    convert( $newfilename, "mplex.mpg" );
    print MANIFEST $newfilename . ".mplex.mpg\n";
} ## end foreach ( sort(@jsonfiles) )

close(MANIFEST);

my $dvdaxml  = $tempdir . "/dvdauthor.xml";
my $dvdaxmld = $dvdaxml . ".dvda";

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
        print DVDAXML "        <post>g2 = $g2; jump title 1;</post>\n";
    }
    print DVDAXML "      </pgc>\n";
} ## end while (<MANIFEST>)
close(MANIFEST);

print DVDAXML "    </titles>\n";
print DVDAXML "  </titleset>\n";
print DVDAXML "</dvdauthor>\n";

close(DVDAXML);

convert( $dvdaxml,  "dvda" );
convert( $dvdaxmld, "iso" );

print "ISO: " . $dvdaxmld . ".iso\n";

1;
