Name:       YunDesk
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
mkdir -p %{buildroot}/usr/share/YunDesk/
mkdir -p %{buildroot}/usr/share/YunDesk/files/
mkdir -p %{buildroot}/usr/share/icons/hicolor/256x256/apps/
mkdir -p %{buildroot}/usr/share/icons/hicolor/scalable/apps/
install -m 755 $HBB/target/release/YunDesk %{buildroot}/usr/bin/YunDesk
install $HBB/libsciter-gtk.so %{buildroot}/usr/share/YunDesk/libsciter-gtk.so
install $HBB/res/YunDesk.service %{buildroot}/usr/share/YunDesk/files/
install $HBB/res/128x128@2x.png %{buildroot}/usr/share/icons/hicolor/256x256/apps/YunDesk.png
install $HBB/res/scalable.svg %{buildroot}/usr/share/icons/hicolor/scalable/apps/YunDesk.svg
install $HBB/res/YunDesk.desktop %{buildroot}/usr/share/YunDesk/files/
install $HBB/res/YunDesk-link.desktop %{buildroot}/usr/share/YunDesk/files/

%files
/usr/bin/YunDesk
/usr/share/YunDesk/libsciter-gtk.so
/usr/share/YunDesk/files/YunDesk.service
/usr/share/icons/hicolor/256x256/apps/YunDesk.png
/usr/share/icons/hicolor/scalable/apps/YunDesk.svg
/usr/share/YunDesk/files/YunDesk.desktop
/usr/share/YunDesk/files/YunDesk-link.desktop

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
    systemctl stop YunDesk || true
  ;;
esac

%post
cp /usr/share/YunDesk/files/YunDesk.service /etc/systemd/system/YunDesk.service
cp /usr/share/YunDesk/files/YunDesk.desktop /usr/share/applications/
cp /usr/share/YunDesk/files/YunDesk-link.desktop /usr/share/applications/
systemctl daemon-reload
systemctl enable YunDesk
systemctl start YunDesk
update-desktop-database

%preun
case "$1" in
  0)
    # for uninstall
    systemctl stop YunDesk || true
    systemctl disable YunDesk || true
    rm /etc/systemd/system/YunDesk.service || true
  ;;
  1)
    # for upgrade
  ;;
esac

%postun
case "$1" in
  0)
    # for uninstall
    rm /usr/share/applications/YunDesk.desktop || true
    rm /usr/share/applications/YunDesk-link.desktop || true
    update-desktop-database
  ;;
  1)
    # for upgrade
  ;;
esac
