# 跨域云盘

`CrossCloud Drive` 是一个面向 Windows 云电脑和普通 Windows 设备的多云对象存储挂载工具。当前版本支持阿里云国际版 OSS，使用 PowerShell、rclone、WinFsp 和 Windows 任务计划程序，将一个 Bucket 或指定前缀挂载为盘符；后续计划在同一 Provider 架构下增加 Amazon S3、S3 兼容存储和 Google Cloud Storage。

仓库名 `crosscloud-drive` 面向多云场景，不绑定某一个云厂商。当前代码中的 OSS、RAM 和 Endpoint 说明均对应首个 Provider：Alibaba Cloud International OSS。

## 当前能力

- 中文和 English GUI 即时切换，不需要额外的 Python、Node.js 或 Go 运行时。
- Bucket 默认为空，OSS 路径 `/` 表示整个 Bucket。
- 默认 VFS 缓存上限 `5G`，可选 `5G`、`10G`、`20G` 或自定义值，最小 `1G`。
- 默认目录缓存 `1m`，保留对象修改时间。
- 测试访问成功后再保存连接并挂载，避免把错误配置注册为自动任务。
- 登录自动挂载和每 5 分钟一次的隐藏恢复检查。
- 停止、重新连接和“移除此设备上的连接”分开处理。
- RAM 前缀隔离策略和管理员全桶对象读写策略批量生成。

V2 每个 Windows 用户只管理一个 CrossCloud 连接；不会接管或结束其他软件、其他 Windows 用户的 rclone 进程。后续可以在 Provider 边界增加 Amazon S3、S3 兼容存储或 GCS，但首期不包含这些服务。

## Provider 状态

| Provider | 状态 | 说明 |
|---|---|---|
| Alibaba Cloud International OSS | 已支持 | 当前 GUI、CLI、RAM 策略脚本和文档覆盖此 Provider。 |
| Amazon S3 | 计划中 | Provider 边界已预留，尚未实现。 |
| S3 兼容存储 | 计划中 | 后续可复用 S3 参数模型接入 MinIO、Cloudflare R2 等服务。 |
| Google Cloud Storage | 计划中 | 后续作为独立 Provider 接入。 |

## 快速开始

普通用户建议从 GitHub Releases 下载 `CrossCloudDrive-<version>.zip`，解压后双击 `CrossCloudDrive.exe`。如果 Windows SmartScreen 提示风险，请确认下载来源是本仓库 Release，并核对 `SHA256SUMS.txt`。

从源码运行时：

1. 将整个项目目录复制到目标 Windows 云电脑。GUI 依赖 `scripts` 下的模块、Provider 和语言文件，不能只复制单个 `.ps1` 文件。
2. 双击 `scripts\start-oss-mount-gui.vbs`。这个入口会隐藏 PowerShell 启动窗口；`.cmd` 仅作为兼容入口保留。
3. 第一次使用，在“连接”页安装 rclone 和 WinFsp。
4. 在“设置”页填写地域、Bucket、OSS 目录、AccessKey ID 和 Secret。
5. 点击“仅测试”，确认 RAM 权限可用后点击“保存并连接”。

启动命令：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\oss-mount-gui.ps1
```

详细说明：

- [中文用户使用手册](docs/用户使用手册.md)
- [中文管理员部署指南](docs/管理员部署指南.md)
- [English User Guide](docs/User-Guide.md)
- [English Administrator Guide](docs/Administrator-Guide.md)
- [Roadmap](docs/ROADMAP.md)

## Alibaba OSS / RAM 权限

普通员工使用独立 RAM 用户，并把对象权限限制到 `users/<user>/` 这类前缀。管理员或 NAS 账号才使用全桶对象读写策略。不要使用阿里云主账号 AccessKey。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\create-oss-ram-users.ps1 `
    -Bucket "<bucket-name>" `
    -Usernames "<user-a>","<user-b>" `
    -CreateAccessKey
```

创建 NAS 或管理员账号时：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\create-oss-ram-users.ps1 `
    -Bucket "<bucket-name>" `
    -Usernames "<admin-user>" `
    -PolicyMode FullBucket `
    -CreateAccessKey
```

Alibaba Cloud CLI 需要预先安装并配置有 RAM 管理权限的管理员身份。脚本生成的 CSV 含明文 Secret，必须放入密码管理器，配置完成后安全删除，绝不能提交到仓库。

## 对象存储边界

对象存储不是 NTFS。文件夹通常是对象名前缀，空文件夹可能表现为目录标记；目录缓存、文件锁、随机写入和重命名行为可能与本地磁盘不同。删除、覆盖和版本控制也可能继续占用历史版本存储空间。工具的停止和本机移除只处理本机任务、进程、remote、配置和缓存，不删除云端对象。

`--vfs-cache-max-size` 是 rclone 的清理目标，不是硬性磁盘配额。上传中或仍被占用的文件可能让缓存短时间超过设置值；系统盘剩余空间不足时，保存和上传可能失败。

## 安全发布检查

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-ReleaseReadiness.ps1
```

该脚本会执行 PowerShell 语法检查、全部本地测试和公开发布敏感信息扫描。字段名、策略动作名和扫描规则本身不代表真实凭据；发现匹配结果后仍需人工核对上下文。

不要提交 AccessKey、Secret、凭据 CSV、`rclone.conf`、日志、缓存、真实 Bucket、公司内部路径、截图或内部人员信息。`.gitignore` 已覆盖常见凭据和运行时文件，但发布前仍需人工复核。

生成本地 Release 产物：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Release.ps1 -Version "0.1.0"
```

生成的 `dist/` 目录、exe、zip 和校验文件只用于 GitHub Release，不提交到 git。

## 许可证

[MIT](LICENSE)
