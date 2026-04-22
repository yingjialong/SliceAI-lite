# Task 24 · SliceAI v2.0 Roadmap 规范评审

**任务开始时间**：2026-04-23
**任务状态**：已完成

---

## 任务背景

项目在 2026-04-23 新增了 v2.0 roadmap，产品定位从“划词 LLM 工具”重塑为“划词触发型 AI Agent 配置框架”。该 roadmap 涉及：

1. 产品定位、竞品锚点与目标用户整体切换
2. `SliceCore` 数据模型升级、`Orchestration` / `Capabilities` 两个新 target 引入
3. `ToolExecutor` 到 Agent/Pipeline 执行模型的根本性迁移
4. 配置 schema 从 v1 升级到 v2，并在后续 phase 中叠加 MCP / Skill / Marketplace / Prompt IDE / Pipeline

该类文档不是普通功能 spec，而是决定未来几个月研发方向的总设计，因此必须先做一次高强度评审，避免把错误抽象冻结为项目基线。

---

## 评审目标

### Step 1：核对当前项目真实基线

阅读 `README.md`、`docs/Task_history.md`、当前 `SliceAIKit/Package.swift`、`SliceCore/Tool.swift`、`SliceCore/Configuration.swift`、`SliceCore/ToolExecutor.swift`、`SliceAIApp/AppContainer.swift`，确认 roadmap 与当前实现之间的差距是真实存在还是叙事性夸大。

### Step 2：审查 roadmap 自身质量

重点检查：

- 是否真正覆盖产品核心诉求，而不是把“想象力”包装成无边界 scope
- 是否存在架构自相矛盾、抽象过度、阶段切分失真
- 是否补齐迁移、回滚、安全、权限、审计、实施顺序这些高风险工程问题

### Step 3：形成可执行的修正建议

输出决策结论、严重问题列表、建议修订方向，作为后续 Phase 0 plan 的前置输入。

---

## ToDoList

- [x] 阅读 `README.md`，确认项目当前对外叙事
- [x] 阅读 roadmap 全文并做逐段审查
- [x] 对照当前代码结构验证 roadmap 的迁移难度
- [x] 输出审查结论与问题分级
- [x] 更新 `docs/Task_history.md`
- [x] 创建本任务文档

---

## 评审结论

- **最终结论**：`REWORK_REQUIRED`
- **置信度**：`Medium`
- **总体判断**：方向是对的，说明你已经从“AI 写作小工具”转向更有潜力的“选中内容驱动的 Agent 配置工具”；但这份 roadmap 仍然把太多战略愿望、架构洁癖和生态想象压进了一份冻结规范里，缺少足够严格的 Phase 0 边界、迁移/回滚设计和安全闭环。若按原文直接开干，极大概率会在重构期失速。

---

## 主要发现

### P0 / P1 级问题

1. **Phase 0 不是“无感重构”，而是高风险换心手术**
   - roadmap 一边要求“用户视觉无感、无新功能”，一边在 Phase 0 中引入 `ExecutionContext`、`Permission`、`OutputBinding`、`Skill`、`MCPDescriptor`、`ExecutionEngine`、`ContextCollector`、`CostAccounting`、`AuditLog`、`ConfigMigratorV1ToV2` 等一整套新骨架。
   - 这不是单纯重构，而是“执行链路 + 持久化模型 + 依赖装配 + 测试边界”一起换。
   - 建议：把当前 Phase 0 拆为两个子阶段。Phase 0A 只做兼容性数据模型和 façade 包装，不删除 `ToolExecutor`；Phase 0B 再在旧行为完全回归后引入新的编排层。

2. **配置迁移是单向破坏式升级，没有可靠回滚策略**
   - roadmap 明确写了 `schemaVersion: 2` 自动迁移、备份旧文件、且“不做降级”。
   - 这意味着只要用户启动 v2 分支，配置即被提升到新格式，旧分支/旧 tag 立刻失去可逆兼容性。
   - 建议：至少二选一：
     - 双读双写一段时间，旧字段保留到 Phase 1 结束；
     - 或者 v2 beta 使用独立 config 路径，先避免污染主配置。

3. **安全模型不够硬，无法支撑你宣称的“信任第一”**
   - 文档允许未来接入 `shell`、`filesystem`、`mcp`、`AppIntents`、`Marketplace`、`Tool Pack`，但安全控制大多停留在“权限弹窗 + 默认确认”层。
   - 对于“导入陌生 pack / skill / MCP server”这种高风险入口，签名校验、来源标记、path canonicalization、输出脱敏、日志保留周期、危险操作审计都没有成体系定义。
   - 建议：先写威胁模型文档，再决定哪些能力能进 Phase 1，哪些必须推迟到有签名或隔离机制之后。

4. **核心领域模型存在自相矛盾，说明抽象还没收敛**
   - `ExecutionContext` 被定义为构建后只读不可变，但执行流程又让 `ContextCollector` 在运行时“填充” `context.contexts`。
   - `ContextCollector` 声称要按 DAG 调度，但 `ContextRequest` 结构中并没有 `depends` 字段。
   - 建议：先统一模型：
     - 用 `ExecutionSeed -> ResolvedExecutionContext` 两阶段对象；
     - 或者取消 DAG，Phase 1 仅保留平铺并发采集。

5. **路线图 scope 仍然过宽，产品核心会被生态功能稀释**
   - 你的真正机会点是“选中内容 -> 调用自定义能力 -> 回到当前工作流”。
   - 但 roadmap 同时塞进了 Marketplace、SliceAI as MCP server、Services、URL Scheme、Prompt IDE、Memory、TTS、Pipeline 可视化编辑器、Smart Actions 等多条大线。
   - 建议：明确一条主线作为 v2 核心：
     - “划词触发 Prompt/Agent/MCP”；
     - 其余全部降为候选扩展，不要先写进冻结 spec。

### P2 级问题

1. **竞品与“独占格”叙事证据不足**
   - “划词 × MCP 独家”是漂亮口号，但它是时效性很强的市场判断，文档里没有证据链，也没有把 moat 落到真正的用户迁移成本上。
   - 建议：把“独家”改成“当前主打差异化假设”，避免未来被市场事实反打脸。

2. **Provider capability 抽象提前过度**
   - 当前代码只有 OpenAI 兼容 provider，一口气把 Anthropic / Gemini / Ollama / capability routing / cascade 全推入核心模型，属于典型的“先为未来抽象”。
   - 建议：Phase 0 保留 `fixed(providerId, modelId)`；等第二种真实 provider 落地后再升维。

3. **成功指标带有明显愿望化叙事**
   - `DAU 5000`、`GitHub Stars 5k+`、`HN 首页`、`PH Top 5` 更像传播目标，不是实施阶段可验证的工程指标。
   - 建议：替换成能在单人开源项目里真正采集和校验的指标，例如：
     - 首个自定义 Tool 从创建到跑通的中位时长
     - 安装 MCP 后首次成功调用率
     - 选中触发到首 token 的分位响应时间

4. **文档体系已开始漂移**
   - `Task_history.md` 已把 v2 roadmap 记为“冻结规划”，但根目录 `README.md` 仍把项目定义为“macOS 开源划词触发 LLM 工具栏”，且状态写的是 `v0.1 开发中`。
   - 建议：只有当你真正接受本次评审后的修订版本时，再同步更新 `README.md`，否则仓库会同时存在两套互相冲突的对外叙事。

---

## 与当前代码基线的差距评估

### 当前基线

- `SliceAIKit/Package.swift` 当前只有 8 个 library target，还没有 `Orchestration` / `Capabilities`
- `SliceCore/Tool.swift` 仍是单次 prompt 调用模型
- `SliceCore/Configuration.swift` 当前 `schemaVersion` 还是 `1`
- `SliceCore/ToolExecutor.swift` 仍是“读取配置 -> 渲染 prompt -> 调用 provider”的单执行器架构
- `SliceAIApp/AppContainer.swift` 也是围绕旧执行模型装配

### 结论

这说明 roadmap 并不是“轻量升级”，而是一次结构级迁移。你的文档已经意识到这一点，但 Phase 0 时间与风险预算仍然偏乐观。

---

## 建议的修订方向

1. **把 v2.0 spec 收缩成“一个主张 + 一个核心 execution model + 一个最小可交付 phase”**
   - 主张：划词触发自定义 Prompt / Agent / MCP
   - 核心 execution model：先只支持 PromptTool + 受限 AgentTool，暂不引入 Pipeline
   - 最小可交付：Claude Desktop 风格 `mcp.json` 导入 + 单个受控 Agent demo

2. **重写 Phase 0 边界**
   - 只保留：
     - `Tool` 向后兼容升级
     - `ProviderSelection` 的最小版本
     - `ExecutionEngine` façade
     - config 双读或独立 beta 路径
   - 砍掉：
     - `CostAccounting`
     - `AuditLog`
     - `ContextCollector` DAG
     - `Skill` / `Marketplace` 相关数据结构预埋

3. **在进入实施前补两份文档**
   - `docs/superpowers/specs/2026-04-23-sliceai-v2-security-model.md`
   - `docs/superpowers/plans/2026-04-24-phase-0-refactor.md`

4. **重新定义“冻结”**
   - 现在这份文档不应该叫 Design Freeze。
   - 更准确的状态应是：`Draft reviewed, rework required`。

---

## 本次文档变动

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `docs/Task_history.md` | 修改 | 新增 Task 24 评审索引 |
| `docs/Task-detail/sliceai-v2-roadmap-review-2026-04-23.md` | 新建 | 记录本次规范评审过程与结论 |

---

## 测试与验证

本次任务为文档评审任务，未执行 `swift build` / `swift test`。验证方式为：

1. 通读 roadmap 全文并逐段交叉审查
2. 对照当前仓库核心代码与包结构验证迁移难度
3. 依据评审结论形成问题分级和修订建议

---

## 后续动作建议

1. 先不要直接开始 Phase 0 编码
2. 先按本评审意见重写 roadmap 的以下部分：
   - Phase 0 范围
   - 迁移/回滚策略
   - 安全模型
   - 成功指标
3. 重写后再产出新的 Phase 0 实施计划文档

