# 技术报告

## 1. 项目概述

本项目是一个基于仓颉语言实现的五子棋系统，目标不是只完成单一算法或单一界面，而是实现一个能够直接运行的完整应用。系统包含规则引擎、启发式 AI、HTTP 服务、局域网房间机制、浏览器前端以及 Firestore 对局记录功能。

项目的核心设计思路是以后端作为唯一真实状态源。棋盘状态、回合切换、胜负判定与合法性检查全部由后端控制，前端只负责展示、输入和状态同步。

## 2. 功能目标

系统当前支持以下功能：

- 本地双人对战
- 人机对战
- 局域网房间对战
- 浏览器可视化棋盘交互
- 对局状态展示
- 已完成对局写入 Firestore
- 单元测试验证规则与 AI 行为

## 3. 系统架构

系统整体采用前后端分离但后端主导状态的结构，可分为四层。

### 3.1 表现层

前端位于 `web/` 目录，由 `index.html`、`styles.css` 和 `app.js` 组成，负责：

- 渲染 15 x 15 棋盘
- 接收用户点击
- 调用后端接口
- 显示当前玩家、对局结果、最后一步和房间状态
- 在局域网模式下轮询房间状态
- 将已结束对局写入 Firestore 并读取历史记录

### 3.2 应用层

应用层由 `GomokuHttpApp` 负责，位于 [src/gomoku_http.cj](/Users/danny/XJTU/compute/final/finalwork/src/gomoku_http.cj:1)。该层主要职责是：

- 管理本地对局实例
- 管理 AI 对局实例
- 管理局域网房间创建、加入、重开与状态查询
- 将领域层结果转换为 HTTP API 输出

### 3.3 领域层

领域层位于 [src/gomoku_core.cj](/Users/danny/XJTU/compute/final/finalwork/src/gomoku_core.cj:1)，负责五子棋核心规则，包括：

- 棋盘数据结构 `Board`
- 棋子枚举 `Stone`
- 对局结果枚举 `GameResult`
- 落子记录 `Move`
- 对局会话 `GameSession`
- 落子规则、胜负判定与平局判定 `GameRules`

### 3.4 策略层

AI 模块位于 [src/gomoku_ai.cj](/Users/danny/XJTU/compute/final/finalwork/src/gomoku_ai.cj:1)。该层使用启发式评估方法，为 AI 模式提供自动选点能力。

## 4. 主要模块设计

### 4.1 棋盘与规则模块

规则模块的设计重点是保证逻辑纯净与可测试性。

- `Board` 只负责棋盘状态存取，不直接承担业务规则判断
- `GameSession` 保存当前棋盘、当前回合、落子历史、对局结果和结束状态
- `GameRules.placeStone` 是核心入口，统一处理：
  - 对局是否已经结束
  - 坐标是否合法
  - 目标位置是否为空
  - 落子后的胜负判定
  - 是否平局
  - 回合切换

胜负判断采用“四个方向连线计数”的方式，分别检查横向、纵向、主对角线和副对角线，只要任一方向累计达到五子即可判胜。

### 4.2 AI 模块

AI 采用启发式评分，而不是搜索树或外部模型。其优点是实现直接、速度较快、适合课程项目规模。

AI 的主要流程如下：

1. 遍历候选点
2. 评估当前点的进攻价值
3. 评估对手潜在威胁
4. 优先处理直接制胜点
5. 若无制胜点，则优先处理必须防守点
6. 在剩余候选点中选择综合评分最高的位置

当前代码中定义了 `Easy` 和 `Normal` 两种难度，并通过棋型分析对活四、冲四、活三、眠三等模式进行评分。

### 4.3 HTTP 服务模块

HTTP 服务同样在 [src/gomoku_http.cj](/Users/danny/XJTU/compute/final/finalwork/src/gomoku_http.cj:1) 中实现。该服务不依赖外部 Web 框架，而是直接基于 `std.net` 的 `TcpServerSocket` 提供能力。

服务端主要完成以下工作：

- 监听 `0.0.0.0:8080`
- 解析 HTTP 请求
- 路由静态资源请求
- 路由 API 请求
- 输出 JSON 响应

入口位于 [src/main.cj](/Users/danny/XJTU/compute/final/finalwork/src/main.cj:1)，启动时创建 `GomokuHttpApp` 和 `GomokuServer`，随后进入常驻服务状态。

### 4.4 局域网房间模块

局域网模式通过 `LanRoom` 实现。每个房间维护：

- 房间号 `roomId`
- 黑方令牌 `blackToken`
- 白方令牌 `whiteToken`
- 房间对应的 `GameSession`

该设计允许两名玩家在同一后端服务上通过房间号加入同一局游戏。服务端同时负责：

- 判定房间是否存在
- 判定玩家令牌是否合法
- 判定当前是否轮到该玩家落子
- 维护连接状态

### 4.5 Firestore 记录模块

前端在 [web/app.js](/Users/danny/XJTU/compute/final/finalwork/web/app.js:1) 中接入 Firebase Web SDK，并在对局结束后将结果写入 Firestore。

当前写入内容包括：

- 对局模式
- 对局结果
- 总手数
- 房间号
- 最后一步
- 棋盘快照的序列化结果
- 完成时间

由于 Firestore 不支持直接写入嵌套二维数组，项目中将棋盘按行序列化为字符串数组后再持久化。

## 5. 前后端交互流程

系统运行时的典型流程如下：

1. 用户在浏览器打开首页
2. 前端加载棋盘和状态面板
3. 前端调用 `/api/local/start`、`/api/ai/start` 或房间接口初始化对局
4. 用户点击棋盘后，前端将坐标发送给后端
5. 后端调用规则层完成落子与判定
6. 若为 AI 模式，后端继续调用 AI 完成自动落子
7. 后端返回最新棋局 JSON
8. 前端更新棋盘与状态展示
9. 若对局结束，前端将结果写入 Firestore

## 6. 接口设计

系统对外暴露的主要接口包括：

- `GET /api/health`
- `POST /api/local/start`
- `POST /api/local/move`
- `POST /api/ai/start`
- `POST /api/ai/move`
- `POST /api/room/create`
- `POST /api/room/join`
- `POST /api/room/state`
- `POST /api/room/move`
- `POST /api/room/restart`

静态资源接口包括：

- `/`
- `/index.html`
- `/styles.css`
- `/app.js`

## 7. 项目目录说明

```text
src/
  main.cj               程序入口
  gomoku_core.cj        棋盘与规则模块
  gomoku_ai.cj          AI 模块
  gomoku_http.cj        HTTP 服务与房间逻辑
  gomoku_core_test.cj   规则测试
  gomoku_ai_test.cj     AI 测试

web/
  index.html            前端页面结构
  styles.css            页面样式
  app.js                前端交互与 Firestore 集成

cjpm.toml               项目配置
README.md               项目说明
LICENSE                 MIT 协议
```

## 8. 测试与验证

当前项目已包含规则层和 AI 层的单元测试。测试重点包括：

- 首次落子是否合法
- 非法坐标是否被拒绝
- 已占用位置是否被拒绝
- 对局结束后是否禁止继续落子
- 横向五连是否能正确判胜
- AI 是否能优先选择制胜点
- AI 是否能阻止对手的直接获胜点

已执行验证命令：

```bash
cjpm build
cjpm test
```

测试结果为 8 个用例全部通过。

## 9. 当前实现特点与不足

### 9.1 优点

- 架构清晰，规则、AI、HTTP 和前端职责明确
- 后端作为唯一真实状态源，避免前后端状态不一致
- 不依赖外部 Web 框架，结构简单、便于理解
- 功能完整，覆盖单机、AI、联机和云端记录
- 已具备基础测试能力

### 9.2 不足

- HTTP 协议处理为手写实现，健壮性有限
- 局域网房间数据仅保存在内存中，服务重启后会丢失
- AI 仍为启发式策略，棋力有限
- Firestore 当前仅保存基础记录，没有用户体系和排行榜
- 尚未加入身份认证、权限控制和更细粒度的异常处理

## 10. 后续优化方向

后续可以继续从以下方面扩展：

- 增加悔棋、复盘、棋谱导出
- 增加用户系统和排行榜
- 将房间与历史记录统一持久化
- 优化 AI 策略，引入更强的搜索能力
- 增强前端交互体验与状态提示
- 增加更多测试场景与异常路径验证

## 11. 结论

本项目已经完成了一个五子棋系统从规则层到前端展示的完整闭环，实现了可运行、可测试、可联机、可扩展的基础工程形态。对于课程设计、仓颉语言实践和小型全栈项目训练，该项目已经具备较好的展示价值和继续迭代的基础。
