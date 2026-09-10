include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-vps000
PKG_VERSION:=1.3.1
PKG_RELEASE:=6
PKG_IMAGE_VERSION:=1.3.1-5

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=luci
	CATEGORY:=LuCI
	SUBMENU:=3. Applications
	TITLE:=VPS000 AnyConnect VPN (account + password)
	PKGARCH:=all
	DEPENDS:=+openconnect +luci-proto-openconnect +ip +curl
endef

define Package/$(PKG_NAME)/description
	VPS000 Cisco AnyConnect client. User enters account and password;
	the gateway is hidden (login.wsdwan.com). Split routing uses
	existing chnroutes. No orchestrator API.
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/vps000
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(CP) ./files/* $(1)/
	chmod 0755 $(1)/usr/sbin/vps000 $(1)/usr/sbin/vps000-update $(1)/etc/init.d/vps000 \
		$(1)/etc/hotplug.d/iface/99-vps000 \
		$(1)/usr/share/vps000/killswitch.fw
	chmod 0644 $(1)/usr/share/vps000/portal.sh 2>/dev/null || true
	chmod 0644 $(1)/etc/openconnect/connect.d/10-vps000-dns 2>/dev/null || true
	echo "VPS000_VERSION=$(PKG_VERSION)-$(PKG_RELEASE)" > $(1)/usr/share/vps000/version
	echo "VPS000_IMAGE=$(PKG_IMAGE_VERSION)" >> $(1)/usr/share/vps000/version
	echo "VPS000_REPO=vps668/luci-app-vps000" >> $(1)/usr/share/vps000/version
	echo "VPS000_BOARD=mt7628" >> $(1)/usr/share/vps000/version
endef

define Package/$(PKG_NAME)/postinst
	#!/bin/sh
	[ -n "$${IPKG_INSTROOT}" ] || {
		/etc/init.d/vps000 enable >/dev/null 2>&1 || true
		rm -rf /tmp/luci-indexcache /tmp/luci-modulecache >/dev/null 2>&1 || true
	}
	exit 0
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
