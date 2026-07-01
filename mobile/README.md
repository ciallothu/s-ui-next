# S-UI Next Mobile

Flutter 管理客户端，目标平台为 Android arm64 与 iPhone arm64。移动端不嵌入 WebView，直接使用面板的 `/apiv3` JSON API。

主要能力：

- 与 Web 面板一致的主页、用户、入站、出站、节点、服务、TLS、基础配置、DNS、路由、管理员与设置管理。
- 任意自定义请求 Header；连接页预置 `CF-Access-Client-Id` 和 `CF-Access-Client-Secret`，可直接连接 Cloudflare Zero Trust Access Service Token 保护的面板。
- 用户用量、原始流量趋势、系统日志和操作审计均支持用户、日期和全文搜索。
- 数据库备份恢复、sing-box 配置导出、链接/订阅转换、密钥生成与服务重启。
- 面板地址、API Token 和自定义 Header 保存到 Android Keystore / iOS Keychain 支持的安全存储。

## 构建

本项目按仓库约定不在开发机生成移动端产物。运行 GitHub Actions 的 `Build S-UI Next Mobile` 工作流：

- `s-ui-next-android-arm64`：Android arm64 APK。
- `s-ui-next-iphone-arm64-unsigned`：未签名 iPhone arm64 IPA，需要使用自己的 Apple Developer 证书签名后安装。

工作流会临时生成 Flutter Android/iOS host 工程，将本目录源码复制进去，再执行 `flutter analyze`、`flutter test` 和对应平台构建。
