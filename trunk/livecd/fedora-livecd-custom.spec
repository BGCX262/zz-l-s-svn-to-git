Summary: This package defines the base contents of Fedora live CD's.
Name: fedora-livecd
Version: 6
Release: 2%{?dist}
License: GPL
Group: System Environment/Base
URL: http://fedoraproject.org/wiki/FedoraLiveCD
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root
Source0: 10-fedora-livecd-base.conf
Source1: 20-fedora-livecd-gnome.conf
Source2: 30-fedora-livecd-desktop.conf

# The next source is our custom SPEC file
Source3: 40-fedora-livecd-office-code.conf

# This is the custom wallpaper we'll use in the Live CD
Source9: fedora-livecd-wallpaper.jpg

# Optionally if you need to include other files, specify them here
# Source10: somePDFdocument.pdf

Autoreq: 0

%description
This package defines the contents of Fedora live CD's.

# fedora-livecd-gnome
%package gnome
Summary: This package defines the contents of the base Fedora Desktop live CD.
Group: System Environment/Base
Autoreq: 0
Requires: fedora-livecd

%description gnome 
This package defines the contents of the base Fedora Desktop Live
CD. Can be used as a starting point for desktop oriented live CD's
using GNOME.

# fedora-livecd-desktop
%package desktop
Summary: This package defines the content of the Fedora Desktop live CD.
Group: System Environment/Base
Autoreq: 0
Requires: fedora-livecd-gnome

%description desktop
This package defines the contents of the Fedora Desktop live CD.

# here we define our custom package 
# and also mention that it also requires the gnome
# fedora-livecd-office-code
%package office
Summary: This package defines the content of the Fedora Office live CD.
Group: System Environment/Base
Autoreq: 0
Requires: fedora-livecd-gnome

%description office
This package defines the contents of our custom Fedora Office-Code live CD.

%prep

%build

%install
rm -rf $RPM_BUILD_ROOT

# now we create the custom directories
mkdir -p $RPM_BUILD_ROOT/etc/livecd/
mkdir -p $RPM_BUILD_ROOT/usr/share/backgrounds/images
# mkdir -p $RPM_BUILD_ROOT/home/fedora/ebook/

# then we copy the files specified at the top into respective directories
install -m 755 %{SOURCE0} $RPM_BUILD_ROOT/etc/livecd/
install -m 755 %{SOURCE1} $RPM_BUILD_ROOT/etc/livecd/
install -m 755 %{SOURCE2} $RPM_BUILD_ROOT/etc/livecd/
install -m 755 %{SOURCE3} $RPM_BUILD_ROOT/etc/livecd/
install -m 644 %{SOURCE9} $RPM_BUILD_ROOT/usr/share/backgrounds/images/
#install -m 644 %{SOURCE10} $RPM_BUILD_ROOT/home/fedora/ebook/

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%dir /etc/livecd
/etc/livecd/10-fedora-livecd-base.conf

%files gnome
%defattr(-,root,root,-)
%dir /etc/livecd
/etc/livecd/20-fedora-livecd-gnome.conf
/usr/share/backgrounds/images/fedora-livecd-wallpaper.jpg
#/home/fedora/ebook/200603.pdf

%files desktop
%defattr(-,root,root,-)
%dir /etc/livecd
/etc/livecd/30-fedora-livecd-desktop.conf

%files office
%defattr(-,root,root,-)
%dir /etc/livecd
/etc/livecd/40-fedora-livecd-office-code.conf


%changelog
* Fri Feb 02 2007 Mayank Sharma <geekybodhi@gmail.com> - 6-2%{?dist}
- Added fedora-livecd-office-code
- Replaced wallpaper

* Wed Dec 20 2006 David Zeuthen <davidz@redhat.com> - 6-1%{?dist}
- Initial build
