# 规格：Windows EXE 打包与 GitHub Release 发布

状态：已实施；本地构建脚本、exe launcher、zip 打包、SHA256 校验和发布检查已完成。真实 Windows 双击验收、代码签名和 GitHub Release 上传仍需发布前执行。

## 0. 当前假设

1. 首期目标是让普通 Windows 用户可以下载并双击运行 `CrossCloudDrive.exe`，不需要自己找到 `.ps1` 或 `.vbs` 入口。
2. 首期使用 `ps2exe` 将一个轻量 launcher 包装为 exe；launcher 再定位并启动 `scripts/oss-mount-gui.ps1`。不重写为 C#、WPF、WinUI 或 Electron。
3. exe、zip、校验文件只作为 GitHub Release 产物发布，不提交到 git 源码仓库。
4. 首期不内置 rclone 和 WinFsp；工具继续通过现有安装流程安装依赖。
5. 首期不做代码签名。未签名 exe 可能触发 Windows SmartScreen 或杀毒软件提示，发布说明必须明确说明来源和校验方式。
6. 首期不做 MSI/NSIS 安装器。后续如果用户量变大，再考虑安装器、开始菜单快捷方式、自动更新和签名。

如果这些假设有变化，先更新本文档，再进入实现。

## 1. 目标

为 CrossCloud Drive 增加一个标准的 Windows 开源发布形态：

- 开发者继续通过源码、PowerShell 脚本和测试来维护项目。
- 普通用户从 GitHub Releases 下载 `CrossCloudDrive.exe` 或 release zip。
- 发布包包含必要脚本、文档和校验文件，但不包含凭据、日志、缓存、真实配置或 `.git` 目录。
- 发布流程可以被本地脚本重复执行，并能在 GitHub Actions 中验证。

成功状态：用户看到 GitHub 项目时，有源码、有文档、有测试、有 Release 二进制，整体更像一个可实际使用的 Windows 工具。

## 2. 技术栈

- Windows PowerShell 5.1：现有 GUI、核心模块和发布脚本。
- WinForms：现有图形界面。
- rclone：实际对象存储挂载能力。
- WinFsp：Windows 文件系统挂载依赖。
- ps2exe：将 `scripts/CrossCloudDrive.Launcher.ps1` 包装为 `CrossCloudDrive.exe`。
- GitHub Actions：继续使用 `windows-latest` 执行发布前检查，后续可增加构建产物检查。

## 3. 命令

### 发布前检查

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-ReleaseReadiness.ps1
```

### 安装打包工具

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Install-Module ps2exe -Scope CurrentUser -Force"
```

### 生成本地 Release 产物

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Release.ps1 -Version "0.1.0"
```

预期输出：

```text
dist/
  CrossCloudDrive-0.1.0/
    CrossCloudDrive.exe
    README.md
    README.en.md
    LICENSE
    SECURITY.md
    CONTRIBUTING.md
    docs/
    scripts/
  CrossCloudDrive-0.1.0.zip
  SHA256SUMS.txt
```

### 本地运行 exe

```powershell
.\dist\CrossCloudDrive-0.1.0\CrossCloudDrive.exe
```

## 4. 项目结构

```text
scripts/
  oss-mount-gui.ps1          # GUI 源入口，仍是核心入口
  start-oss-mount-gui.vbs    # 源码模式下隐藏启动入口
  CrossCloudDrive.Launcher.ps1 # exe launcher 源脚本
  Build-Release.ps1          # 生成 exe、zip、校验文件
  Test-ReleaseReadiness.ps1  # 发布前检查

docs/
  EXE_PACKAGING_SPEC.md      # 本规格
  RELEASE_CHECKLIST.md       # 发布检查清单，需要补充 exe 发布项

dist/                        # 本地生成目录，不提交 git
  CrossCloudDrive-<version>/
  CrossCloudDrive-<version>.zip
  SHA256SUMS.txt

.github/workflows/
  test.yml                   # 继续跑测试，后续可增加 build 检查
```

## 5. 打包设计

### 5.1 exe 入口

`CrossCloudDrive.exe` 应包装轻量 launcher：

```powershell
scripts\CrossCloudDrive.Launcher.ps1
```

launcher 只负责定位 release 目录中的 `scripts\oss-mount-gui.ps1`，并用隐藏 PowerShell 进程启动真实 GUI。业务逻辑仍保留在现有 GUI 和共享模块中，不复制第二套挂载逻辑。

exe 启动后行为应与源码模式一致：

- 支持中文/英文 GUI。
- 能加载 `scripts` 下的模块、Provider 和语言文件。
- 能调用安装依赖、测试连接、保存并连接、停止、重新连接、移除本机连接等现有能力。
- 不把 AccessKey Secret 写入工具状态 JSON 或日志。

### 5.2 模块加载

首期不把所有模块嵌入单个 exe。release 目录中仍包含 `scripts/`，exe 作为更友好的启动入口。

这样做的好处：

- 风险低，不需要重写模块加载机制。
- 用户双击 exe 即可启动。
- 开发者仍能审计和修改脚本源码。
- 后续 S3/GCS Provider 文件可以继续按模块方式扩展。

### 5.3 产物边界

Release 包应包含：

- `CrossCloudDrive.exe`
- `README.md`
- `README.en.md`
- `LICENSE`
- `SECURITY.md`
- `CONTRIBUTING.md`
- `docs/`
- `scripts/`

Release 包不包含：

- `.git/`
- `.github/`，除非发布开发者源码包
- `tests/`，除非发布开发者源码包
- `dist/`
- 凭据 CSV
- `rclone.conf`
- 日志、缓存、截图、真实 Bucket、内部路径或人员信息

## 6. 代码风格

计划新增脚本遵循现有 PowerShell 风格：函数职责明确、参数显式、失败时抛出清晰错误、危险删除只作用于仓库内生成目录。

示例风格：

```powershell
function New-ReleaseDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    $distRoot = Join-Path $RepositoryRoot 'dist'
    $releasePath = Join-Path $distRoot "CrossCloudDrive-$Version"

    New-Item -ItemType Directory -Force -Path $releasePath | Out-Null
    return $releasePath
}
```

命名约定：

- 发布脚本使用动词-名词形式，例如 `Build-Release.ps1`。
- 函数使用 PowerShell PascalCase，例如 `New-ReleaseDirectory`。
- 生成产物使用 `CrossCloudDrive-<version>`。
- 不在命令行参数、日志或校验文件中输出 Secret。

## 7. 测试策略

### 7.1 自动检查

`Test-ReleaseReadiness.ps1` 应继续覆盖：

- PowerShell AST 语法检查。
- 现有本地测试。
- 敏感信息扫描。

计划新增：

- `Build-Release.ps1` AST 语法检查。
- `dist/`、`.zip`、`.exe` 默认不被 git 跟踪。
- Release 包不包含凭据、日志、缓存和 `.git`。
- `SHA256SUMS.txt` 中包含 exe 和 zip 的校验值。

### 7.2 手工 Windows 验收

每次正式发布前，在真实 Windows 电脑或云电脑上验证：

- 双击 `CrossCloudDrive.exe` 可以打开 GUI。
- 启动时不留下常驻 PowerShell 黑窗口。
- 中文和英文切换正常。
- 安装依赖、测试连接、保存并连接、停止、重新连接、移除本机连接正常。
- 计划任务仍使用隐藏启动器。
- 本机移除不删除云端对象。
- 未签名 exe 的 SmartScreen/杀毒提示已在 Release 说明中提醒。

## 8. 边界

### Always

- 发布前运行 `scripts/Test-ReleaseReadiness.ps1`。
- exe 和 zip 只进入 GitHub Release，不进入 git 仓库。
- 生成 SHA256 校验文件。
- 保留源码运行方式，方便开发者审计和调试。
- 发布说明明确当前只支持 Alibaba Cloud International OSS，S3/GCS 是计划中。

### Ask First

- 引入新的打包依赖或桌面运行时。
- 做代码签名、购买证书或接入第三方签名服务。
- 改成 MSI/NSIS/Inno Setup 安装器。
- 把 rclone 或 WinFsp 直接内置进发布包。
- 改动 GitHub Actions，使其自动创建公开 Release。

### Never

- 提交 AccessKey、Secret、凭据 CSV、`rclone.conf`、日志或缓存。
- 把真实 Bucket、公司内部路径、人员信息或私密截图放入 Release。
- 在发布脚本里递归删除未经确认的目录。
- 为了打包 exe 复制出第二套 GUI 或挂载逻辑。
- 发布会删除云端对象的卸载逻辑。

## 9. 成功标准

- 仓库中存在本文档，并且 README 或发布检查清单能指向 exe 发布流程。
- 新增 `scripts/Build-Release.ps1`，一条命令能生成 exe、zip 和 SHA256 文件。
- `scripts/Test-ReleaseReadiness.ps1` 通过。
- `git status --short` 不显示生成的 `dist/` 产物。
- 在真实 Windows 环境双击 exe 能打开 GUI，并完成至少一次“仅测试”流程。
- GitHub Release 可以上传 `CrossCloudDrive-<version>.zip` 和 `SHA256SUMS.txt`。

## 10. 已确认决策

1. 首期 exe 使用 `ps2exe` 生成。
2. Release zip 默认不包含 `tests/`，源码仓库保留测试。
3. 首期接受未签名 exe，但 Release 说明必须提醒 SmartScreen 风险并提供 SHA256 校验。
4. 初始发布版本使用 `0.1.0`。
5. exe 文件名使用 `CrossCloudDrive.exe`。
