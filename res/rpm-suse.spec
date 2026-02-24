Name:       RustDesk
Version:    1.1.9
Release:    0
Summary:    RPM package
License:    GPL-3.0
Requires:   gtk3 libxcb1 libXfixes3 alsa-utils libXtst6 libva2 pam gstreamer-plugins-base gstreamer-plugin-pipewire
Recommends: libayatana-appindicator3-1 xdotool

# https://docs.fedoraproject.org/en-US/packaging-guidelines/Scriptlets/

%description
The best open-source remote desktop client software, written in Rust.

%prep
# we have no source, so nothing here

%build
# we have no source, so nothing here

%global __python %{__python3}

%install
mkdir -p %{buildroot}/usr/bin/
mkdir -p %{buildroot}/usr/share/RustDesk/
mkdir -p %{buildroot}/usr/share/RustDesk/files/
mkdir -p %{buildroot}/usr/share/icons/hicolor/256x256/apps/
mkdir -p %{buildroot}/usr/share/icons/hicolor/scalable/apps/
install -m 755 $HBB/target/release/RustDesk %{buildroot}/usr/bin/RustDesk
install $HBB/libsciter-gtk.so %{buildroot}/usr/share/RustDesk/libsciter-gtk.so
install $HBB/res/RustDesk.service %{buildroot}/usr/share/RustDesk/files/
install $HBB/res/128x128@2x.png %{buildroot}/usr/share/icons/hicolor/256x256/apps/RustDesk.png
install $HBB/res/scalable.svg %{buildroot}/usr/share/icons/hicolor/scalable/apps/RustDesk.svg
install $HBB/res/RustDesk.desktop %{buildroot}/usr/share/RustDesk/files/
install $HBB/res/RustDesk-link.desktop %{buildroot}/usr/share/RustDesk/files/

%files
/usr/bin/RustDesk
/usr/share/RustDesk/libsciter-gtk.so
/usr/share/RustDesk/files/RustDesk.service
/usr/share/icons/hicolor/256x256/apps/RustDesk.png
/usr/share/icons/hicolor/scalable/apps/RustDesk.svg
/usr/share/RustDesk/files/RustDesk.desktop
/usr/share/RustDesk/files/RustDesk-link.desktop

%changelog
# let's skip this for now

%pre
# can do something for centos7
case "$1" in
  1)
    # for install
  ;;
  2)
    # for upgrade
    systemctl stop RustDesk || true
  ;;
esac

%post
cp /usr/share/RustDesk/files/RustDesk.service /etc/systemd/system/RustDesk.service
cp /usr/share/RustDesk/files/RustDesk.desktop /usr/share/applications/
cp /usr/share/RustDesk/files/RustDesk-link.desktop /usr/share/applications/
systemctl daemon-reload
systemctl enable RustDesk
systemctl start RustDesk
update-desktop-database

%preun
case "$1" in
  0)
    # for uninstall
    systemctl stop RustDesk || true
    systemctl disable RustDesk || true
    rm /etc/systemd/system/RustDesk.service || true
  ;;
  1)
    # for upgrade
  ;;
esac

%postun
case "$1" in
  0)
    # for uninstall
    rm /usr/share/applications/RustDesk.desktop || true
    rm /usr/share/applications/RustDesk-link.desktop || true
    update-desktop-database
  ;;
  1)
    # for upgrade
  ;;
esac
