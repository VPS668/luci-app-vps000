# luci-app-vps000

VPS000 Cisco AnyConnect 路由器客户端（OpenWrt Barrier Breaker / MT7628）。

## 功能简介
OpenWrt 路由器插件，实现 Cisco AnyConnect VPN 连接功能。用户只需输入账号密码，即可连接到 VPN 服务（网关地址隐藏）。支持开机自动连接、分流路由、防泄露等功能。

## 界面展示
- **VPN 连接**：账号密码登录、线路选择、连接/断开
- **更新管理**：检查最新版本、安装软件包、整包升级
- **状态监控**：实时连接状态显示

## 技术特点
- 基于 OpenWrt LuCI 框架开发
- 使用 openconnect 作为底层 VPN 客户端
- 集成中国大陆路由表（chnroutes）实现分流
- 支持 MT7628 平台（华硕 AC68U 等路由器）
- 配置文件：`/etc/config/vps000`

## 依赖组件
- `openconnect` - VPN 客户端核心
- `luci-proto-openconnect` - LuCI VPN 协议支持
- `ip-full`、`curl`、`ipset` - 网络工具
- `jsonfilter` - GitHub 版本信息解析

## 使用方法
1. 进入 LuCI 界面：**VPN → 连接 / 更新**
2. 输入账号和密码
3. 选择线路并连接
4. 可选：设置开机连接和分流规则

## 命令行操作
```
vps000 login          # 登录 VPN
vps000 connect        # 连接 VPN
vps000 disconnect     # 断开 VPN
vps000 status         # 查看状态
vps000 update check   # 检查更新
vps000 update apply ipk    # 安装软件包更新
vps000 update apply firmware # 整包固件升级
```

## 编译与发布
- 本地开发：`./scripts/pack-ipk.sh`
- 编译：`make package/luci-app-vps000/compile V=s`
- 发布：包含软件包、固件、manifest.json

仓库：https://github.com/vps668/luci-app-vps000

## 适用设备
华硕 AC68U（MT7628 平台）及其他基于 MT7628 的 OpenWrt 路由器。
