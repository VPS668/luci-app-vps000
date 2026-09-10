# luci-app-vps000

VPS000 Cisco AnyConnect 路由器客户端（OpenWrt Barrier Breaker / MT7628）。

菜单：**VPN** → 连接 / 更新

## 用户可见

只需填写账号和密码。登录后选择线路连接。可选开机连接、分流、防泄露。

**更新**页从 GitHub Release 检查最新版本，可单独安装软件包，或升级整包固件（保留配置并重启）。

仓库：https://github.com/vps668/luci-app-vps000

## 编译

放到 OpenWrt 的 `package/luci-app-vps000`：

```
make package/luci-app-vps000/compile V=s
```

不经过完整 SDK 时，可在本仓库打包 ipk：

```
./scripts/pack-ipk.sh
```

依赖：`openconnect`、`luci-proto-openconnect`、`ip`、`curl`。本机 `jsonfilter` 用于解析 GitHub 清单。

## Release

每个 GitHub Release 包含：

| 文件 | 说明 |
|---|---|
| `manifest.json` | 版本清单，路由器更新页优先读取 |
| `luci-app-vps000_*-all.ipk` | 软件包 |
| `*-squashfs-sysupgrade.bin` | 可选，MT7628 整包固件 |

更新说明只维护一份：仓库根目录 `RELEASE_NOTES`。打 Release 时：

```
./scripts/publish-release.sh --firmware /path/to/sysupgrade.bin --push
```

`manifest.json` 的 `notes` 与 `gh release create --notes-file RELEASE_NOTES` 使用同一文案。

检查更新会依次尝试直连 GitHub 与若干镜像（ghproxy / ghfast / kkgithub 等）。

## 命令

```
vps000 login
vps000 connect
vps000 disconnect
vps000 status
vps000 update check
vps000 update apply ipk
vps000 update apply firmware
```
