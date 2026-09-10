#!/bin/sh
# Build manifest.json + GitHub Release. ipk and firmware are both required when --push.
# Usage:
#   ./scripts/publish-release.sh [--ipk path] [--firmware path] [--push]
set -e
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

PKG_NAME=luci-app-vps000
REPO_SLUG=vps668/luci-app-vps000
IPK=""
FW=""
PUSH=0
FW_NAME_DEFAULT=openwrt-ramips-mt7628-mt7628-squashfs-sysupgrade.bin

while [ $# -gt 0 ]; do
	case "$1" in
		--ipk) IPK=$2; shift 2 ;;
		--firmware|--fw) FW=$2; shift 2 ;;
		--push) PUSH=1; shift ;;
		-h|--help)
			echo "Usage: $0 [--ipk <ipk>] [--firmware <sysupgrade.bin>] [--push]" >&2
			exit 0
			;;
		*) echo "Unknown arg: $1" >&2; exit 1 ;;
	esac
done

find_firmware() {
	if [ -n "$FW" ] && [ -f "$FW" ]; then
		return 0
	fi
	local p
	for p in \
		"${VPS000_FIRMWARE:-}" \
		"$ROOT/release/$FW_NAME_DEFAULT" \
		"$ROOT/../../bin/ramips/$FW_NAME_DEFAULT" \
		"$ROOT/../../firmware/$FW_NAME_DEFAULT"
	do
		if [ -n "$p" ] && [ -f "$p" ]; then
			FW=$p
			return 0
		fi
	done
	return 1
}

mkdir -p "$ROOT/release"
if [ -z "$IPK" ] || [ ! -f "$IPK" ]; then
	IPK=$(sh "$ROOT/scripts/pack-ipk.sh" "$ROOT/release")
fi
[ -f "$IPK" ] || { echo "error: ipk missing" >&2; exit 1; }

VER=$(basename "$IPK" | sed -n "s/^${PKG_NAME}_\\(.*\\)_all\\.ipk$/\\1/p")
[ -n "$VER" ] || { echo "error: cannot parse version from $IPK" >&2; exit 1; }
TAG="v$(printf '%s' "$VER" | sed 's/-.*//')"
# Keep tag aligned with PKG_VERSION (1.3.1) even when release is 1.3.1-2
NOTES=$(cat "$ROOT/RELEASE_NOTES" 2>/dev/null || echo "${PKG_NAME} ${VER}")
IPK_NAME=$(basename "$IPK")
IPK_SHA=$(sha256sum "$IPK" | awk '{print $1}')
if [ "$(readlink -f "$IPK")" != "$(readlink -f "$ROOT/release/$IPK_NAME")" ]; then
	cp -f "$IPK" "$ROOT/release/$IPK_NAME"
fi

FW_JSON=""
if find_firmware; then
	FW_NAME=$(basename "$FW")
	FW_SHA=$(sha256sum "$FW" | awk '{print $1}')
	cp -f "$FW" "$ROOT/release/$FW_NAME"
	FW_JSON=$(printf ',"firmware":{"version":"%s","board":"mt7628","filename":"%s","url":"https://github.com/%s/releases/download/%s/%s","sha256":"%s"}' \
		"$VER" "$FW_NAME" "$REPO_SLUG" "$TAG" "$FW_NAME" "$FW_SHA")
	echo "firmware: $ROOT/release/$FW_NAME"
else
	echo "warning: firmware image not found (pass --firmware or set VPS000_FIRMWARE)" >&2
fi

if [ "$PUSH" = 1 ] && [ -z "$FW_JSON" ]; then
	echo "error: GitHub Release must include firmware. Example:" >&2
	echo "  $0 --firmware /path/to/$FW_NAME_DEFAULT --push" >&2
	exit 1
fi

# notes as a JSON string
NOTES_JSON=$(printf '%s' "$NOTES" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

printf '{"tag":"%s","version":"%s","notes":%s,"vps000":{"version":"%s","filename":"%s","url":"https://github.com/%s/releases/download/%s/%s","sha256":"%s"}%s}\n' \
	"$TAG" "$VER" "$NOTES_JSON" \
	"$VER" "$IPK_NAME" "$REPO_SLUG" "$TAG" "$IPK_NAME" "$IPK_SHA" \
	"$FW_JSON" > "$ROOT/release/manifest.json"

echo "ipk: $ROOT/release/$IPK_NAME"
echo "manifest: $ROOT/release/manifest.json"
echo "tag: $TAG"

if [ "$PUSH" != 1 ]; then
	echo "Local files ready. Push with: $0 --ipk '$IPK' --firmware '${FW:-$FW_NAME_DEFAULT}' --push"
	exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
	echo "error: gh not found" >&2
	exit 1
fi

gh release delete "$TAG" -R "$REPO_SLUG" -y 2>/dev/null || true
# shellcheck disable=SC2086
gh release create "$TAG" -R "$REPO_SLUG" \
	--title "$TAG" \
	--notes-file "$ROOT/RELEASE_NOTES" \
	"$ROOT/release/manifest.json" \
	"$ROOT/release/$IPK_NAME" \
	"$ROOT/release/$FW_NAME"
echo "GitHub Release: https://github.com/${REPO_SLUG}/releases/tag/${TAG}"
