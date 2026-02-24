Name:       YunDesk
Version:    1.4.5
Release:    0
Summary:    RPM package
License:    GPL-3.0
URL:        https://YunDesk.com
Vendor:     YunDesk <info@YunDesk.com>
Requires:   gtk3 libxcb1 libXfixes3 alsa-utils libXtst6 libva2 pam gstreamer-plugins-base gstreamer-plugin-pipewire
Recommends: libayatana-appindicator3-1 xdotool
Provides:   libdesktop_drop_plugin.so()(64bit), libdesktop_multi_window_plugin.so()(64bit), libfile_selector_linux_plugin.so()(64bit), libflutter_custom_cursor_plugin.so()(64bit), libflutter_linux_gtk.so()(64bit), libscreen_retriever_plugin.so()(64bit), libtray_manager_plugin.so()(64bit), liburl_launcher_linux_plugin.so()(64bit), libwindow_manager_plugin.so()(64bit), libwindow_size_plugin.so()(64bit), libtexture_rgba_renderer_plugin.so()(64bit)

# https://docs.fedoraproject.org/en-US/packaging-guidelines/Scriptlets/

%description
The best open-source remote desktop client software, written in Rust.

%prep
# we have no source, so nothing here

%build
# we have no source, so nothing here

# %global __python %{__python3}

%install

mkdir -p "%{buildroot}/usr/share/YunDesk" && cp -r ${HBB}/flutter/build/linux/x64/release/bundle/* -t "%{buildroot}/usr/share/YunDesk"
mkdir -p "%{buildroot}/usr/bin"
install -Dm 644 $HBB/res/YunDesk.service -t "%{buildroot}/usr/share/YunDesk/files"
install -Dm 644 $HBB/res/YunDesk.desktop -t "%{buildroot}/usr/share/YunDesk/files"
install -Dm 644 $HBB/res/YunDesk-link.desktop -t "%{buildroot}/usr/share/YunDesk/files"
install -Dm 644 $HBB/res/128x128@2x.png "%{buildroot}/usr/share/icons/hicolor/256x256/apps/YunDesk.png"
install -Dm 644 $HBB/res/scalable.svg "%{buildroot}/usr/share/icons/hicolor/scalable/apps/YunDesk.svg"

%files
/usr/share/YunDesk/*
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
ln -sf /usr/share/YunDesk/YunDesk /usr/bin/YunDesk
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
    rm /usr/bin/YunDesk || true
    rmdir /usr/lib/YunDesk || true
    rmdir /usr/local/YunDesk || true
    rmdir /usr/share/YunDesk || true
    rm /usr/share/applications/YunDesk.desktop || true
    rm /usr/share/applications/YunDesk-link.desktop || true
    update-desktop-database
  ;;
  1)
    # for upgrade
    rmdir /usr/lib/YunDesk || true
    rmdir /usr/local/YunDesk || true
  ;;
esac
