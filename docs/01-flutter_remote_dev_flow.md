# Flutter 远程开发与 GitHub Actions 自动构建发布流程

## 1. 目标

在 **本地尽量不安装完整开发环境** 的前提下，完成以下流程：

1. 本地使用代码编辑器编写 Flutter 项目代码。
2. 通过 Git 提交并推送到 GitHub 仓库。
3. 由 GitHub Actions 自动拉取代码、安装 Flutter、执行构建。
4. 自动上传构建产物。
5. 在打版本标签时，自动创建 GitHub Release 并附带构建包。

这套流程适合：

- 本地磁盘空间较紧张
- 不希望本地安装 Flutter / Android Studio / 大量依赖
- 接受“本地只写代码，构建交给云端”

---

## 2. 整体架构

```text
本地编辑器写代码
    ↓
Git add / commit / push
    ↓
GitHub 仓库收到变更
    ↓
GitHub Actions workflow 自动触发
    ↓
云端 runner 安装 Flutter 并执行构建
    ↓
生成构建产物
    ├─ 上传为 Actions artifact
    └─ 如为版本标签，则自动发布到 GitHub Release
```

---

## 3. 各部分职责

### 3.1 本地电脑

本地只需要承担轻量工作：

- 编辑代码
- 查看和管理 Git 变更
- 提交并推送到仓库

推荐本地最小配置：

- VS Code
- Git
- 可选：Remote SSH（如果你要连云服务器编辑）

本地可以不安装：

- Flutter SDK
- Android Studio
- Visual Studio
- Android SDK

前提是你不在本地运行和调试。

---

### 3.2 GitHub 仓库

仓库负责保存：

- Flutter 项目源码
- workflow 文件
- 版本标签
- Release 记录

关键目录：

```text
.github/workflows/
```

这里面放的 YAML 文件就是整个自动化流程的核心。

---

### 3.3 GitHub Actions

GitHub Actions 负责：

- 在云端 runner 上自动执行构建任务
- 安装 Flutter SDK
- 执行 `flutter pub get`
- 执行 `flutter build web`
- 打包构建产物
- 上传 artifact
- 在版本标签触发时自动创建 Release

可以理解为：

> workflow 才是这套流程真正的关键。

---

## 4. 推荐的最小测试方案

为了先跑通整条链路，建议先使用：

**Flutter Web Demo**

原因：

- 构建简单
- 不依赖 Android / iOS 真机环境
- 适合验证自动构建与发布流程
- 产物就是静态网页文件，容易打包

建议先验证以下两种触发：

1. `push main`：自动构建并上传 artifact
2. `push tag v0.1.0`：自动构建并发布 Release

---

## 5. 项目初始化流程

如果本地不装 Flutter，可以在云服务器上先生成一次项目骨架。

### 5.1 服务器初始化项目

```bash
flutter create --platforms=web flutter_release_demo
cd flutter_release_demo
git init
git branch -M main
git remote add origin 你的仓库地址
git add .
git commit -m "init flutter web demo"
git push -u origin main
```

完成这一步后，本地只需要拉取仓库并继续写代码。

---

## 6. 本地开发流程

### 6.1 日常改代码

主要改这些文件：

- `lib/main.dart`
- `pubspec.yaml`
- 其他业务代码文件

### 6.2 提交代码

```bash
git add .
git commit -m "update demo"
git push origin main
```

推送到 `main` 后，GitHub Actions 会自动执行构建。

---

## 7. 示例 workflow

文件路径：

```text
.github/workflows/build-release.yml
```

示例内容：

```yaml
name: build-and-release-flutter-web

on:
  push:
    branches:
      - main
    tags:
      - 'v*'

permissions:
  contents: write

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install Flutter
        run: |
          git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
          echo "$HOME/flutter/bin" >> $GITHUB_PATH
          flutter --version
          flutter config --enable-web

      - name: Get dependencies
        run: flutter pub get

      - name: Build web
        run: flutter build web

      - name: Package build output
        run: |
          tar -czf flutter-web-build.tar.gz -C build web

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: flutter-web-build
          path: flutter-web-build.tar.gz

      - name: Create GitHub Release
        if: startsWith(github.ref, 'refs/tags/v')
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          gh release create "${{ github.ref_name }}" \
            flutter-web-build.tar.gz \
            --title "${{ github.ref_name }}" \
            --notes "Automated release for ${{ github.ref_name }}"
```

---

## 8. workflow 逻辑说明

### 8.1 触发条件

```yaml
on:
  push:
    branches:
      - main
    tags:
      - 'v*'
```

含义：

- 推送到 `main` 时运行
- 推送 `v` 开头的标签时也运行，例如 `v0.1.0`

---

### 8.2 权限设置

```yaml
permissions:
  contents: write
```

含义：

- 允许 workflow 使用仓库内容写权限
- 创建 Release 时需要这个权限

---

### 8.3 自动安装 Flutter

```yaml
- name: Install Flutter
  run: |
    git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
    echo "$HOME/flutter/bin" >> $GITHUB_PATH
    flutter --version
    flutter config --enable-web
```

含义：

- runner 上默认没有 Flutter
- 所以 workflow 每次运行时需要安装 Flutter
- 然后启用 Web 平台支持

---

### 8.4 拉依赖

```yaml
- name: Get dependencies
  run: flutter pub get
```

作用：

- 下载 `pubspec.yaml` 中声明的依赖

---

### 8.5 构建 Web 版本

```yaml
- name: Build web
  run: flutter build web
```

作用：

- 生成 `build/web` 目录
- 这是 Flutter Web 的发布产物目录

---

### 8.6 打包构建结果

```yaml
- name: Package build output
  run: |
    tar -czf flutter-web-build.tar.gz -C build web
```

作用：

- 把构建后的静态文件压缩成单个文件
- 方便上传 artifact 或挂到 Release

---

### 8.7 上传 artifact

```yaml
- name: Upload artifact
  uses: actions/upload-artifact@v4
  with:
    name: flutter-web-build
    path: flutter-web-build.tar.gz
```

作用：

- 每次构建都会保存一个可下载产物
- 适合临时测试或下载验证

---

### 8.8 自动创建 Release

```yaml
- name: Create GitHub Release
  if: startsWith(github.ref, 'refs/tags/v')
```

作用：

- 只有在推送版本标签时才创建正式发布
- 平时 `push main` 不会生成 Release

---

## 9. 版本发布流程

### 9.1 平时开发

```bash
git add .
git commit -m "update page"
git push origin main
```

结果：

- 自动构建
- 自动生成 artifact
- 不创建 Release

### 9.2 正式打版本

```bash
git tag v0.1.0
git push origin v0.1.0
```

结果：

- 自动构建
- 自动上传 artifact
- 自动创建 GitHub Release
- Release 中附带构建压缩包

---

## 10. GitHub Pages 能否配合使用

可以。

如果后续想让 Flutter Web 直接在线访问，可以在当前流程跑通后，再增加一个 Pages 发布 workflow。

建议的顺序是：

1. 先跑通 Release 流程
2. 再接入 GitHub Pages

这样排错最简单。

---

## 11. 适合你的使用方式

根据你当前需求，推荐采用：

### 方案 A：本地只写代码 + GitHub Actions 自动构建

适合：

- 本地磁盘空间紧张
- 不需要本地运行测试
- 先跑通最小开发闭环

### 方案 B：本地写代码 + 云服务器辅助 + GitHub Actions 发布

适合：

- 想偶尔在远程服务器手动执行命令
- 希望在 Actions 之外保留一个可控环境

---

## 12. 当前方案的边界

这套流程非常适合：

- Flutter Web
- 代码验证
- 自动化打包
- 自动 Release

但要注意：

### 12.1 不适合直接产出 iOS `.ipa`

原因：

- iOS 打包需要 macOS 和 Xcode
- GitHub Actions 若要打 iOS，需要 macOS runner

### 12.2 不适合本地即时调试体验

因为：

- 你本地不运行项目
- 无法获得完整的本地热重载和本地调试体验

所以当前方案更偏向：

> 轻本地、重云端的自动构建流程

---

## 13. 建议的落地顺序

### 第一步

先创建最小 Flutter Web Demo 仓库。

### 第二步

把 workflow 放进：

```text
.github/workflows/build-release.yml
```

### 第三步

修改 `lib/main.dart`，提交并推送。

### 第四步

进入 GitHub 仓库的 Actions 页面，确认构建是否成功。

### 第五步

打一个标签，例如：

```bash
git tag v0.1.0
git push origin v0.1.0
```

### 第六步

确认 GitHub Release 是否自动生成。

---

## 14. 一句话总结

这套开发流程的核心不是“本地环境”，而是：

**本地只负责写代码，GitHub Actions workflow 负责自动安装 Flutter、构建、打包、上传 artifact、发布 Release。**

如果只是想低成本跑通开发链路，这已经是最省本地空间、最容易验证的一种方案。

