<div align="center">

# Gomoku

一个使用 **仓颉语言** 实现的五子棋项目，包含规则引擎、启发式 AI、HTTP 服务和浏览器前端。

**Local PvP · AI Battle · LAN Room · Firestore Records**

</div>

## Overview

`finalwork` 是一个可直接运行的完整应用，而不是单独的算法演示或静态页面示例。

它提供：

- 本地双人对战
- 人机对战
- 局域网房间联机
- 浏览器单页前端
- Firestore 对局记录
- 单元测试

## Preview

默认启动后可在浏览器访问：

```text
http://127.0.0.1:8080
```

## Tech Stack

| Layer | Stack |
| --- | --- |
| Language | Cangjie |
| Build | `cjpm` |
| Backend | `std.net`, `std.fs`, `std.collection` |
| Frontend | HTML, CSS, Vanilla JavaScript |
| Database | Firebase Firestore |

## Quick Start

先确认本机已经安装仓颉工具链，并且 `cjpm` 可用：

```bash
cjpm --version
```

启动流程：

```bash
cjpm check
cjpm build
cjpm run
```

启动后在浏览器访问：

```text
http://127.0.0.1:8080
```

如需局域网访问，可使用运行机器的局域网 IP，例如：

```text
http://192.168.x.x:8080
```

运行测试：

```bash
cjpm test
```

## Project Structure

```text
src/          Cangjie backend source
web/          frontend assets
cjpm.toml     project manifest
LICENSE       MIT license
```

## Firebase

项目前端支持将已完成对局写入 Firestore。

如需启用：

1. 在 Firebase 控制台创建 Web App
2. 开启 `Cloud Firestore`
3. 将配置填入 [web/app.js](/Users/danny/XJTU/compute/final/finalwork/web/app.js:19)

## License

This project is licensed under the [MIT License](/Users/danny/XJTU/compute/final/finalwork/LICENSE).
