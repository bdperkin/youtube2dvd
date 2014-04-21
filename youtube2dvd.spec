Name:		youtube2dvd
Version:	0.0.2
Release:	1%{?dist}
Summary:	YouTube video downloader and DVD authoring tool

Group:		Applications/Internet
License:	GPLv2
URL:		https://github.com/bdperkin/%{name}
Source0:	https://github.com/bdperkin/%{name}/sources/%{name}-%{version}.tar.gz

BuildArch:	noarch
BuildRequires:	asciidoc
BuildRequires:	docbook-style-xsl
BuildRequires:	/usr/bin/groff
BuildRequires:	libxslt
BuildRequires:	pandoc
BuildRequires:	/usr/bin/perltidy
BuildRequires:	/usr/bin/podchecker
BuildRequires:	w3m
Requires:	/usr/bin/cp
Requires:	/usr/bin/diff
Requires:	/usr/bin/dvdauthor
Requires:	/usr/bin/ffmpeg
Requires:	/usr/bin/ffprobe
Requires:	/usr/bin/find
Requires:	/usr/bin/fuseiso
Requires:	/usr/bin/fusermount
Requires:	/usr/bin/genisoimage
Requires:	/usr/bin/grep
Requires:	/usr/bin/mkdir
Requires:	/usr/bin/mountpoint
Requires:	/usr/bin/mplayer
Requires:	/usr/bin/mplex
Requires:	/usr/bin/normalize
Requires:	/usr/bin/perl
Requires:	/usr/bin/perldoc
Requires:	/usr/bin/rm
Requires:	/usr/bin/touch
Requires:	coreutils
Requires:	diffutils
Requires:	dvdauthor
Requires:	ffmpeg
Requires:	findutils
Requires:	fuse
Requires:	fuseiso
Requires:	genisoimage
Requires:	grep
Requires:	mjpegtools
Requires:	mplayer
Requires:	normalize
Requires:	perl
Requires:	perl(File::Compare)
Requires:	perl(File::Find::Rule)
Requires:	perl(File::LibMagic)
Requires:	perl(File::Path)
Requires:	perl(Getopt::Long)
Requires:	perl(IO::Select)
Requires:	perl(IPC::Open3)
Requires:	perl(strict)
Requires:	perl(URI::Split)
Requires:	perl(warnings)
Requires:	perl(WWW::Curl::Easy)
Requires:	perl(XML::XPath)
Requires:	perl-File-Find-Rule
Requires:	perl-File-LibMagic
Requires:	perl-File-Path
Requires:	perl-Getopt-Long
Requires:	perl-Pod-Perldoc
Requires:	perl-URI
Requires:	perl-WWW-Curl
Requires:	perl-XML-XPath
Requires:	rpmfusion-free-release
Requires:	util-linux

%define NameUpper %{expand:%%(echo %{name} | tr [:lower:] [:upper:])}
%define NameMixed %{expand:%%(echo %{name} | %{__sed} -e "s/\\([a-z]\\)\\([a-zA-Z0-9]*\\)/\\u\\1\\2/g")}
%define NameLower %{expand:%%(echo %{name} | tr [:upper:] [:lower:])}
%define Year %{expand:%%(date "+%Y")}
%define DocFiles ACKNOWLEDGEMENTS AUTHOR AUTHORS AVAILABILITY BUGS CAVEATS COPYING COPYRIGHT DESCRIPTION LICENSE NAME NOTES OPTIONS OUTPUT README.md RESOURCES SYNOPSIS
%define SubFiles %{name} %{name}.1.asciidoc %{DocFiles} man.asciidoc
%define DocFormats chunked htmlhelp manpage text xhtml

%description
Perl script to download YouTube videos, convert them, and author a DVD.

%prep
%setup -q

%clean
%{__rm} -rf $RPM_BUILD_ROOT

%build
%{__cp} %{name}.pl %{name}
%{__sed} -i -e s/%{NAME}/%{name}/g %{SubFiles}
%{__sed} -i -e s/%{NAMEUPPER}/%{NameUpper}/g %{SubFiles}
%{__sed} -i -e s/%{NAMEMIXED}/%{NameMixed}/g %{SubFiles}
%{__sed} -i -e s/%{NAMELOWER}/%{NameLower}/g %{SubFiles}
%{__sed} -i -e s/%{VERSION}/%{version}/g %{SubFiles}
%{__sed} -i -e s/%{RELEASE}/%{release}/g %{SubFiles}
%{__sed} -i -e s/%{YEAR}/%{Year}/g %{SubFiles}
for f in %{DocFormats}; do %{__mkdir_p} $f; a2x -D $f -d manpage -f $f %{name}.1.asciidoc; done
groff -e -mandoc -Tascii manpage/%{name}.1 > manpage/%{name}.1.groff
%{__mkdir_p} pod
./groff2pod.pl manpage/%{name}.1.groff pod/%{name}.1.pod
podchecker pod/%{name}.1.pod
cat pod/%{name}.1.pod >> %{name}
perltidy -b %{name}
podchecker %{name}
pandoc -f html -t markdown -s -o README.md.pandoc xhtml/%{name}.1.html
cat README.md.pandoc | %{__grep} -v ^% | %{__sed} -e 's/\*\*/\*/g' | %{__sed} -e 's/^\ \*/\n\ \*/g' | %{__sed} -e 's/\[\*/\[\ \*/g' | %{__sed} -e 's/\*\]/\*\ \]/g' | %{__sed} -e 's/{\*/{\ \*/g' | %{__sed} -e 's/\*}/\*\ }/g' | %{__sed} -e 's/|\*/|\ \*/g' | %{__sed} -e 's/\*|/\*\ |/g' | %{__sed} -e 's/=\*/=\ \*/g' | %{__sed} -e 's/\*=/\*\ =/g' > README.md 

%install
%{__rm} -rf $RPM_BUILD_ROOT
%{__mkdir_p} %{buildroot}%{_bindir}
%{__mkdir_p} %{buildroot}%{_mandir}/man1
%{__install} %{name} %{buildroot}%{_bindir}
%{__gzip} -c manpage/%{name}.1 > %{buildroot}/%{_mandir}/man1/%{name}.1.gz

%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%doc %{DocFiles}
%doc %{DocFormats} pod
%doc %{_mandir}/man1/%{name}.1.gz


%changelog
* Mon Apr 21 2014 Brandon Perkins <bperkins@redhat.com> 0.0.2-1
- new package built with tito

* Mon Apr 21 2014 Brandon Perkins <bperkins@redhat.com> 0.0.4-1
- Generating ISOs. (bperkins@redhat.com)
- DVD Authoring (bperkins@redhat.com)
- Make command paths explicit, and add dependency requirements to the RPM spec.
  (bperkins@redhat.com)

* Tue Apr 15 2014 Brandon Perkins <bperkins@redhat.com> 0.0.3-1
- Normalization of PCM audio. (bperkins@redhat.com)
- add or update closing side comments after closing BLOCK brace
  (bperkins@redhat.com)
- cuddled else; use this style: '} else {' (bperkins@redhat.com)
- add newlines;  ok to introduce new line breaks (bperkins@redhat.com)
- File conversions. (bperkins@redhat.com)
- Much better checking of data (bperkins@redhat.com)
- Add docs. (bperkins@redhat.com)

* Tue Apr 08 2014 Brandon Perkins <bperkins@redhat.com> 0.0.2-1
- new package built with tito

