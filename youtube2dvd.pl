#! /usr/bin/perl -wT

use diagnostics;
use strict;
use warnings;
use Data::Dumper;
use Digest::MD5 qw[md5_hex];
use File::Temp;
use File::Which;
use Getopt::Long;
use IPC::Cmd qw[can_run];
use IPC::Run3;
use JSON::Path;
use Log::Log4perl;
use Regexp::Common qw[URI];

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

$ENV{PATH} = "/usr/bin";
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

my %logconf = (
    "log4perl.category" => "$LEVEL, SCREEN",
    "log4perl.appender.SCREEN" =>
      "Log::Log4perl::Appender::ScreenColoredLevels",
    "log4perl.appender.SCREEN.layout" => "SimpleLayout",
    "log4perl.appender.SCREEN.stderr" => 1
);

Log::Log4perl::init( \%logconf );
my $logger = Log::Log4perl->get_logger('SCREEN');

unless ($opturl) {
    $logger->error_die("URL not provided: $!");
}

sub validurl {
    my ($url) = @_;

    my $regexp = qr($RE{URI}{HTTP}{-scheme=>qr/https?/}{-keep});

    if ( $url =~ $regexp ) {
        $url = $1;
        return $url;
    }

    return 0;
} ## end sub validurl

if ( validurl($opturl) ) {
    $opturl =~ /\A(.*)\z/s
      or $logger->error_die( $opturl . " is tainted: $!" ); $opturl = $1;
} else {
    $logger->error_die("URL is not valid: $!");
}

my @extcmds = (
    "youtube-dl", "ffprobe", "grep", "ffmpeg", "mplayer", "cp", "normalize",
    "mplex", "rm", "mkdir", "dvdauthor", "find", "touch", "genisoimage"
);
my %paths;
foreach my $extcmd (@extcmds) {
    getcmd($extcmd);
}

sub getcmd {
    my ($extcmd) = @_;
    $paths{$extcmd} = which($extcmd);
    unless ( $paths{$extcmd} ) {
        $logger->error_die( $extcmd . " is not installed: $!" );
    }
    my $full_path = can_run( $paths{$extcmd} )
      or $logger->error_die( $paths{$extcmd} . " cannot be run: $!" );
    $logger->debug( $extcmd . " found at " . $full_path );
    return $full_path;
} ## end sub getcmd

my $tempdir = File::Temp->newdir( DIR => "." );
$tempdir->unlink_on_destroy(0);
my $tempdirname = $tempdir->dirname;

$logger->debug( "Temporary directory: " . $tempdirname );

sub runcmd {
    my (@cmd) = @_;
    my ( $in, $out, $err );
    $logger->trace( "Running command: " . Dumper(@cmd) );
    my $result = run3( @cmd, \$in, \$out, \$err );
    if ($out) {
        $logger->info($out);
    }
    if ($err) {
        $logger->error($err);
    }
    if ( $result != 1 ) {
        $logger->error_warn( "Return code: " . $result );
    }
} ## end sub runcmd

my $ytdlcmd =
    getcmd("youtube-dl")
  . " -f webm/mp4 --prefer-free-formats --write-description --write-info-json --write-annotations --write-thumbnail --write-all-thumbnails -o \'"
  . $tempdirname
  . "/\%(playlist_index)s - \%(title)s.\%(ext)s\' \""
  . $opturl . "\"";
runcmd($ytdlcmd);

my @jsonfiles;
unless ( opendir( TEMPDIR, $tempdirname ) ) {
    $logger->error_die("Cannot open $tempdirname: $!");
}
while ( readdir(TEMPDIR) ) {
    $logger->trace("$tempdirname/$_");
    if ( $_ =~ m/\.info\.json$/ ) {
        push( @jsonfiles, $_ );
    }
} ## end while ( readdir(TEMPDIR) )
closedir(TEMPDIR);

my $manifest = $tempdirname . "/manifest.txt";
unless ( open( MANIFEST, ">$manifest" ) ) {
    die "Cannot open manifest file $manifest for writing: $!\n";
}

foreach ( sort(@jsonfiles) ) {
    my $basename = "$tempdirname/$_";
    $basename =~ s/\.info\.json$//g;
    $basename =~ /\A(.*)\z/s
      or $logger->error_die( $basename . " is tainted: $!" ); $basename = $1;
    my $newfilename = $tempdirname . "/" . md5_hex($basename);
    my $jsonname    = $basename . ".info.json";
    $logger->trace($jsonname);
    unless ( open( JSONFILE, $jsonname ) ) {
        $logger->error_die("Cannot open $jsonname: $!");
    }
    my $data = <JSONFILE>;
    close(JSONFILE);
    $logger->trace( Dumper $data );
    my $jpath;
    $jpath = JSON::Path->new('$._filename');
    my $_filename = $jpath->value($data);
    runcmd( "/usr/bin/cp -a \"" . $_filename . "\" \"" . $newfilename . "\"" );
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

my $dvdaxml  = $tempdirname . "/dvdauthor.xml";
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

sub convert {
    my ( $basename, $task ) = @_;
    my $cmd;

    if ( -f $basename . ".$task" || -d $basename . ".$task" ) {
        $logger->debug(
            "File or directory" . $basename . ".$task already exists." );
        return 0;
    }

    if ( $task =~ m/^mpg$/ ) {
        my $nullaudio = "";
        $cmd =
            "/usr/bin/ffprobe -v info -select_streams a \""
          . $basename
          . "\" 2>&1 | /usr/bin/grep '^    Stream #' |"
          . " /usr/bin/grep ': Audio: ' > /dev/null";
        $logger->error_warn(
            "Checking for audio stream in $basename with: \"$cmd\"");
        my $rc = system($cmd);
        if ($rc) {
            warn(   "$basename does not have an audio track,"
                  . " setting it to have one..." );
            $nullaudio = " -f lavfi -i aevalsrc=0 -shortest"
              . " -c:v copy -c:a aac -strict experimental ";
        } ## end if ($rc)
        $cmd =
            " /usr/bin/ffmpeg -y -i \""
          . $basename . "\" "
          . $nullaudio
          . " -target ntsc-dvd -q:a 0 -q:v 0 \""
          . $basename
          . ".$task" . "\"";
    } elsif ( $task =~ m/^ac3$/ ) {
        $cmd =
            " /usr/bin/ffmpeg -y -i \""
          . $basename . ".mpg"
          . "\" -acodec copy -vn \""
          . $basename
          . ".$task" . "\"";
    } elsif ( $task =~ m/^m2v$/ ) {
        $cmd =
            " /usr/bin/ffmpeg -y -i \""
          . $basename . ".mpg"
          . "\" -vcodec copy -an \""
          . $basename
          . ".$task" . "\"";
    } elsif ( $task =~ m/^wav$/ ) {
        $cmd =
            " /usr/bin/mplayer -noautosub -nolirc -benchmark "
          . "-vc null -vo null "
          . "-ao pcm:waveheader:fast:file=\""
          . $basename
          . ".$task" . "\" \""
          . $basename . ".ac3" . "\"";
    } elsif ( $task =~ m/^pcm$/ ) {
        $cmd =
            "if [ ! -f \""
          . $basename
          . ".$task"
          . "\" ]; then "
          . " /usr/bin/cp -a \""
          . $basename . ".wav" . "\" \""
          . $basename
          . ".$task" . "\"" . "; fi "
          . " && /usr/bin/normalize --no-progress -n \""
          . $basename
          . ".$task"
          . "\"  2>&1 | "
          . "/usr/bin/grep ' has zero power, ignoring...' ; "
          . "if [ \$? -eq 0 ]; "
          . "then echo \"skipping file "
          . $basename
          . ".$task" . "\"; "
          . "else echo \"normalizing file "
          . $basename
          . ".$task"
          . "\" && "
          . "/usr/bin/normalize -m \""
          . $basename
          . ".$task" . "\" ; " . "fi";
    } elsif ( $task =~ m/^mpa$/ ) {
        $cmd =
            " /usr/bin/ffmpeg -y -i \""
          . $basename . ".pcm"
          . "\" -f ac3 -vn \""
          . $basename
          . ".$task" . "\"";
    } elsif ( $task =~ m/^mplex\.mpg$/ ) {
        $cmd =
            " /usr/bin/mplex -f 8 -o \""
          . $basename
          . ".$task\" \""
          . $basename . ".m2v" . "\" \""
          . $basename . ".mpa" . "\"";
    } elsif ( $task =~ m/^dvda$/ ) {
        $cmd =
            "if [ -d \""
          . $basename . "."
          . $task
          . "\" ]; then /usr/bin/rm -r "
          . $basename . "."
          . $task
          . "; fi && /usr/bin/mkdir "
          . $basename . "."
          . $task . " && "
          . "/usr/bin/dvdauthor -x \""
          . $basename
          . "\" -o "
          . $basename . "."
          . $task;
    } elsif ( $task =~ m/^iso$/ ) {
        $cmd =
            "if [ -f \""
          . $basename . "."
          . $task
          . "\" ]; then /usr/bin/rm "
          . $basename . "."
          . $task
          . "; fi && "
          . "/usr/bin/find "
          . $basename
          . " -exec /usr/bin/touch"
          . " -a -m -r \""
          . $tempdirname
          . "\" {} \\\; && "
          . "/usr/bin/genisoimage -quiet -dvd-video -o "
          . $basename . "."
          . $task . " "
          . $basename;
    } else {
        die "Task \"$task\" is unkown!";
    }

    runcmd($cmd);

} ## end sub convert

