#!/bin/sh
# Pack luci-app-vps000 as a PKGARCH=all ipk without the full OpenWrt SDK.
set -e
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

PKG_NAME=luci-app-vps000
PKG_VERSION=$(sed -n 's/^PKG_VERSION:=//p' Makefile | head -1)
PKG_RELEASE=$(sed -n 's/^PKG_RELEASE:=//p' Makefile | head -1)
VER="${PKG_VERSION}-${PKG_RELEASE}"
OUTDIR="${1:-$ROOT/release}"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

mkdir -p "$WORKDIR/data" "$WORKDIR/ctrl" "$OUTDIR"
cp -a files/. "$WORKDIR/data/"
chmod 0755 "$WORKDIR/data/usr/sbin/vps000" \
	"$WORKDIR/data/usr/sbin/vps000-update" \
	"$WORKDIR/data/etc/init.d/vps000" \
	"$WORKDIR/data/etc/hotplug.d/iface/99-vps000" \
	"$WORKDIR/data/usr/share/vps000/killswitch.fw" 2>/dev/null || true

printf 'VPS000_VERSION=%s\nVPS000_REPO=vps668/luci-app-vps000\nVPS000_BOARD=mt7628\n' \
	"$VER" > "$WORKDIR/data/usr/share/vps000/version"

SIZE=$(du -sb "$WORKDIR/data" | awk '{print $1}')

cat > "$WORKDIR/ctrl/control" <<EOF
Package: ${PKG_NAME}
Version: ${VER}
Depends: libc, openconnect, luci-proto-openconnect, ip, curl
Source: package/${PKG_NAME}
Section: luci
Architecture: all
Installed-Size: ${SIZE}
Description:  VPS000 Cisco AnyConnect client. User enters account and password;
 the gateway is hidden (login.wsdwan.com). Split routing uses
 existing chnroutes. No orchestrator API.
EOF

printf '/etc/config/vps000\n' > "$WORKDIR/ctrl/conffiles"

cat > "$WORKDIR/ctrl/postinst" <<'EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || {
	/etc/init.d/vps000 enable >/dev/null 2>&1 || true
	rm -rf /tmp/luci-indexcache /tmp/luci-modulecache >/dev/null 2>&1 || true
}
exit 0
EOF
chmod 0755 "$WORKDIR/ctrl/postinst"

echo 2.0 > "$WORKDIR/debian-binary"
tar -C "$WORKDIR/data" --owner=0 --group=0 -czf "$WORKDIR/data.tar.gz" .
tar -C "$WORKDIR/ctrl" --owner=0 --group=0 -czf "$WORKDIR/control.tar.gz" .
IPK="${OUTDIR}/${PKG_NAME}_${VER}_all.ipk"
rm -f "$IPK"
tar -C "$WORKDIR" --owner=0 --group=0 -cf "$IPK" debian-binary data.tar.gz control.tar.gz
echo "$IPK"
