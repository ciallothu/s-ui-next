# S-UI Next Mobile API v3

API 根路径跟随面板 Web Path。例如面板为 `https://example.com/app/`，API 根路径为 `https://example.com/app/apiv3/`。

## 鉴权与 Cloudflare Access

- 标准鉴权：`Authorization: Bearer <token>`。
- 兼容旧客户端：`Token: <token>` 或 `X-API-Token: <token>`。
- 账号换取 Token：`POST auth/login`，JSON 字段为 `username`、`password`、`expiryDays`。
- Cloudflare Access Service Token 由客户端额外发送：`CF-Access-Client-Id` 与 `CF-Access-Client-Secret`。这些 Header 不由面板保存或转发。

所有 JSON 响应使用：

```json
{"success": true, "data": {}}
```

失败时返回对应 HTTP 4xx/5xx 与：

```json
{"success": false, "error": "message"}
```

## 资源与操作

- `GET bootstrap`：面板资源、状态、管理员和设置首屏数据。
- `GET resources/{inbounds|clients|outbounds|endpoints|services|tls|config|settings}`。
- `POST resources/{resource}`：`action` 支持 `new`、`edit`、`del`、`set`、`addbulk`、`editbulk`、`delbulk`，`data` 为原生 JSON 值。Endpoint 资源可额外发送 `apply: false` 仅保存；省略或设为 `true` 时会在完整配置校验后同步应用，失败则恢复原运行配置。
- `POST wireguard/export`：发送 `tag` 与从 0 开始的 `peerIndex`，返回受控生成的标准 WireGuard 客户端配置、名称和文件名。导出使用显式配置的 WireGuard UDP 地址，不使用管理面板域名。
- `GET status`、`GET onlines`。
- `GET users`、`PATCH users/:id`。
- `GET/POST tokens`、`DELETE tokens/:id`。
- `GET backup/database`、`POST backup/database`、`GET backup/singbox`。
- `POST actions/restart-core`、`POST actions/restart-panel`。
- `POST tools/link-convert`、`POST tools/sub-convert`、`POST tools/keypair`、`GET tools/check-outbound`。

## 用量、统计与日志

时间参数均为 Unix 秒。

- `GET analytics/usage`：`user`、`search`、`start`、`end`、`offset`、`limit`。数据库侧按用户聚合上传、下载和总量，并附带配额、到期时间、分组、在线状态与生命周期用量。
- `GET analytics/stats`：`resource`、`tag`、`search`、`start`、`end`、`offset`、`limit`。
- `GET analytics/connections`：`resource`、`tag`、`user`、`search`、`start`、`end`、`offset`、`limit`。连接记录会附带 `sourceInfo`、`destinationInfo`、`remoteInfo`，用于展示域名、解析 IP、归属、运营商和地区。
- `GET analytics/address-info`：`address`。按需补充单个连接目标的解析 IP、运营商与地区，供详情视图即时更新。
- `GET logs`：`level`、`user`、`search`、`start`、`end`、`offset`、`limit`。结果统一包含系统日志和配置变更审计；可解析的连接日志会在 `connection` 字段中带同样的 IP 归属信息。
- `GET changes`：`user`、`key`、`search`、`start`、`end`、`offset`、`limit`。

所有筛选均使用参数化数据库查询；分页上限由服务端约束，避免移动端一次拉取完整历史数据。
