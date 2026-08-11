# Git for Windows 本地化定制说明(Localization Custom Build)

本仓库是基于 `git-for-windows/build-extra` 的**本地定制**分支 `localization/all-languages`,
用于构建带完整本地化的 ARM64 (aarch64) Git 安装程序。
**不提交上游 PR**(上游有意保持安装程序/翻译文件精简,见 dscho 在 git-for-windows/git#724、#5353 的表态)。

## 定制内容(与上游差异)

### 1. `installer/release.sh` — 启用 `WITH_L10N`
在调用 `make-file-list.sh` 时传入 `WITH_L10N=1`,
使 git core 的 gettext 翻译(`clangarm64/share/locale/*/LC_MESSAGES/git.mo`,20 种语言)
不再被 `make-file-list.sh` 的 L10N 门过滤掉。
官方默认不传此变量(安装包不含任何 locale 文件)。

### 2. `make-file-list.sh` — 放行 man 页
- 包列表加入 `man-db groff gcc-libs`(`man`/`mandb` 命令与 groff 排版工具,man 渲染必需;
  `gcc-libs` 提供 groff 的 C++ 组件 `preconv`/`tbl`/`groff` 依赖的 `msys-stdc++-6.dll`)。
- 无条件过滤 `-e '/man/'`(子串匹配,排除全部 man 页)改为
  `-e '^/usr/man/' -e '^/usr/.*/man/'`(只排除 MSYS 侧 man 页)。
  这样 `clangarm64/share/man/**`(英文 + 28 语言翻译 man 页)进入安装包。
- 过滤正则 `^/usr/bin/msys-\(db\|curl\|icu\|gfortran\|stdc++\|quadmath\)[^/]*\.dll$`
  中移除 `stdc++`(上游为省体积故意排除 gcc 运行时大 DLL,但 groff 依赖
  `msys-stdc++-6.dll`,缺它会导致 `man git` 输出 0 字节/空白)。

### 3. `keep-despite-upgrade.txt` — 非包属文件清单
列出随包的自定义文件(它们不属于任何 pacman 包,`pacman -Ql` 不会列出):
- `/clangarm64/share/man/**` — 28 语言翻译 git man 页 + 英文 git man 页
- `/clangarm64/share/man/zh_CN/**`、`/clangarm64/share/man/zh_TW/**` —
  标准 locale 目录名(man-db 按 `LANG` 查找 `zh_CN`/`zh_TW`,
  l10n 项目的 `zh_HANS-CN`/`zh_HANT` 命名不匹配,需映射)
- `/usr/bin/col.exe` — man 输出管道需要的 `col`(属被排除的 util-linux 包)

## 本地化资源来源与构建

### git core 消息(20 语言)
`git/git` 自带 `po/`(gettext),构建时 `make install` 生成
`clangarm64/share/locale/<lang>/LC_MESSAGES/git.mo`。
语言:bg ca de el es fr ga id is it ko pl pt_PT ru sv tr uk vi zh_CN zh_TW。
随 `LANG`/`LC_ALL` 生效(测试:`LANG=zh_CN.UTF-8 git status` → 中文错误消息)。

### git man 页(28 语言 + 英文兜底)
- 翻译源:官方文档翻译项目 `jnavila/git-manpages-l10n`(版本对齐 git `v2.55.0` ↔ git 源码 `v2.55.0.windows.3`)。
- 构建:`make man`(po4a v0.74 翻译 → asciidoctor 渲染 `.1/.5/.7`)。
  存在单页 ≥80% 翻译门槛(`pre-translate-po`):完整语言(fr/ru/uk/sv/zh_HANS-CN/pt_BR 及部分 de/es/ja)
  生成 116–151 页;骨架语言(15–39% 完成度)多数页面被丢弃 → 0 页,回退英文。
- 安装到 `clangarm64/share/man/<lang>/man{1,5,7}`。
- 英文兜底:git 源码 `Documentation/make man` 生成,装到 `clangarm64/share/man/man{1,5,7}`。
- 简体中文映射 `zh_HANS-CN→zh_CN`、繁体 `zh_HANT→zh_TW`(man-db locale 查找需要)。
- 生效方式(不改 help 默认 html 行为):
  1. 用户 `git config --global help.format man`
  2. Git Bash 的 `profile.d/lang.sh` 自动按 Windows 用户区域设 `LANG`(`locale -uU`)
  3. `man`/`groff`/`less` 随包,MANPATH 含 `clangarm64/share/man`
  → 验证:`LANG=zh_CN.UTF-8 man git` 显示中文手册页。

## 环境注意事项(本机)

- **写入失败根因 = Smart App Control(智能应用控制),非 OneDrive**:构建中多次 mkdir/git-init/pacman 锁库/gem 写入失败,
  是 SAC 阻止进程写盘(用户手动放行)。SAC 关闭(`VerifiedAndReputablePolicyState=0`)后写入正常;
  OneDrive Files On-Demand 未开启。源码放非 OneDrive 路径 `C:\Users\tbyta\src` 仍推荐(规避本机拦截)。
- 直连 GitHub 挂起/SSL 失败 → 用 `gh-proxy.com` 前缀克隆。
- **SSL 后端 = 原生 Schannel(与上游 Git for Windows 一致)**:内置 git 链接 libcurl(Schannel),
  安装版 `etc/gitconfig` 无 sslbackend 覆盖 → 默认 schannel。本机 schannel 验证 github 失败
  (`CRYPT_E_NO_REVOCATION_CHECK`)是 Watt Toolkit MITM 中间证书不被 Windows 信任所致(本机环境问题);
  SDK 仓库 dev config 的 `http.sslbackend=openssl + ca-bundle` 是 Watt Toolkit 本机绕过,不进安装包。
- MSYS2 Rust 工具链与 SDK 的 llvm/openssl 不兼容 → 自包含 Rust 工具链位于 `C:\Users\tbyta\rust`
  (MSYS2 匹配版本),git 构建时 `PATH` 前置其 `clangarm64/bin`。
- 构建 git 用 `NO_RUST` 之外的官方同款方式(带 Rust gitcore,`aarch64-pc-windows-gnullvm` 目标)。
- po4a 的 Perl 依赖(polib、YAML::Tiny、Text::WrapI18N、Unicode::LineBreak 等)与
  asciidoctor 的 `parslet` gem 均为手工安装(清华镜像/手动解包)。

## 重新构建

```sh
# 构建并安装 git(含 git.mo)
cd /c/Users/tbyta/src/git
MSYSTEM=CLANGARM64 bash --login -c \
  'export PATH="/c/Users/tbyta/rust/clangarm64/bin:$PATH"; make -j$(nproc) DEVELOPER=1 && make install'

# 构建 28 语言 man 页并安装
cd /c/Users/tbyta/src/git-manpages-l10n
MSYSTEM=CLANGARM64 bash --login -c \
  'export GEM_HOME=/c/Users/tbyta/rubygems; export GEM_PATH=/c/Users/tbyta/rubygems:/clangarm64/lib/ruby/gems/4.0.0; make -j$(nproc) man && make install-man mandir=/c/Users/tbyta/OneDrive/Printer/GitHub/git-sdk-arm64/clangarm64/share/man'

# 构建安装程序(上游 SemVer 版本号)
cd /c/Users/tbyta/src/build-extra/installer
MSYSTEM=CLANGARM64 bash --login -c \
  'unset GIT_EDITOR VISUAL EDITOR; ./release.sh 2.55.0.windows.3'
# 产物:C:\Users\tbyta\Git-2.55.0.windows.3-arm64.exe(APP_VERSION=2.55.0.3)
```

## 验证结果(2026-08-11)

- `Git-2.55.0.windows.3-arm64.exe`(89 MB,上游 SemVer 版本号)静默安装成功。
- `git version 2.55.0.windows.3`(aarch64,从源码构建,含 Rust gitcore)。
- 20 语言 git.mo 生效:`LANG=zh_CN.UTF-8 git status` → 中文。
- 英文/中文/乌克兰语 man 页渲染正常:
  - `man git` → 英文;`LANG=zh_CN.UTF-8 man git` → 中文;
  - `LANG=uk_UA.UTF-8 man git` → 乌克兰语。
- 安装包含 man-db/groff/col/less 完整 man 工具链。
