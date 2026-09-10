#!/bin/sh
# Pack luci-app-vps000 as a PKGARCH=all ipk (OpenWrt 14.07 ipkg-build -c format).
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
TAR="tar --format=gnu --owner=0 --group=0 --numeric-owner"

mkdir -p "$WORKDIR/data" "$WORKDIR/ctrl" "$OUTDIR"
cp -a files/. "$WORKDIR/data/"
chmod 0755 "$WORKDIR/data/usr/sbin/vps000" \
	"$WORKDIR/data/usr/sbin/vps000-update" \
	"$WORKDIR/data/etc/init.d/vps000" \
	"$WORKDIR/data/etc/hotplug.d/iface/99-vps000" \
	"$WORKDIR/data/usr/share/vps000/killswitch.fw" 2>/dev/null || true

PKG_IMAGE_VERSION=$(sed -n 's/^PKG_IMAGE_VERSION:=//p' Makefile | head -1)
[ -n "$PKG_IMAGE_VERSION" ] || PKG_IMAGE_VERSION=$VER
printf 'VPS000_VERSION=%s\nVPS000_IMAGE=%s\nVPS000_REPO=vps668/luci-app-vps000\nVPS000_BOARD=mt7628\n' \
	"$VER" "$PKG_IMAGE_VERSION" > "$WORKDIR/data/usr/share/vps000/version"

$TAR -czpf "$WORKDIR/data.tar.gz" -C "$WORKDIR/data" .
SIZE=$(wc -c < "$WORKDIR/data.tar.gz" | awk '{print $1}')

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

echo "2.0" > "$WORKDIR/debian-binary"
$TAR -czf "$WORKDIR/control.tar.gz" -C "$WORKDIR/ctrl" .
IPK="${OUTDIR}/${PKG_NAME}_${VER}_all.ipk"
rm -f "$IPK"
# Outer gzip tar with ./ members — same as OpenWrt 14.07 `ipkg-build -c`.
( cd "$WORKDIR" && $TAR -zcf "$IPK" ./debian-binary ./data.tar.gz ./control.tar.gz )
echo "$IPK"
