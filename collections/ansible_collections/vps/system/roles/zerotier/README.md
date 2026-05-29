# Role: vps.system.zerotier

## 1. 概述
该角色用于在 Linux 主机上安装 ZeroTier 客户端，并实现自动加入指定网络以及 Moon 节点的配置。

## 2. 变量说明
| 变量名 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `zerotier_network_id` | `""` | ZeroTier 网络 ID（必填）。 |
| `zerotier_port` | `9993` | ZeroTier 使用的 UDP 端口。 |
| `zerotier_api_url` | `https://my.zerotier.com` | ZeroTier API 地址。 |
| `proxy_enabled` | `false` | 是否使用代理下载（仅影响下载过程，不影响安装）。 |
| `proxy_http` | `""` | HTTP 代理地址。 |
| `proxy_https` | `""` | HTTPS 代理地址。 |

**注意**: 无论 `proxy_enabled` 设置如何，ZeroTier 都会在未安装时自动安装。代理设置仅影响下载过程，使用 `| default('')` 确保未定义时不会报错。

## 3. 内部逻辑
- **安装**: 自动识别操作系统并使用 ZeroTier 官方脚本或仓库安装。
- **网络加入**: 如果提供了 `network_id`，则自动执行 `zerotier-cli join`。
- **Moon 配置**: 支持将当前节点配置为 Moon 节点或加入现有的 Moon 节点。

## 4. 依赖关系
- 操作系统: Debian / Ubuntu / CentOS。
- 网络: 需要能够访问 ZeroTier 官方基础设施。

## 5. 维护与排查
- **查看状态**: `zerotier-cli status`。
- **查看网络**: `zerotier-cli listnetworks`。
- **查看 Peers**: `zerotier-cli listpeers`。
- **手动加入**: `zerotier-cli join <network_id>`。
