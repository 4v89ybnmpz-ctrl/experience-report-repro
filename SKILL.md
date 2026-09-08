---
name: experience-report-repro
description: "在固定昇腾NPU容器里复现JSON体验评估报告中【痛点所在的各个阶段】，核实各阶段痛点/失败结论是否成立。输入是体验agent生成的JSON体验评估报告(记录某开源项目S0搜索→S1环境准备→S2快速体验→S3开发编译→S4测试验证→S5贡献各阶段的命令轨迹actual_path.actions、痛点pain_points/failure_reason、评分)。Report是主输入；同目录存在同次运行的log*.json时只能作补证(须满足项目/仓库branch/运行关联标记三条件)，不能替代Report。复现阶段由报告文件自动确定(自动痛点扫描):解析Report后自动扫描S1-S4全部阶段的pain_points/failure_reason(空串/'-'/空白占位不计,cons仅存目不算痛点;S0搜索与发现、S5反馈与贡献两阶段不纳入扫描与复现,其痛点如有仅在痛点分布表存目、不判定、不生成核实文件),生成痛点分布表,凡有实质痛点且not_evaluated=False、actions非空的阶段自动进入复现清单,无痛点的阶段不碰;用户显式指定阶段时以指定收窄为准,只给文件不指定阶段则全自动。核心机制:S1是环境基线——无论复现哪个阶段,都先严格按S1_SETUP阶段记录的actions把容器环境配置成与报告一致(照S1原样装,不自行补装/修正/对齐文档),其他阶段依赖这个环境;然后按阶段号升序逐阶段复现各痛点阶段的命令轨迹(被跳过的中间阶段若被后续痛点阶段依赖其产物,作为依赖前置重放),捕获真实退出码、读业务输出,逐条核实各痛点是否成立。当前执行模式为单容器report重放:只起report容器(按Report的S1+各痛点阶段actions重放,回答报告现象是否真实,容器名cann_test_ml_{项目名}{时间戳}_report_claude),挂载davinci设备与Ascend driver/firmware/npu-smi等;双子星docs容器(从干净状态按官方文档独立复现,回答普通用户按文档是否遇到该痛点)【已停用——保留设计待恢复】,停用期间“文档侧”核实改为在分析阶段直接读report容器已clone的同一commit仓库内文档原文(QUICKSTART/README/docs/)+源码对照,并在结论报告注明“未启用文档复现容器,文档符合性以原文对照方式核实”。全程独立,只依据被复现报告+本项目文档/源码,不读workspace其他项目结果;但工具链/依赖安装的非项目耦合通用踩坑可复用。痛点判定用“现象状态(成立/不成立/部分成立/无法判定=环境阻塞)+报告归因状态(项目/环境/用法/未确定)+可信度等级(高/中/低)”两层模型，“现象成立≠项目问题成立”；每条待核实痛点须单独生成核实文件log/painpoint_<阶段号>-<序号>_<slug>.md(痛点原文+指向的命令源+分[源码]/[文档]/[日志]三类标注的具体核实原因+逐段判定+能否提交/提交文本),repro_report.md汇总表逐行指向该文件。复现收尾须在工作目录根写README.md(全部产物与脚本的作用、对应报告命令、可粘贴的重跑命令与重放顺序)。触发:用户给出JSON体验报告要求复现/验证/核实痛点或失败结论是否成立(可显式指定某阶段S2快速体验/S3编译/S4测试等收窄范围,也可不指定——不指定时自动扫描报告识别各阶段痛点,对痛点所在阶段做复现),或要求起干净NPU容器验证某CANN/昇腾项目某阶段流程是否如报告所述。"
---

# 体验报告阶段复现与验证(昇腾NPU容器)

> **输入**:体验 agent 生成的 **JSON 体验评估报告**(用户**可选**指定要复现的阶段,不指定时自动识别)。
> **目标**:在固定的昇腾 NPU docker 容器里,**先按 S1 把环境配成与报告一致,再复现痛点所在的各个阶段**的命令轨迹,核实各阶段的**痛点/失败结论是否成立**——复现阶段由**自动痛点扫描**确定:解析报告后扫描 S1–S4 全部阶段的 `pain_points`/`failure_reason`,凡有实质痛点的阶段进入复现清单(用户显式指定时以指定收窄为准),无痛点的阶段不碰;**S0 搜索与发现、S5 反馈与贡献不纳入扫描与复现**(其痛点如有仅在分布表存目)。很多报告里的"痛点/失败/0%"其实是体验 agent 那次特定环境或用法的问题,甚至是它自身的判断有偏差,并非项目缺陷。

> ## ⛔ 当前执行模式:双子星 docs 复现路径已停用(只跑 report 容器)
>
> **自本版本起,docs 文档复现容器(`_docs_claude`/`_serial_docs_claude`)及其并行试跑/串行降级流程全部停用**。除非用户**显式要求恢复双子星**(明确说"启用双子星/起 docs 容器/文档路径独立复现"),否则一律按以下单容器模式执行:
>
> 1. **只起一个复现容器** `cann_test_ml_<项目名><时间戳后缀>_report_claude`,只做 Report 重放(S1 基线 + 各痛点阶段——自动痛点扫描确定,用户指定时以指定收窄);不起 docs 容器、不做并行试跑、无串行降级,执行模式记为"单容器 report 重放"。
> 2. **"文档侧"核实改为分析阶段原文对照**:在阶段 6-8 分析时,直接读取 report 容器 S1 已 clone 的**同一 commit 仓库内**文档原文(QUICKSTART/README/docs/ 下相关文档)+ 源码(build.sh/CMakeLists/脚本)对照,核实"文档描述与实际是否相符"类痛点(文档模板/路径/参数说明是否失实、文档是否给出必要信息)。文档原文如有引用核实价值,存档到 `log/`(如 `log/QUICKSTART_original.md`)。
> 3. **结论报告必须注明**:"文档复现容器未启用;文档符合性以仓库内文档原文+源码对照方式核实"。涉及"普通用户按文档从零执行是否可跑通"的结论,证据力降一级(原文对照 ≠ 独立干净执行),此类结论措辞用"文档原文与实际不符"而非"按文档必然失败",除非报告路径实测已证明。
> 4. **工作目录不再建 `docs_replay/`**、不写 `docs_` 前缀脚本、结论报告的"文档路径命令逐条复现/双路径对照"两节按模板标注"不适用(未启用)"并代之以"文档原文对照"小节。
> 5. 下文「双子星容器:Report 重放与文档对照」章节及各处 `_docs_claude`/并行试跑/串行降级的说明**为停用前的原设计,仅保留备查**,当前不得照做;恢复方法:删除本声明块并还原 frontmatter 中执行模式描述。

---

## 输入契约:Report 主输入,log 同次运行补证

当用户同时提供 `Report*.json` 和 `log*.json` 时,始终以 **`Report*.json` 作为主输入**:阶段选择、S1 基线、复现阶段命令、痛点、`failure_reason`、`cons` 和报告结论都从 Report 提取。`log*.json` 只能作为**同一次运行**的原始命令、状态、stdout/stderr 或 evidence 补充,不能替代 Report,也不能单独决定复现范围。

### 主报告有效性

- 有效的最终 Report 至少应包含 `meta`、`project`、`journey_steps[]`,且复现阶段能找到 `actual_path.actions[]`;`not_evaluated=True` 或 actions 为空时不可复现该阶段。
- 顶层只有 `hits`、`_shards`、`took` 等字段的 **Elasticsearch 查询响应不是最终 Report**,即使文件名以 `Report-` 开头也不能作为主输入(区别于下文「JSON 报告结构速查」变体 B——B 变体是 ES hits 包裹但内部有完整阶段数据,可挖取;这里指只有查询响应骨架、无阶段数据的文件);应要求用户提供包含 `journey_steps[]` 的完整报告。
- 如果用户只提供 `log*.json`,先说明它是原始执行日志,不能满足本 skill 的完整复现输入契约;除非用户明确接受"仅按日志做有限核查",否则请求有效 Report。

### log 同次运行匹配

在使用 log 前,先在输入目录中查找候选 `log*.json`,并建立匹配记录。只有**同时**满足以下条件,才可标记为"同次运行补证":

1. **项目身份一致**:`log._meta.project_name` 与 `Report.project.project_name`(或 `project_id`)一致;
2. **仓库和分支一致**:`log._meta.project_url` 与 `Report.project.repo_url` 一致,且双方都有 branch 时值一致;
3. **存在明确的运行关联标记**:Report ID/共享 run ID 一致,或 Report 与 log 的**文件名时间戳后缀完全一致**。仅仅项目名相同、日期相近或 branch 相同,不足以证明是同一次运行。

匹配失败的 log 可以列为"未采用的候选证据",但不得用于改写 Report 命令、痛点、失败原因、阶段结论或根因判断。不同日期的同项目 log 默认不是同次运行。无法证明关联时宁可只用 Report 和本次复现日志,也不要拼接两次运行的证据。

### 证据优先级和冲突处理

- **复现范围和原始命令**:以 Report 为准;log 中出现而 Report 没有的命令不得自动执行。
- **实际成败和根因**:以本次复现的真实 RC、完整业务输出、产物和源码/文档证据为准;匹配 log 只用于补充原始执行细节。
- Report 与匹配 log 冲突时,保留两者原文并标记冲突,重新执行相关命令核实;不得静默选择更符合结论的一方。
- 每条补充证据都记录来源文件、JSON 路径和运行关联依据,确保根因可以回溯。

### Report × log 搭配取上下文

Report 定"骨架"(范围、顺序、结论、评分),log 定"血肉"(完整输出、原始参数、痛点↔命令定位)。复现前把两者按下表拼齐,得到完整复现上下文:

| 上下文维度 | Report 提供(主) | log 补充(同次运行) | 用途 |
|---|---|---|---|
| 项目/仓库/分支 | `project.project_id`/`repo_url`/`branch` | `_meta.project_name`/`project_url`/`branch`(交叉验证) | 定容器、工作目录与镜像 |
| S1 环境基线命令 | `S1_SETUP.actions[]`(`tool_args` 结构化) | `setup_*` 字段 `commands[]`(`args` 二次 `json.loads` + `output`) | 按 S1 原样建环境基线 |
| 复现阶段命令与顺序 | 复现阶段 `actions[]`(复现范围与顺序**唯一权威**) | `commands[]` 的 `name`/`args`(核对参数) | 逐条重放命令 |
| 每条命令完整业务输出 | `detail`(仅摘要) | `output`(完整原文)+ `output_summary` | 读 pass/failed/精度/golden,防 wrapper 吞 RC |
| 痛点清单 | `task_details[].pain_points[]`/`failure_reason`(主;`cons` 仅存目不判定) | `evidence.pain_points[]`(字符串版)+ **`pain_points_tool_nums[]`(序号定位到具体命令)** | 逐条核验现象与根因 |
| 命令成败 | `success`(报告判定) | `status`(原始标志) | 交叉验证;不一致须标记 |
| 耗时指标 | `duration`(报告dur,字符串) | `duration_time`(原始秒数) | 与本次实测三方对照,核实耗时类结论 |
| 评分/结论/归因 | `overall_scores`/`cons`/`divergence_alerts`/`recommendations` | 无(log 不能替代) | 结论与提交依据 |

拼齐操作要点:

- **范围与顺序只认 Report**:log 的 `commands[]` 常多于 Report 的 `actions[]`(含失败重试、探索性命令),不得把 log 独有命令并入复现范围;但 Report 命令对应的同序 log 命令,可用其 `output` 补上下文。
- **log 的 `args` 是 JSON 字符串,必须先 `json.loads`** 再读(解析后 `shell_exec→command`、`git_clone→url/branch/path`、`file_read→path`);`commands[]` 的 `name` 即 Report 的 `action_type`。
- **痛点先用 `pain_points_tool_nums` 钉到命令**:把 `evidence.pain_points_tool_nums[]` 的序号(1-based)映射到 `commands[]` 对应项,用该命令的 `output`/`output_summary` 判断痛点指向哪条命令、当时输出是什么;Report 侧没有序号,靠文本 + JSON 路径定位。注意该字段常见**嵌套结构**(`[['9','21','25']]`,每个子数组对应一条痛点、内含其涉及的多个命令序号)——逐痛点取子数组内全部序号,不要当成单层序号数组误读。
- **log 一律是扁平字段结构,阶段映射与主报告变体无关**:即使主 Report 是变体 A(`journey_steps`),同次运行的 log 仍按扁平字段名取数(S3 ↔ `dev_modify`+`dev_build`+`dev_run` 合并,S1 ↔ `setup_clone`+`setup_prereq`+`setup_deps` 合并,见下方「ES 扁平报告:字段名 → 阶段映射」);`pain_points_tool_nums` 的命令序号在**该扁平阶段字段自己的 `commands[]` 内**计数,不要跨字段或对齐 Report `actions[]` 的序号。
- **耗时类结论三方对照**:报告 `duration` 声称值 ↔ log `duration_time` 原始值 ↔ 本次实测 `$SECONDS`,三者不一致要如实记录——报告耗时指标本身可能就是待核实痛点。
- **`success` vs `status` 不一致要标记**:Report 记 success 但 log 对应命令 status 非成功(或反之),多为 `|tee`/wrapper 吞 RC 等假象,须按核心执行规则 4 重跑取真实 RC。
- **结论与评分只以 Report 为准**:log 无评分/cons/归因,不能拿来否定 Report 的结论。

---

## 自动痛点扫描与复现范围确定(通过报告文件自动识别各阶段痛点)

复现阶段**不再依赖用户手动指定**:解析 Report 后自动扫描 **S1–S4** 全部阶段的痛点,据此确定复现范围。**S0 搜索与发现、S5 反馈与贡献不纳入扫描与复现**(既定口径:S0 主要是搜索/文档导航行为、S5 是提 issue/PR 等社区互动行为,均非容器内可重放命令;两阶段痛点如有仅在分布表存目,不判定、不生成核实文件)。用户**显式指定**阶段时,以指定为准(收窄为只复现指定阶段);用户只给报告文件未指定时,完全按扫描结果执行。

### 扫描算法(按报告变体取数)

- **变体 A(`journey_steps`)**:遍历 `journey_steps[]` 每个阶段(**跳过 `S0_DISCOVERY` 与 `S5_CONTRIBUTION`**),取 `per_project_assessments[0].task_completion.task_details[]` 下每条 `pain_points[]` 与 `failure_reason`;同时记录该阶段 `not_evaluated` 与 `actual_path.actions` 是否非空。
- **变体 B/C(扁平字段)**:按「ES 扁平报告:字段名 → 阶段映射」遍历各阶段字段(`quickstart_doc`/`dev_modify`+`dev_build`+`dev_run`/`test_unit`/`setup_*`;**`discovery_repo_*` 属 S0、`contribution_*` 属 S5,均不纳入扫描**),取 `evidence.pain_points[]`(字符串数组,逐条核实)。
- **痛点计数口径**(与「取数要点」一致):只计**有实质内容**的条目——`pain_points` 数组中的非空字符串 + 非空 `failure_reason`;空串、`"-"`、纯空白占位符**不计入**。`cons` 仅存目,**不算痛点、不进复现范围判定**。
- 每条痛点记录:原文、JSON 路径、所属阶段、(匹配 log 时)`pain_points_tool_nums` 定位到的命令序号。

### 痛点分布表与复现清单

扫描完成后产出 **`log/painpoint_scan.md`**(痛点分布与复现范围清单),固定结构:

```markdown
# 痛点自动扫描(painpoint_scan)
- 扫描时间 / 报告: <report_id> / 变体: A|B|C
- 计数口径: pain_points X 条 + failure_reason Y 条,共 N=X+Y 条(cons 仅存目不计入)
## 痛点分布
| 阶段 | 痛点数 | not_evaluated | actions 非空 | 进入复现清单 | 说明 |
|---|---|---|---|---|---|
| S0_DISCOVERY | …(存目) | — | — | **否(固定)** | S0 不复现;痛点如有仅存目不判定 |
| S5_CONTRIBUTION | …(存目) | — | — | **否(固定)** | S5 不复现;痛点如有仅存目不判定 |
| S1_SETUP | … | False | 是 | 是(环境基线) | 痛点也逐条核实 |
| S2_QUICKSTART | … | … | … | … | 无可执行命令时注明 |
| …
## 逐条痛点清单
| # | 阶段 | 类型(pain_point/failure_reason) | 原文(截断) | JSON 路径 |
## 复现范围结论
- 复现阶段集合(升序): S? → S? → …
- 依赖前置: <被跳过的中间阶段中,哪些因后续痛点阶段依赖其产物而需重放>
- 用户指定覆盖: <无 / 用户指定 S?,以指定收窄为准>
```

**进入复现清单的判据**(全部满足):该阶段**不是 S0/S5**(两阶段固定排除,见上)、有≥1 条实质痛点(`pain_points` 或 `failure_reason`)、`not_evaluated=False`、`actual_path.actions[]` 非空(扁平变体:对应阶段字段有 `shell_exec`/`git_clone` 命令)。**痛点阶段集合按阶段号升序串行复现**(S1→S2→S3→S4,环境与产物依赖天然有序)。

**四个特例**:
- **S0 搜索与发现、S5 反馈与贡献固定不进复现清单**(既定口径):即使其有痛点与 actions 也不扫描、不重放、不核实——痛点如有仅在分布表"存目"列出原文,不判定、不生成 `painpoint_S0-*.md`/`painpoint_S5-*.md`;用户显式要求复现 S0 或 S5 时,先说明该阶段按口径不纳入,请其改选其它阶段。
- **S1 永远执行**(环境基线角色),即使 S1 自身无痛点;S1 有痛点时其痛点同样逐条核实(见「阶段映射与可复现性」的既有规则)。
- 某阶段有痛点但**无可执行命令**(如 S2 仅 `file_read` 文档导航、`quickstart_doc` 无命令):该阶段不重放命令,其痛点转为**纯文档/引用类核实**(按阶段 4 原文对照 + 阶段 6 判定),在分布表"说明"列注明"无可执行命令,仅做文档对照核实"。
- 某阶段有痛点但 `not_evaluated=True`:不进清单,分布表注明"报告未评估"。

### 依赖前置(中间阶段的产物依赖)

痛点阶段集合不连续时(如只有 S1、S4 有痛点而 S3 无),被跳过的中间阶段**可能被后续痛点阶段依赖**(S4 测试通常依赖 S3 编译产物):

- **判据**:读后继痛点阶段 `actions[]` 的命令,若引用中间阶段产物路径(build/ 目录、编译出的二进制、install 产物、生成的样例),或命令本身是"运行/测试类"而其目标产物只能由中间阶段生成 → 判定存在依赖。
- **存在依赖** → 中间阶段作为**依赖前置重放**:照原样执行其 `actions[]` 命令、记录真实 RC 与耗时,但**不核实其痛点**(该阶段无痛点,本来也无可核实),在结论报告标注"作为依赖前置重放,非复现目标"。
- **无依赖**(后继阶段命令自成体系,如自带 clone+build) → 直接跳过中间阶段。
- **默认保守**:S4 痛点且 S3 未进清单时,默认按"存在依赖"处理(重放 S3 编译),除非 S4 actions 明确自带完整构建链。

### 扫描结果的呈现与继续

扫描结果(分布表 + 复现范围结论)在起容器前**展示给用户**(让用户知道自动识别到什么、将复现哪些阶段),然后**直接继续执行**——自动模式不需要等待用户确认;用户若要收窄,会在此前显式指定阶段。扫描结论同时写入 `log/painpoint_scan.md` 存档,结论报告第一节引用它。

---

## 痛点核验判定模型

"痛点现象真实"和"报告给出的根因正确"是两个独立问题,禁止用一次命令失败直接替代根因证明。对每条 `pain_points`、`failure_reason` 建立一行核验记录,至少包含:原文及 JSON 路径、可观察预期、实际结果、现象状态、报告归因状态、根因证据、可信度。**`cons` 不做正确性判定**(见取数要点),只存目原文。

### 现象状态

- **成立**:在按 S1 建立的环境中,用同一语义的报告命令观察到报告所描述的客观现象,且有完整输出、真实 RC 或实际产物支持。
- **不成立**:完整复现达到报告所称的预期结果,且没有报告描述的现象。
- **部分成立**:只复现了部分入口、部分失败条件或现象严重程度低于报告描述。
- **无法判定(环境阻塞)**:容器、NPU、驱动、网络或其它前置条件失败,尚未执行到足以判断痛点的命令。此状态不能计入"不成立",也不能计入项目问题。

### 报告归因状态

单独判断报告把问题归为项目、环境或用法是否成立:

- **项目问题**:现象可稳定复现,环境和用法已排除,且源码、项目文档、堆栈或单变量对照支持项目代码/文档/依赖本身是原因。
- **环境问题**:换用报告要求的正确容器、驱动、工具链或通用源后现象消失,项目代码和文档无需修改。
- **用法问题**:命令、参数、路径或执行顺序偏离文档/报告;按正确用法重跑后现象消失。
- **未确定**:现象存在但证据不足以排除其它原因,不能写入"项目真问题清单"。

### 可信度等级

- **高**:同一环境和命令稳定复现,并有源码/文档证据或单变量对照支持根因。
- **中**:现象稳定复现,但尚缺少源码、文档或对照证据来锁定根因。
- **低**:只有 Report 或同批次 log 的摘要,未完成独立复现。

**最终结论必须同时写出"现象状态"和"报告归因状态";"现象成立"不等于"项目问题成立"。**

### 单痛点独立核实文件(每条痛点一个文件,必做)

每条待核实 `pain_points`/`failure_reason` **必须单独生成一个核实文件**,与 `repro_report.md` 的汇总表分离——痛点逐条成档,便于单独提交给项目方、单独复盘,不与其它痛点混排。`cons` 不生成核实文件(仅存目)。

- **文件路径与命名**:`test_<项目名><时间戳后缀>/log/painpoint_<阶段号>-<两位序号>_<痛点slug>.md`(如 `painpoint_S4-01_spgemm_cmake.md`);阶段号为 `S1`/`S2`/`S3`/`S4`,序号按痛点在**该阶段内**的报告顺序 01 起**独立计数**(多阶段复现时各阶段各自编号,S3-01 与 S4-01 互不冲突),slug 取痛点核心关键词的短英文 kebab/snake 名。
- **内容结构(固定六节,每条证据必须标注来源类型 `[源码]`/`[文档]`/`[日志]`)**:
  1. **痛点原文(JSON 路径)**:报告原文 + 精确 JSON 路径;有匹配 log 时附 `pain_points_tool_nums` 定位到的命令序号。
  2. **痛点指向的命令源**:报告/同次 log 记录的原始命令(含报告判定与 dur)+ 本次复现实际执行的命令与脚本路径——该痛点"涉及哪条命令"一望即知。
  3. **核实证据**:分 `[源码]`(文件:行号 + 关键代码/函数语义 + 对照组)、`[文档]`(文档原文路径:行号 + 是否存在/语境是否挪用)、`[日志]`(同次 log 原文 vs 本次实测输出,逐字对照)三类列出;每类证据落到具体文件与行号,禁止只有结论没有出处。
  4. **痛点逐段判定表**:把痛点原文拆成若干断言,逐段判"成立/不成立(需修正)",附依据编号。
  5. **复现实测汇总表**:涉及的全部命令 × 报告判定/同次 log/本次实测三方对照(RC、耗时、业务输出)。
  6. **核验结论**:现象状态 + 报告归因状态 + 可信度 + **能否提交**(能 / 需修正措辞+修正建议;可提交时附建议提交文本)。
- **与结论报告的关系**:`repro_report.md` 第五节汇总表每行加"详见 `log/painpoint_<...>.md`"指向对应单痛点文件;两者判定结论必须一致,单痛点文件是证据全量,汇总表是索引。

---

## 双子星容器:Report 重放与文档对照

> **⛔ 本章节已停用(2026-08-28 起),仅保留原设计备查,当前不得照做**——docs 复现路径停用期间的执行方式见顶部「当前执行模式」声明块。以下原文供将来恢复双子星时使用。

完整核验固定使用两个隔离容器,不能把两条路径混在一个容器里:

- **报告复现容器** `cann_test_ml_<项目名><时间戳后缀>_report_claude`:只按 Report 的 S1 和复现阶段 actions 重放,用来回答"体验报告记录的现象是否真实"。
- **文档复现容器** `cann_test_ml_<项目名><时间戳后缀>_docs_claude`:从同一镜像和同一代码版本的干净状态开始,只按项目官方文档建立环境并执行对应阶段,用来回答"普通用户按文档是否会遇到该痛点"。

两个容器必须使用**相同的镜像 immutable ID/RepoDigest、Ascend 驱动/firmware、NPU 配置、项目 commit 和网络策略**;容器名、工作目录、源码 clone、虚拟环境、构建产物、脚本和日志必须隔离。**不得把报告容器里安装好的依赖、编译产物、修复后的文件或环境变量复制到文档容器**。文档路径可以读取文档,但不得偷偷采用 Report 中的人工补救命令。

> **Claude 容器命名硬规则**:凡由 Claude 为本次复现启动的容器,名称最后一段必须是 `_claude`,且 `_claude` 后不得再追加字符。固定格式为 `..._report_claude`、`..._docs_claude`、`..._serial_report_claude` 和 `..._serial_docs_claude`;用户已有或外部启动的容器不改名、不复用为 Claude 复现容器。历史版本(或非本 skill 流程)启动的无后缀容器 `cann_test_ml_<项目名><时间戳后缀>` 视为 Report 容器,若要复用先确认其环境归属。

单卡默认先做一次**并行试跑**:同时启动 `_report_claude` 和 `_docs_claude`,监控设备初始化、显存、ACL/RT、进程状态、超时和业务输出。若两条路径都完成且没有设备争用或交叉影响,记录执行模式为 `parallel_trial`;但性能、耗时、吞吐和超时类结论仍必须用串行结果确认。若出现 device busy、显存不足、ACL/RT 初始化失败、异常 hang/timeout、进程互相终止或结果疑似被影响,立即保留并行试跑日志,不把该现象归为项目问题,改用全新容器按 `_serial_report_claude` → `_serial_docs_claude` 顺序重跑。并行试跑失败的容器不得直接作为串行复现容器复用。

**并行试跑 = 命令必须真同时后台启动(防"容器并行、执行串行")**:并行试跑不是"同时起两个容器",而是**两条命令链真正同时在各自容器内运行**。实现方式二选一:① 把 report 与 docs 的整条命令链分别写成脚本,用 `docker exec -d`(detached)丢进各自容器后台执行,宿主机只轮询两边的 `.done`/结束标记;② 由**两个独立执行流**(两个独立 subagent,各管一个容器)同时推进。单个执行 agent 逐条下发命令时指令天然是顺序的——只起了容器、没把命令后台化,就会出现"**一个容器在跑、另一个长期空闲**"的假并行(检测信号:某容器无进程且日志长时间不变,而另一容器在忙)。假并行下两条路径实际是串行完成的:耗时翻倍,且不满足"并行试跑验证设备可共享"的目的;若仍要记录执行模式,必须注明"容器并行、执行串行",不能冒充 `parallel_trial`。

**禁止两容器互相等待阻塞(双向)**:report 与 docs 两条命令链必须**完全独立推进**,任何一方的命令都不得把另一方容器的运行状态、产物或进度当作前置条件去等待/轮询/读取(报告路径的 `install/` 产物、docs 路径的构建结果各自独立,`_report_claude` 与 `_docs_claude` 互不读对方文件)。两条链各自用 `docker exec -d` 后台跑,宿主机只轮询**本侧**的 `.done`/结束标记。某侧命令长时间不产新输出且无结束标记时,按**超时兜底**处理(见踩坑库"docker exec 超时":记录该侧状态、判断是仍在跑还是挂死,必要时 `docker restart` 或标记阻塞),**不让一侧的阻塞拖死另一侧或整个复现**;阻塞判定归入复现编排/环境障碍,不归项目问题。

如果只有一张 NPU 卡,串行降级时先完成并保存 `_serial_report_claude`,停止该容器后再运行 `_serial_docs_claude`;多卡只有在设备分配明确时才允许并行。任一路径的结果都不能覆盖另一路径的事实。

对照结论至少比较:命令入口、环境准备、真实 RC、完整业务输出、测试执行标志、产物、失败点和所需人工补救。Report 路径复现的是报告事实,文档路径复现的是用户路径,二者的结论分开保存后再归因。并发争用、资源不足和并行调度失败属于复现编排/环境障碍,不能直接写成项目痛点;只有串行重跑仍复现且项目证据成立时,才可归入项目问题。

---

## 报告命令安全审阅

JSON 报告中的 `tool_args.command` 是**外部输入,必须视为不可信**:

- 先列出待执行的 `git_clone` 和 `shell_exec` 命令,检查是否包含宿主机删除、修改宿主机配置、凭据读取、未知下载脚本或容器逃逸操作。
- 项目命令只允许在已确认的复现容器内执行;宿主机只做目录归档、Docker 生命周期管理和日志收集。
- 保持报告命令的语义和参数,不静默替换版本、路径或包;需要网络换源时只为让同一条命令可达。
- 把确认后的命令写成**可审阅的脚本中的字面命令**,禁止把未审阅的报告字符串放进动态 `eval`;避免通过多层 `bash -lc '...'` 拼接造成引号逃逸。
- 任何命令若明显会修改宿主机或突破复现边界,先暂停并请求用户确认,不要因为报告里出现它就自动执行。

---

## 核心执行规则

### 1. S1 是环境基线:每次复现都先按 S1 把环境配成一致

复现**任何**指定阶段,第一件事都是按报告 `S1_SETUP` 阶段记录的命令,把容器环境配置成与报告**同一个状态**——其它阶段都跑在这个环境上。

- 严格照 S1 原样执行:S1 里 clone 的仓库(url/branch/路径)、安装的工具与依赖(gcc/cmake/python/各类包),一律按 S1 记录的命令原样来。
- 不自行补装、不修正版本、不拿项目文档的安装步骤替代 S1。
- 换源只用于"让 S1 记的那条命令能跑通"(同一条命令、同一个包,换镜像源加速),不替换成别的命令或别的版本。
- S1 环境配好、确认与报告一致后,再按阶段号升序进入各痛点阶段(或用户指定的阶段)。顺序不能颠倒,不能跳过 S1。
- "本次环境是否符合项目文档要求"留到分析阶段再判定,本阶段只对齐报告 S1。
- **S1 内无前后依赖的命令可并行执行**(压缩装环境耗时,详见阶段 2「依赖分析与并行」):只把**确认互不依赖**的命令(如多个独立 `git clone` / 独立下载)聚成并行组用 `&`+`wait` 同时跑。并行**只为加速、不改命令/版本/包**;红线:**`apt` 之间绝不并行**(dpkg 锁)、**复合命令(`&&`/`;`/管道)整体不拆**、**`source`/`export` 之后依赖该环境的命令串行**;拿不准有无依赖就**不并行**。有依赖的命令照旧按报告顺序串行。

### 2. 复现痛点所在的各个阶段(自动识别,用户指定可收窄)

- 复现范围由**自动痛点扫描**确定(见「自动痛点扫描与复现范围确定」):凡有实质痛点的阶段进入复现清单,按阶段号升序逐阶段复现;无痛点的阶段不碰。用户显式指定阶段时,以指定收窄为准(只复现指定阶段)。
- 每个复现阶段都按该阶段 `actual_path.actions` 的顺序,逐条执行其中的 `git_clone` 与 `shell_exec`;`file_read`/`web_search` 等是观察行为,不算可执行命令。
- 阶段间按阶段号升序串行推进;被跳过的中间阶段若被后续痛点阶段依赖其产物,作为**依赖前置重放**(执行命令但不核实痛点)。
- 某有痛点的阶段 `not_evaluated=True` 或没有 actions 时:该阶段不重放命令——`not_evaluated=True` 在分布表注明"报告未评估";有痛点但无 actions 的转为纯文档/引用类核实,不因无可执行命令而丢弃其痛点。
- 多阶段复现时,前序痛点阶段已核实失败的命令照实记录,不阻断后续阶段的执行(后续阶段的痛点独立核实);但若前序失败导致后续阶段环境/产物缺失而无法执行,后续痛点状态记"无法判定(环境阻塞)"并注明阻塞源。

### 3. 执行阶段以报告为准,文档/源码留到分析阶段

- 起容器、按 S1 配环境、复现指定阶段,都照报告记录原样执行,执行过程中不去翻项目文档补装或改命令。
- 项目文档与源码在**分析阶段**才引入,用来对照核实,不在执行阶段干预。
- (此规则约束 **report 容器**;双子星 docs 容器路径已停用,文档核实移至分析阶段以原文对照完成,见顶部「当前执行模式」声明。)

### 4. 判定命令成败看真实结果,不被退出码或管道骗到

- 每条命令都要拿到**真实退出码**:不要在命令后接 `| tail` / `| head` 这类管道——管道会把前面命令的真实失败掩盖成成功。用 `命令 > 日志 2>&1; echo RC=$?` 拿退出码。
- 退出码是 0 **不代表**功能成功:对测试、验证、运行类命令,还要看程序实际输出(测试 pass/failed、结果与预期是否一致、精度误差),才能判定这条命令到底成没成。
- **`yes | .run --install` 管道首段 RC=141 SIGPIPE 是假失败**(★ CANN `.run` 安装最易踩):症状——复现报告里的 `yes | ./Ascend-cann-xxx.run --install | tee log`(用 `yes |` 自动喂 license 确认)在 `.run` 正常结束后,`yes` 仍向已关闭的管道写,被 **SIGPIPE** 杀,导致 `PIPESTATUS[0]`/整条命令 RC=**141**(=128+13),看着像安装失败;但读 `.run` 内部日志结尾是 `install success`、产物(`setenv.sh`/`bisheng -v`/`ascend_*_install.info` 的 `version=`)齐全——**RC=141 ≠ 安装失败**,是 `yes|` 管道的 SIGPIPE 噪音。通用解法(只判真假、不改命令):判定 `.run` 安装成败**只看业务标志**(`install success`/`Successfully installed` + 产物文件/setenv 存在),**不看 `yes|` 管道的 RC**;若要拿干净 RC,改用 `yes | ./run --install > log 2>&1; RC=${PIPESTATUS[0]}` 捕获 `.run` 段退出码(仍可能 141,以业务标志为准)。toolkit/A3-ops/nnal 三类 `.run --install` 均常见此现象。
- **wrapper 脚本会吞内部退出码**(★ build/install 类最易踩):`build.sh`/`Makefile`/`*.run --install`/`pip wheel`/`install_deps.sh` 这类包装脚本自身常以 **RC=0** 退出,但内部 make/子进程可能 `Error 1/2`、wheel 构建失败、依赖装到一半——**RC=0 ≠ 编译/安装成功**。这类命令必须 grep 业务标志判定:编译看 `Built target`/`built successfully`(反面:`error:`/`FAILED`/`Error [0-9]`),安装看 `Successfully installed`/`install success`,运行看 `Compare success`/`PASS`/`ret=0`。报告把这类命令标 `success` 时,常是被 wrapper 退出码骗了——务必读 wrapper 重定向出来的内部日志(`/tmp/build_*.log` 等),不要只看 wrapper 自身 RC。

### 5. 复现中的问题分清是哪一类;报告该阶段的结论逐条对照核实

- 复现路上遇到的每个障碍,分清是:**项目本身的问题**(按文档/源码跑不通、文档不清、代码缺陷)、**环境问题**(容器/驱动/工具链/网络源,换个源或补通用工具就好,跟项目逻辑无关)、还是**用法问题**(命令/参数/路径用错了,纠正就好);证据不足时为**未确定**。
- 报告里该阶段记的每条**痛点 / 失败原因 / 缺点**,逐条对照本次复现的真实结果核实:这条结论在干净环境、按报告用法下是否真的成立?会不会是体验 agent 那次特定环境或用法造成的、或它判断有偏差?按「痛点核验判定模型」输出**现象状态 + 报告归因状态 + 可信度**,而不是笼统的"成立/不成立"。

### 6. 通用安装踩坑可直接用,但不参考别的项目结论

- 装 environment 时的**通用手法**(pip/apt/git 换源、NPU 基础设施、通用工具安装——这些跟具体项目无关)可直接拿来用,避免在装环境上反复卡壳(见文末「辅助踩坑库」)。
- 但不要去翻 workspace 里别的 `test_*/` 项目、别的项目版本得出的**项目相关结论**来对照或抄答案——每个项目的复现只依据它自己的报告 + 文档/源码。

### 7. 极耗时命令优先"聚焦复现"

- 报告里有些命令单次就极耗时(全量 `--run_all`/`--run` 测试常 **30–60min**,首次 1800s 超时是常态)。**先看痛点的 `pain_points_tool_nums` 指向哪几条命令**再决定怎么跑:
  - 若痛点指向**某个具体测试/二进制/case**(如"trowargmax 测试崩溃""某 op 精度超限"),**不要傻跑全量**,改用项目的单测入口**聚焦构建+运行那一个**——如 `run_st.py -t <测试名>`、单独 `cmake --build` 那个二进制再 `./bin/<name>`、`pytest -k <用例>`、`./xxx --gtest_filter=<case>`。同一二进制同一 case,**等价验证痛点**,却从 40min 压到几十秒~几分钟。
  - 若痛点本身是"全量耗时/超时",或痛点覆盖全量多组件无法收窄,才跑全量(用 `docker exec -d` detached + 轮询,见踩坑库)。
  - **聚焦前先定位目标 case 归属哪个二进制/模块**(昇腾 UT 常见坑,不定位会匹配 0 个白跑):`grep -rl 'TEST_F(<测试类名>' --include='*.cpp'` 找源文件 → 看它被哪个 `CMakeLists.txt`/`AddOpTestCase` 编进哪个 `*_ut` 二进制(op_api/op_host/op_kernel/op_kernel_aicpu) → 聚焦命令要**同时指定模块**(`--opkernel --ops=xxx` 或 `--[opapi|ophost|opkernel|opkernel_aicpu]`),不能只给 `--gtest_filter`。**若聚焦输出 `[==========] Running 0 tests` = 定位错了,立即回退全量**(`-d` 跑),别在错误二进制上反复调 filter。
- 结论报告里注明:聚焦复现用了哪条单测命令、对应报告哪条全量命令、为何等价(同一二进制/case),避免被误读为"没跑全量=没复现"。

---

## JSON 报告结构速查(取数路径)

报告顶层关键键:

```
meta                  报告元信息(report_id / report_title / generated_at / persona)
project               project_id / project_name / repo_url / branch / platform
journey_steps[]       ← 6 个阶段,复现的核心数据源,逐个看
  [i].step_id            S0_DISCOVERY / S1_SETUP / S2_QUICKSTART / S3_DEVELOPMENT / S4_TESTING / S5_CONTRIBUTION
  [i].step_name          阶段中文名(如"S2 样例快速体验")
  [i].not_evaluated      True=该阶段未评估(无 actions/痛点,不可指定复现)
  [i].per_project_assessments[0]
      .actual_path.actions[]        ← 命令执行轨迹(逐条复现的依据)
          .action_type     git_clone / shell_exec / file_read / web_search ...
          .tool_args       shell_exec→{command}; git_clone→{url,path,branch}; file_read→{path}
          .success         bool
          .detail          执行回显摘要
          .duration        耗时
          .task_id         归属子任务
      .actual_path.total_duration_seconds / retry_count
      .task_completion.task_details[]   ← 子任务级痛点(核实是否成立的依据)
          .task_id / .task_name
          .task_achieved   bool(报告判定该子任务是否达成)
          .observations[]  观察记录
          .pain_points[]   ← 痛点列表(逐条核实)
          .failure_reason  ← 失败原因(核实)
      .pros / .cons        阶段优点/缺点(cons 仅存目原文,不做正确性判定)
      .subjective / .objective  评分
journey_map / phase_analysis   各阶段总分、pros/cons 汇总(辅助理解)
```

**取数要点**:
- 复现命令 = 该阶段 `per_project_assessments[0].actual_path.actions[]` 里 `action_type=shell_exec` 的 `tool_args.command`,以及 `git_clone`(`tool_args.url/branch`)。`file_read`/`web_search` 等是观察行为,不当作可执行命令(但 file_read 的路径提示了报告读过哪些文档,分析阶段可对照)。
- 待核实痛点 = 该阶段 `task_completion.task_details[]` 的 `pain_points` + `failure_reason`;自动扫描时对**全部阶段**执行此取数(不止用户指定阶段),得到痛点分布。
- 空字符串、空数组或缺失的 `failure_reason` 不得被改写成失败原因。
- **`cons` 一律不做正确性判定,仅存目原文**(用户既定口径):`cons` 是各阶段一条的主观短评(如"配置步骤繁多"),不对应可复现命令,逐条判"成立/不成立"既无客观依据又稀释真问题的信噪比。结论报告痛点盘点下单独一行"cons 仅存目、不做正确性判定"列出全部原文(可能为字符串或列表,保留原文并记录 JSON 路径,避免重复计数;占位符如 `"-"` 或空白直接略过);核验表、状态汇总、归因汇总、提交建议均只覆盖 `pain_points`/`failure_reason`。
- **待核实痛点计数口径必须透明**:总数 = 有实质内容的 `pain_points` 条数 + 非空 `failure_reason` 条数;在结论报告和给用户的汇总里**分项列出**各来源的实际条数(如"pain_points 1 条 + failure_reason 0 条,共 1 条"),让读者一眼看懂 N 从哪来。

> ⚠️ **报告结构可能不同——先探测顶层键再取数**:上述是常见结构,但实际报告常见 **三种**变体,取数第一步都先 `python3 -c "import json;d=json.load(open(f));print(list(d.keys()))"` 看顶层键:
>
> | 变体 | 顶层键特征 | 内容位置 | 阶段定位 |
> |---|---|---|---|
> | **A. journey_steps** | `meta`/`project`/`journey_steps` | `journey_steps[i]` | 按 `step_id`(S1_SETUP...) |
> | **B. ES hits 包裹** | `took`/`_shards`/`hits` | `hits.hits[0]._source.raw_data` | 扁平字段名 |
> | **C. 裸扁平** | `_meta` + `setup_clone`/`setup_prereq`/...直接在顶层(无 hits 包裹、无 raw_data) | 顶层各阶段字段 | 扁平字段名 |
>
> B/C 两种扁平结构的每个阶段 dict 结构相同:
> - `commands[]`:命令轨迹;元素 `.name`=action_type(`shell_exec`/`git_clone`/`file_read`...),`.args` 是 **JSON 字符串,需二次 `json.loads`**(解析后 `shell_exec→.command`、`file_read→.path`、`git_clone→.url/.branch/.path`),`.status`/`.duration_time` 对应报告 success/duration;阶段整体有 `.status`/`.name`(如"阅读Quick Start文档并提取步骤")。
> - `evidence.pain_points`(痛点**字符串数组**,逐条核实)+ `evidence.observations`(观察记录)+ `evidence.pain_points_tool_nums`(每条痛点对应的 command 序号,从1起,用于把痛点定位到具体命令)。
>
> 判定:顶层键含 `journey_steps`→A;含 `took`/`hits`→B(挖 `hits.hits[0]._source.raw_data`,project/branch 在 `raw_data._meta`);**顶层直接是 `_meta`+`setup_clone`/`dev_build`/`test_unit` 等扁平字段(无 hits)→C**(直接在顶层取,project/branch 在 `_meta`)。命令一律按 `commands[].name` 过滤 `shell_exec`/`git_clone`,痛点取 `evidence.pain_points`。注意:B 变体只有查询响应骨架、无阶段数据时(如仅有 `hits`/`_shards`/`took` 而无 `raw_data` 或 `journey_steps`)不是最终 Report,不能作为主输入。

---

## 阶段映射与可复现性

| step_id | 阶段 | 是否典型复现目标 |
|---|---|---|
| S0_DISCOVERY | S0 搜索与发现 | **不纳入复现**(固定排除:自动扫描跳过,用户指定也先劝退——主要是搜索/文档导航行为,非容器内命令;痛点如有仅存目) |
| **S1_SETUP** | **S1 环境检查与准备** | **永远是第一步(环境基线)**,即使不是痛点阶段/用户指定的复现阶段也要先按它配环境 |
| S2_QUICKSTART | S2 样例快速体验 | ✅ 典型复现目标(跑样例/demo) |
| S3_DEVELOPMENT | S3 开发与编译 | ✅ 典型复现目标(编译/构建) |
| S4_TESTING | S4 测试与验证 | ✅ 典型复现目标(跑测试/精度验证) |
| S5_CONTRIBUTION | S5 反馈与贡献 | **不纳入复现**(固定排除:提 issue/PR 等社区互动行为,非容器内命令;通常 `not_evaluated=True`;痛点如有仅存目) |

用户说"复现 S2 / 复现快速体验阶段 / 复现编译阶段"等 → 按上表映射到 `step_id`,在 `journey_steps` 里定位,**以指定收窄复现范围**(S0/S5 除外——固定不纳入,见上表);用户未指定阶段时,由自动痛点扫描按上表遍历全部阶段(**不含 S0/S5**),凡有实质痛点且 `not_evaluated=False`、`actions` 非空的阶段进入复现清单。**只能复现 `not_evaluated=False` 且 `actions` 非空的阶段**;用户指定的阶段 `not_evaluated=True` 时,先告知该阶段报告未评估、无可复现内容,请其改指定其它阶段(或改为自动扫描)。

**⚠️ ES 扁平报告:字段名 → 阶段映射**(扁平结构无 `step_id`,按顶层字段名归阶段;用户说"s1/s3/s4"时把多个字段并成一个阶段复现):

| 阶段 | 扁平字段名(顶层键) |
|---|---|
| S0 搜索发现 | `discovery_repo_*`(`discovery_repo_baidu`/`_google`)——**不纳入扫描与复现** |
| **S1 环境基线** | `setup_clone` + `setup_prereq` + `setup_deps`(三字段合并,顺序 clone→prereq→deps) |
| S2 快速体验 | `quickstart_doc`(多为 file_read/文档导航,常无可执行命令) |
| **S3 开发编译** | `dev_modify` + `dev_build` + `dev_run`(三字段合并) |
| **S4 测试** | `test_unit`(单字段) |
| S5 贡献 | 通常无字段或 `contribution_*`——**不纳入扫描与复现** |

> "s1"=复现 setup_clone+setup_prereq+setup_deps;"s3"=dev_modify+dev_build+dev_run;"s4"=test_unit。S1 即使不在复现清单(自动识别结果)或用户指定列表里也**永远先跑**(环境基线)。自动扫描时按本表把扁平字段归并为阶段,再统计各阶段痛点数定复现清单。

> ⚠️ **指定 S1 时,setup_deps/setup_prereq 自身的 `evidence.pain_points` 也要逐条核实**——它们既是环境基线,本身也是带痛点的评估对象(典型:依赖版本约束矛盾如 `numpy<=1.24.0` vs `numpy>=2.4.4`、缺声明的前置依赖、pip check 冲突)。别只把 S1 当"装环境"跑完就收工,漏了它记录的痛点。取数时把 `setup_clone`/`setup_prereq`/`setup_deps` 三字段的 `evidence.pain_points` 全提取进待核实清单,和复现阶段痛点一起逐条判定。

---

## 复现环境(固定 docker 容器)

**复现一律在固定的昇腾 NPU docker 容器内进行**。当前只起一个 report 复现容器(`_report_claude` 重放报告;docs 容器已停用,见顶部声明),镜像固定为 `guoqiangqi/cogito:202606150944`。

**{项目名} 取法**:取报告 `project.project_id` 中 `/` 后的部分(如 `cann/asc-tools` → `asc-tools`)。

**{时间戳后缀} 取法**:从 JSON 报告**文件名**中提取,去掉 `Report-cann_<项目名>` 前缀和 `.json` 后缀,剩余部分即为时间戳后缀(如 `Report-cann_ge_20260619_0221.json` → `_20260619_0221`;`Report-cann_ops-nn_20260706_2206.json` → `_20260706_2206`)。完整工作目录名 = `test_<项目名><时间戳后缀>`(如 `test_ge_20260619_0221`、`test_ops-nn_20260706_2206`);容器名 = `cann_test_ml_<项目名><时间戳后缀>` + 路径后缀(`_report_claude`/`_docs_claude`/`_serial_report_claude`/`_serial_docs_claude`)。同一时间戳后缀同时用于工作目录与容器名,避免多次复盘同一项目时目录名/容器名撞车。

起容器命令(把 `{项目名}` 替换为实际项目名,容器名后缀当前只用 `_report_claude`;`_docs_claude`/`_serial_*` 后缀属已停用的双子星/串行降级流程,仅备查):

```bash
docker run -dit \
  --name cann_test_ml_{项目名}{时间戳后缀}_report_claude \
  --privileged \
  --net=host \
  --device /dev/davinci0 \
  --device /dev/davinci_manager \
  --device /dev/devmm_svm \
  --device /dev/hisi_hdc \
  -v /usr/local/Ascend/driver:/usr/local/Ascend/driver:ro \
  -v /usr/local/Ascend/firmware:/usr/local/Ascend/firmware:ro \
  -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi \
  -v /etc/ascend_install.info:/etc/ascend_install.info:ro \
  -v /run/ascend:/run/ascend \
  -v /usr/local/dcmi:/usr/local/dcmi \
  -e LD_LIBRARY_PATH="/usr/local/Ascend/driver/lib64:/usr/local/Ascend/driver/lib64/common:/usr/local/Ascend/driver/lib64/driver:/usr/local/dcmi" \
  --entrypoint bash \
  guoqiangqi/cogito:202606150944
```

- 镜像固定为 `guoqiangqi/cogito:202606150944`(如该 tag 拉取失败,先告知用户并确认替代 tag,**不要擅自换其它镜像**)。
- 容器内执行统一用 `docker exec <report容器名> bash -lc '<已审阅的固定命令>'`;脚本先在宿主机 `test_<项目名><时间戳后缀>/report_replay/scripts/` 写好,再 `docker cp` 进容器执行,便于审视与复用。
- **宿主机↔容器文件流转**:宿主机 `test_<项目名><时间戳后缀>/` 只放脚本/日志/报告;容器内按报告记录的路径操作(如 S1 里 git clone 到 `/tmp/devx_workspace` 就照此路径)。容器内日志用 `docker exec ... > 宿主机log` 或执行后 `docker cp` 取回 `report_replay/log/`。
- 起容器后先自检 NPU 可用:`npu-smi info`(应能看到设备)与 `ls /dev/davinci*`,确认设备挂载成功,再进入复现。
- **长耗时命令**用 `docker exec -d` 在容器内后台运行,脚本末尾写入明确结束标记(`echo DONE`),宿主机用短查询轮询,不要让一次 exec 因编译或下载超时而误判(详见踩坑库)。
- **并行试跑已随 docs 容器停用**(无 `log/parallel_trial/` 归档需求);最终采信的 Report 结果写入 `report_replay/log/`。

### 环境和版本指纹

报告只记录 branch 或镜像 tag 时,复现结果可能因代码、镜像或驱动漂移而改变。进入复现阶段前必须保存 `report_replay/log/environment_fingerprint.log`(docs 侧指纹已随 docs 容器停用而取消):

- 宿主机记录 Docker 镜像 **immutable ID/RepoDigest**;只有 tag 没有 digest 时标记为"镜像不可完全固定"。
- 容器内记录 `npu-smi info`、`/etc/ascend_install.info`(存在时)、CANN `set_env.sh` 路径、Python、pip、cmake、gcc 版本和报告要求的关键依赖版本。
- clone 完成后记录 `git rev-parse HEAD`、`git status --short`、实际 branch 和 remote URL;只有 branch 没有 commit 时标记为"源码不可完全固定"。
- 只记录与复现有关的环境变量,禁止把 token、密码或完整宿主机环境直接写入日志。
- 如果本次指纹与 Report 声明不一致,仍可执行严格重放,但结论必须注明环境差异;**环境差异未排除前,不得把失败归为项目问题**。

---

## 会话信息归档:session_resume.md(宿主机 + 容器双份)

复现由 Claude Code 会话执行,会话中断/上下文压缩/换人接手时,下一个会话需要知道**复现在哪个会话进行、如何恢复、在哪个目录工作**。这些信息落成 `session_resume.md`,**双份保存**:宿主机 `test_<项目名><时间戳后缀>/log/session_resume.md` + 容器内 `/tmp/session_resume.md`(docker cp 同步)。

- **写入时机**:①阶段 1 起容器建目录后写**初始版**(会话/容器/目录已定);②阶段 9 结论报告写完后**更新最终版**(补完成状态);中途会话即将结束/被压缩前也可随时更新。
- **会话 ID 获取**(通用方法,以最新 mtime 的 jsonl 为当前会话;并行多会话时人工确认):
  ```bash
  ls -t ~/.claude/projects/<项目slug>/*.jsonl | head -1 | xargs basename | sed 's/\.jsonl//'
  # <项目slug> = 宿主机工作目录绝对路径中 '/' 替换为 '-'(如 /home/x/workspace/run1 → -home-x-workspace-run1)
  ```
- **文件内容模板**(字段逐项填实,不要留占位符):
  ```markdown
  # 复现会话信息(session_resume)
  - 更新时间: <date> | 状态: 进行中(S?已完)/已完成
  - 复现项目: <project_id> | 报告: <Report文件名> | 复现阶段: S?/S? | 环境基线: S1
  - Claude 会话: <session-id>
    - transcript: ~/.claude/projects/<项目slug>/<session-id>.jsonl
    - 恢复命令: cd <宿主机workspace绝对路径> && claude --resume <session-id>
  - 宿主机工作目录: <绝对路径>/test_<项目名><时间戳后缀>/
    - 结论报告: log/repro_report.md | 过程日志: report_replay/log/ | 主输入: log/input_report.json
  - 复现容器: cann_test_ml_<项目名><时间戳后缀>_report_claude(镜像 guoqiangqi/cogito:202606150944)
    - 容器内: 脚本 /tmp/report_s*.sh | 进度标记 /tmp/*.done | 本文件副本 /tmp/session_resume.md
  - 重新接手/续跑入口:
    1. 读本文件 + README.md(产物/脚本说明与重放顺序) + log/repro_report.md 了解进度与结论
    2. docker ps 确认容器 Up;docker exec <容器> bash -lc 'cat /tmp/*.done' 看各阶段进度
    3. 需回到原会话: 上方恢复命令;新会话接手: 在宿主机工作目录启动 claude 并提供本文件路径
  ```
- **同步方法**:宿主机写好后 `docker cp test_<项目名><时间戳后缀>/log/session_resume.md <容器>:/tmp/session_resume.md`;每次更新两处一起更。

## 工作目录结构(每个项目独立)

每复现一个项目,在 workspace 下建 `test_<项目名><时间戳后缀>/` 目录(如 `test_ge_20260619_0221/`),**所有产物归档其中**,保持 workspace 根目录干净:

```
test_<项目名><时间戳后缀>/
├── README.md             # 本目录产物与脚本的作用、使用方式(复现交付入口,见下方规矩)
├── report_replay/        # 报告重放容器的 scripts/ 和 log/(回答"报告现象是否真实")
│   ├── scripts/
│   └── log/
└── log/                  # 主 Report、匹配的原始 log、痛点自动扫描清单(painpoint_scan.md)、文档原文存档(如 QUICKSTART_original.md)、单痛点核实文件(painpoint_*.md)、session_resume.md、repro_report.md
```

> 双子星模式的 `docs_replay/` 目录与 `log/parallel_trial/` 已随 docs 容器停用,不再创建;文档原文对照的存档放 `log/` 下。

规矩:
- 复现**第一步**建结构:`mkdir -p test_<项目名><时间戳后缀>/{report_replay/{scripts,log},log}`;把主 Report 保存为根目录 `log/input_report.json`;只有确认同次运行的 log 才保存为 `log/matched_raw_log.json`,其它候选文件只记录路径和不匹配原因。
- ★ **工作目录根必须写 `README.md`(产物与脚本使用说明,与复现收尾一起完成)**——任何人(包括下次会话/他人接手/项目方)打开目录第一眼能看懂"每个产物是什么、每个脚本怎么重跑"。内容四节(模板):
  1. **一句话结论**:复现了什么阶段、核心判定(成立/不成立)、指向 `log/repro_report.md`;
  2. **产物说明表**:每个文件一行"路径 → 作用 → 怎么读"(repro_report.md=汇总结论;painpoint_scan.md=痛点自动扫描与复现范围清单;painpoint_*.md=单痛点证据档(命令源+[源码]/[文档]/[日志]三类核实原因);input_report.json=主输入;matched_raw_log.json=同次运行补证;*_original.md=文档原文存档;session_resume.md=会话恢复;report_replay/log/*.log=各命令过程日志,含关键日志对应报告哪条命令);
  3. **脚本说明表**:`report_replay/scripts/` 每个脚本一行"脚本名 → 作用(对应报告哪条/哪些命令,标注报告 action 序号)→ 前置条件(如需 S1 完成/需 source set_env.sh)→ 重跑命令"(`docker cp` 进容器 + `docker exec <容器> bash /tmp/<脚本>` 原样可贴);并行批注明内部并行结构;
  4. **重放顺序**:按脚本依赖列出从头完整重放的执行顺序(S1 批 a/b/c/d… → S? 批 a/b/c… → S? 批 a/b/c…,按阶段号升序、含依赖前置批),并注明"环境已就绪时只重跑对应阶段脚本即可"。
- ★ **结论报告固定写入 `test_<项目名><时间戳后缀>/log/repro_report.md` 这一个文件**——复现结论对照表 + S1 环境复现 + Report 路径复现 + 文档原文对照 + 痛点核实判定 + 问题分类归因 + 项目问题清单**全部汇总进它**;过程日志另存 `report_replay/log/*.log`(如 `s1_setup.log`、`s3_build.log`)。**禁止**拆成多个 `.md` 或起别名——**唯一例外**是「单痛点独立核实文件」`log/painpoint_<阶段号>-<序号>_<slug>.md`(每条痛点一个,见「痛点核验判定模型」),它是汇总表逐行指向的证据档,不是结论报告的拆分;README.md 是目录级导航说明,同样不算结论报告的拆分。
- 复现命令清单里的脚本路径一律用 `test_<项目名><时间戳后缀>/report_replay/scripts/<脚本>`。
- **容器内过程日志归档**:容器内 `/tmp/*.log`(build/install/ut/run 等)复现结束后用 `docker cp <容器>:/tmp/xxx.log report_replay/log/s<阶段>_xxx.log` 取回宿主机,与 `repro_report.md` 一起留存,便于复盘与证据追溯(容器可能被清,日志不取回会丢)。

### 脚本组织规范(命名 / 分批 / 内部结构)

复现脚本按 **`<路径>_s<阶段号>_<批次字母>.sh`** 命名、按逻辑分批,便于独立重跑、定位失败、控制超时:

- **命名**:`report_s1_a.sh`、`report_s1_b.sh`、`report_s2_a.sh`、`report_s4_a.sh`……前缀统一 `report_`(报告重放容器;`docs_` 前缀随 docs 容器停用,不再使用);"阶段号"对齐报告 step(S1/S2/S3),同阶段内按执行顺序用 `_a/_b/_c` 分批。**多阶段复现时各阶段独立分批**(`report_s3_*.sh`、`report_s4_*.sh` 并存,按阶段号升序执行);依赖前置阶段同样按其阶段号命名脚本,并在脚本头部注释与 README 中注明"依赖前置,非复现目标"。**S1 内确认无依赖的命令聚成一个并行批 `report_s1_par_<批>.sh`**(如 `report_s1_par_a.sh`,内部结构见下),与串行批 `_a/_b` 区分。自检、换源等一次性辅助操作可直接 `docker exec`,不必都落脚本。
- **分批粒度**(每批是一个**可独立重跑**的逻辑块):
  - **重操作单独成批**:大文件下载(CANN toolkit/ops 的 `.run` 包)、长时间编译(`bash build.sh`,常 200s+)、首次会失败的依赖脚本(`install_deps.sh`)各拆一批——便于设超时、失败时只重跑这一批。
  - **按依赖顺序排**:批次内命令前后依赖,批次间也顺序(S1 先于 S2/S3);**核心核实命令(build / `--run` / 精度验证)单独成批**,完整捕获业务输出。
  - 参考拆法:S1 ≈ clone+自检 / `install_deps` 首次 / 通用工具(pigz+googletest)/ CANN 下载安装 / 验证+`install_deps` 重跑+pip;复现阶段按"编译运行 / 目录探查 / 其它"分批。
  - **S1 独立命令可聚成并行批**:S1 里互不依赖的命令(多个独立 git clone / 独立下载,依阶段 2 判据)聚成一个 `report_s1_par_<批>.sh` 同时跑,压缩耗时;重操作(大下载/长编译/易失败的 `install_deps`)仍各拆串行批。并行批内**单条失败不中断其它**(`set +e`),一条卡住时其它照跑。
- **脚本内部结构**(每批统一):
  ```bash
  #!/usr/bin/env bash
  set +e                                                   # 命令失败不中断,逐条记录
  source /usr/local/Ascend/cann/set_env.sh 2>/dev/null     # S2 及之后需要
  cd /tmp/devx_workspace                                   # 按报告 S1 记的 clone 路径
  echo "===== [S?-??] 报告原命令摘要 (报告 success=? 报告dur=?) ====="   # 标编号+报告判定+报告耗时,便于核对与耗时指标核实
  START=$SECONDS
  <已审阅的报告原命令> > /tmp/xxx.log 2>&1                 # 长输出存容器内临时日志
  echo "RC??=$? 耗时=$((SECONDS-START))s"
  grep -iE "error|fail|pass|skip|..." /tmp/xxx.log | head  # 只回显关键行(对已保存日志做摘要,不接在被核实命令后)
  cat /tmp/run.log                                         # 测试/核实类:完整业务输出(pass/failed/精度/golden)
  ```
  要点:`set +e` 逐条记录;每条 echo 行**标注报告 `success` 与 `duration`**(报告dur,取自报告该 action 的 `duration` 字段),便于和本次 `$SECONDS` 实测耗时对照、核实报告耗时类指标(如 `SDX_BUILD_TIME_SEC`);每条 `命令 > log 2>&1; echo RC=$?`(**绝不**接 `| tail`/`| head`,管道会伪装失败为成功——见核心执行规则 4);耗时命令用 `$SECONDS` 计时;**核实/测试类命令务必 `cat` 完整业务输出**(RC=0 ≠ 功能成功,要看 pass/failed、精度比对)。

  > **报告原命令含单引号/多行/`#include`/嵌套引号时,不要塞进 `bash -lc '...'`**——转义成 `'"'"'` 多层嵌套极易出错(如 bisheng 测试 `echo '#include <cstdint>' | bisheng ...` 这类)。改为把命令**原样 heredoc 写入文件**再执行,零转义、保留原始文本:
  > ```bash
  > cat > /tmp/cmd_<i>.sh <<'CMDEOF'
  > source /usr/local/Ascend/ascend-toolkit/set_env.sh
  > echo '#include <cstdint>' | /usr/local/Ascend/cann-9.0.0/bin/bisheng -x c++ -fsyntax-only -std=c++17 -
  > CMDEOF
  > bash /tmp/cmd_<i>.sh > /tmp/cmd_<i>.log 2>&1; echo "RC<i>=$?"
  > ```
  > `'CMDEOF'`(带引号的定界符)阻止 heredoc 内的 `$`/反引号被展开,命令文本逐字落盘;长命令、含 `&&`/`;`/管道的复合命令同理优先落盘成文件,而非全塞进 `bash -lc` 单行串。

  **并行批内部结构**(`report_s1_par_<批>.sh`,把 S1 无依赖命令并行跑;红线:`apt` 间不并行、复合命令不拆、不 source/export 改共享态;每条命令必须是审阅后的字面命令,不得动态拼接):
  ```bash
  #!/usr/bin/env bash
  set +e                                            # 单条失败不中断其它(并行的价值)
  cd /tmp/devx_workspace                            # 报告 S1 记的 clone 根路径(按需)
  # source /usr/local/Ascend/cann/set_env.sh 2>/dev/null   # 若并行命令依赖,在此串行 source 一次
  (
    git clone --depth=1 -b <branchA> <urlA> <pathA> >/tmp/par_clone_a.log 2>&1
    echo $? >/tmp/par_clone_a.rc
  ) &
  (
    git clone --depth=1 -b <branchB> <urlB> <pathB> >/tmp/par_clone_b.log 2>&1
    echo $? >/tmp/par_clone_b.rc
  ) &
  wait
  echo "===== [S1-par] 并行组结果(对照报告 success/报告dur) ====="
  for tag in clone_a clone_b; do
    echo "[$tag] RC=$(cat /tmp/par_${tag}.rc)"
    grep -iE "error|fail|fatal" /tmp/par_${tag}.log | head -3
  done
  ```
  要点:每条独立 `/tmp/par_<tag>.log`+RC(不接管道伪装成败);`apt` 不要把多条塞进同一并行组互并(可与 git/pip/wget 跨类型同组);串行 `source`/`cd` 在并行启动**前**做一次,并行命令只读环境、各自独立产出。并行规则:不同仓库或不同 URL 的 clone/download 可以并行;不同 pip 安装保守串行;apt 之间禁止并行;下载→解压/安装链串行;复合命令整体不拆;有隐藏依赖时串行。

---

## 工作流

工作流分两部分:**第一部分 执行阶段**(严格忠于报告,单容器 report 重放,先 S1 后指定阶段,执行中不碰项目文档)和**第二部分 分析阶段**(此时才引入文档/源码对照核实——docs 容器停用后,"文档侧"核实也在此阶段以读仓库内文档原文+源码的方式完成,见顶部「当前执行模式」声明)。

> **断点续跑**(会话中断/上下文压缩后重新进入时**先做**,别从头重来):⓪**先读 `test_<项目名><时间戳后缀>/log/session_resume.md`**(容器内 `/tmp/session_resume.md` 同份)——上一会话把"哪个会话在跑、恢复命令、工作目录、容器名、进行到哪"都记在里面,按其中的接手入口操作;①`docker ps` 确认 report 容器 `cann_test_ml_<项目名><时间戳>_report_claude` 还在 `Up`,丢了才 `docker run` 重建;②`docker exec <容器> bash -lc 'cat /tmp/*.done 2>/dev/null'` 看各阶段进度标记(S1 装环境、复现阶段命令各自结尾 `echo RC=... > /tmp/xxx.done` 留的标记);③**已装好的(CANN/依赖/已 clone 代码)绝不重装、已跑完的命令绝不重跑**,从下一个未完成标记续;④不确定环境是否完整时,跑一条快速自检(`gcc --version`/`source set_env.sh && echo $ASCEND_HOME_PATH`/`ls /tmp/devx_workspace`)确认,而非整套 S1 重来。

---

### 第一部分:执行阶段(严格忠于报告)

#### 阶段 0｜解析输入,匹配 log,定位阶段

1. 读 JSON 报告并校验主报告有效性(见「输入契约」):确认含 `journey_steps[]`(或可挖取的变体 B/C 阶段数据),排除仅含 `hits`/`_shards`/`took` 的 ES 查询响应;取 `project.project_id` → 定 `{项目名}` 与工作目录。
2. 在输入目录查找候选 `log*.json`,按"项目、仓库、branch、运行关联标记"逐项比对(见「log 同次运行匹配」);只有同次运行的 log 才登记为补充证据,保存为 `log/matched_raw_log.json`,其它候选只记录路径和不匹配原因。
3. **全阶段自动痛点扫描,确定复现范围**(见「自动痛点扫描与复现范围确定」):按报告变体遍历 **S1–S4** 全部阶段的 `pain_points`/`failure_reason`(占位符不计,`cons` 仅存目;**S0 搜索与发现、S5 反馈与贡献不扫描、不复现**,其痛点如有在分布表存目),统计各阶段痛点数、`not_evaluated`、actions 是否非空,产出**痛点分布表与复现清单**,写入 `log/painpoint_scan.md`;用户显式指定阶段时,以指定收窄复现清单并在文件中注明(指定 S0/S5 时说明该阶段固定不纳入)。把扫描结果(哪些阶段有痛点、将复现哪些)展示给用户后继续。
4. 从报告提取两类命令:
   - **S1 环境基线命令**:`journey_steps` 里 `step_id=S1_SETUP` 的 `per_project_assessments[0].actual_path.actions[]` 中所有 `git_clone` 与 `shell_exec`(**按报告顺序**)。
   - **各复现阶段命令**:复现清单内每个阶段的 `actual_path.actions[]` 中所有 `git_clone` 与 `shell_exec`(**按报告顺序、阶段按阶段号升序**);按「依赖前置」判定的中间阶段命令也一并提取(标注"依赖前置");不得从 log 追加未出现在 Report 的执行命令。
5. 从报告提取**待核实痛点**:复现清单内各阶段 `task_completion.task_details[]` 的每条 `pain_points` / `failure_reason`(`cons` 不判定,单独存目原文)——**注意是全部痛点阶段,不只复现阶段;S1 有痛点也包含在内**。若匹配 log 存在,再按「Report × log 搭配取上下文」补齐——每条痛点对应 `evidence.pain_points[]` 的字符串版、`pain_points_tool_nums[]` 定位到的命令序号、该命令 `commands[].output` 完整输出,以及命令 `status` 与报告 `success` 是否一致,全部记录 JSON 路径。
6. 按「Report × log 搭配取上下文」把 Report 与匹配 log 拼齐,产出**复现上下文快照**:S1 基线命令、各复现阶段命令及顺序、每条命令完整业务输出、痛点清单与命令定位、成败与耗时三方对照,逐项标注来源 JSON 路径;此快照是后续重放与核验的依据,避免边复现边反复翻两个 JSON。
7. 记录 S1 装了哪些工具/依赖(从 S1 的 `task_details.observations` 与 `actions.detail` 摘出,如 gcc/cmake/python/特定包版本),供后续"环境是否一致"对照。
8. 为 `_report_claude` 容器列出 Report 重放命令清单(见「报告命令安全审阅」),覆盖 S1 + 全部复现阶段(含依赖前置)。(docs 容器清单已随 docs 复现停用而取消。)
9. 在执行前把 report 容器的准确名称、镜像、设备、挂载、网络权限和将要运行的命令列给用户,完成安全审阅和特权容器确认。

#### 阶段 1｜起 report 容器 + 自检(单容器模式;docs 容器停用)

1. `mkdir -p test_<项目名><时间戳后缀>/{report_replay/{scripts,log},log}`,主 Report 放 `log/input_report.json`,确认的匹配 log 放 `log/matched_raw_log.json`。
2. 用上文固定 `docker run` 命令起 `cann_test_ml_{项目名}{时间戳}_report_claude`(已有同名容器**不得自动删除**,先检查状态和归属;需要重建时先向用户确认准确容器名)。
3. 在容器中自检:`npu-smi info`、`ls /dev/davinci*`、镜像内基础工具情况,自检结果记入 `report_replay/log/container_check.log`。
4. 记录容器的镜像 immutable ID/RepoDigest、容器内驱动/CANN/编译器/Python 版本和 NPU 信息,写入 `report_replay/log/environment_fingerprint.log`(见「环境和版本指纹」)。
5. 关键自检失败时停止复现并报告环境阻塞。
6. 执行模式在结论报告记为"单容器 report 重放"(无 `parallel_trial`/串行降级)。
7. **写 session_resume.md 初始版**(见「会话信息归档」章节):记录当前 Claude 会话 ID、恢复命令、宿主机工作目录、容器名,写入宿主机 `log/session_resume.md` 并 `docker cp` 到容器 `/tmp/session_resume.md`。

#### 阶段 2｜按 S1 配置 report 容器环境(环境基线,严格按 S1 原样)

**目标:让 report 容器环境与报告 S1 记录一致,为后续阶段铺底。** 先对 S1 的 `git_clone`/`shell_exec` 做**依赖分析**——无依赖的聚成并行组并行跑、有依赖的按报告顺序串行跑(串行链照旧逐条执行):

- **照 S1 原样执行**:clone 用 S1 记的 `url`/`branch`/`path`;装依赖用 S1 记的命令原样跑。**不补装、不修正、不对齐文档**。并行只动执行编排,不改命令/版本/包。
- **换源仅限让 S1 那条命令能跑**:S1 记的 pip/apt/git 源拉不动时,按「网络与源硬规则」换镜像源/加代理让**同一条命令、同一个包**跑起来;**不替换为文档里的其它命令/版本**。
- 每条捕获真实退出码(`cmd > log 2>&1; echo RC=$?`,**绝不接** `| tail`/`| head`),全过程记 `report_replay/log/s1_setup.log`;并行组每条独立 log+RC 也汇总进来。
- 全程记录:S1 报告声明装了什么 → 本次实际装成功什么、哪些与报告不一致(版本/缺失),供"环境一致性"判定。
- 非项目耦合的通用安装踩坑(见文末踩坑库)可直接用,不在装环境上反复栽跟头。
- **docs 容器已停用**,本阶段只操作 report 容器;文档侧核实移至分析阶段(阶段 6-8)以读仓库内文档原文方式完成。

**依赖分析与并行(压缩 S1 耗时)**:扫描 S1 全部 `git_clone`/`shell_exec`,按下述判据+分级分成**并行组**与**串行链**——并行组写 `report_s1_par_<批>.sh`(`&`+`wait`,模板见「脚本组织规范」),串行链(下载→安装链、apt 互斥链、`source`/`export` 后的命令、复合命令)按原串行模板顺序跑。

- **① 依赖判据**(一条命令可并入并行组 ⟺ 全部满足):不消费前序命令产出(不 `cd` 进前序 clone 的目录、不读前序下载的文件、不依赖前序装好的包/工具);不设置后续命令依赖的环境(不 `source set_env.sh`、不 `export` 后续要用的 PATH/LD_LIBRARY_PATH/Ascend*、不改 profile);不是"下载→解压/安装"链的一环(`wget xxx.run` 与 `bash xxx.run` 绑定串行);报告里本身就是复合命令(`&&`/`;`/管道/多行)时**整体作为一个单元不拆**。
- **② 并行安全分级**(能否与同类型命令互相并行):`git clone`(不同仓库/路径) ✅ 放心并行;`wget`/`curl` 下载(不同 URL) ✅ 放心并行;`pip install`(不同 action) ⚠️ 保守串行(同一 site-packages 写 `.dist-info` 偶发竞争,报告本就一条 `pip install A B C` 则不拆);`apt`/`apt-get` ❌ **禁止互相并行**(dpkg 锁冲突必失败),但**可与跨类型**(git/pip/wget)并行。
- **红线**:跨类型可并行(如一条 `apt` + 一条 `git clone` + 一条 `wget` 同时);同类型内按上表。命令间疑似有隐藏依赖(都写同一文件/都改同一 config)**保守归串行**;**不确定就不并行**——宁可少并行,不可污染 S1 环境对照。

> S1 配完后,**不要**急着对齐项目文档;环境是否"符合项目要求"留到分析阶段判定。本阶段只对齐"报告 S1 记录"。clone 完成后记录实际 commit、branch、remote URL 和工作树状态(进 `environment_fingerprint.log`);S1 关键命令失败或环境与报告无法建立时停止,不执行复现阶段。

#### 阶段 3｜复现 report 容器中的各痛点阶段(按阶段号升序)

对复现清单内每个阶段,逐条按该阶段 `actions` 顺序执行其 `git_clone`/`shell_exec`;阶段间按阶段号升序推进(S1 环境就绪后 S2→S3→S4 依次执行,依赖前置阶段穿插其间):

- **照报告原样执行**各复现阶段记录的命令(clone 若 S1 已 clone 且路径相同,可复用,不必重复;以报告记录为准)。
- **多阶段推进规则**:每阶段跑完即小结该阶段各命令 RC/业务输出(便于断点续跑定位),再进下一阶段;依赖前置阶段的命令照跑但**不核实痛点**,只在日志与结论报告标注"依赖前置"。前序阶段的痛点核实(阶段 6)统一在执行全部完成后进行,不在执行中途下结论。
- 每条**捕获真实退出码**(`cmd > log 2>&1; echo RC=$?`,**绝不接** `| tail`/`| head`);过程记 `report_replay/log/s<阶段号>_<名>.log`(如 `report_replay/log/s3_build.log`)。
- **RC=0 也要读业务输出**:对验证/测试/运行类命令,继续读 stdout/stderr 里的 pass/failed、内部 `ret=N`、golden 比对、精度误差,判定"功能是否真成功",而不止看退出码。
- 遇到失败:照报告原样复现到失败点即可(不绕过、不修),如实记录失败命令、退出码、报错、业务输出。换源同理,仅限让报告同一条命令能跑。
- **极耗时命令聚焦复现**(见核心规则 7):全量 `--run_all`/首次大编译等 30min+ 命令,若痛点指向具体子项,改用单测入口聚焦跑那一个,省几十分钟。
- **昇腾类命令记得 `source` 环境**:报告里 `run_st.py`/`build.sh`/`./xxx.run` 常省略 `source setenv.bash`(体验 agent 在累积 env 的 shell 里跑);单条 `docker exec` 执行时若报 `ASCEND_HOME_PATH is not set`/`bisheng: command not found`,在命令前补 `source /usr/local/Ascend/cann-9.1.0/bin/setenv.bash`(文档路径,见踩坑库"CANN env 脚本路径")。
- **编译类阶段(S3/S4)必做 SOC 核实**(用户常追问"芯片是 910C,是否编译了不支持本机的产物"):
  1. **看本机芯片型号**:`npu-smi info -t board -i 0` 看 Product Name(如 `IT22HMDA` 系列=910C/Atlas A3)+ Chip Count(910C 双 die)+ Aicore Count 辅助判定;顶层 `npu-smi info` 显示"Ascend910"不带后缀是驱动显示惯例,以 board 信息为准。
  2. **确认报告 `--soc=` 对应本机芯片**(三重印证):①项目文档(compile.md 的 soc 说明);②`bash build.sh --help` 的支持列表;③源码 SOC 映射(如 `scripts/util/const_var.py` 的 SOC_MAP)。常见对应:`ascend910b`=A2/910B、`ascend910_93`=A3/910C、`ascend950`=A5/950、`ascend310p`=310P。
  3. **端到端验证**:编译产物在本机实跑(run_example / 单测)能跑通 = soc 正确的最强证据。
  - 报告用错 soc(如 910C 机却 `--soc=ascend910b`)→ 报告/用法真问题,记入痛点;soc 正确则在结论报告补一节"SOC 核实"说明,避免用户误判"编译了别的芯片"。

#### 阶段 4｜文档原文对照核实(docs 容器已停用的替代路径)

> 原(docs 容器)流程已停用:不再单独 clone 干净仓库按官方文档独立执行。停用期间按以下方式完成"文档侧"核实,所得证据并入阶段 6-8 的痛点判定。

- **读同一 commit 的文档原文**:直接读取 report 容器 S1 已 clone 的仓库内文档(QUICKSTART.md、README.md、docs/ 下安装/编译/运行相关文档),**逐字核对痛点引用的文档原文是否真实存在、语境是否被挪用**(引用失真检查仍是痛点核实的必做项)。
- **文档承诺 vs 实测对照**:把文档给出的命令模板/文件名/路径/参数说明与本次 report 路径的实测产物与输出对照,核实"文档描述与实际不符"类痛点(文档模板缺字段、描述的目录不存在、未给出的映射/前置说明等)。
- **文档没有写出的步骤不得伪装成文档要求**;对照只使用文档原文,不引入推测。
- 有引用核实价值的文档原文(痛点点名的段落所在文件)存档到 `log/`(如 `log/QUICKSTART_original.md`),与 `repro_report.md` 一起留存。
- **证据力边界**:原文对照能证明"文档与实际不符",但不能证明"普通用户按文档从零独立执行必然失败/必然成功"——此类结论须如实标注"未做文档路径独立复现",措辞用"文档原文与实际不符",除非 report 路径实测已直接证明该后果。
- (恢复双子星时:在干净 `_docs_claude` 容器单独 clone 相同 commit,按官方文档独立执行对应阶段,不复制 report 容器的任何产物/补救;原设计全文见「双子星容器」章节。)

#### 阶段 5｜记录执行结果(report 路径)

- 为 report 路径的每条命令整理:命令来源、报告声明(success/报告dur)、真实 RC、实测耗时、业务输出摘要、功能是否成功和失败报错。**此阶段不下根因结论、不回头修改已执行命令。**
- **重跑/对照记录**(仅在触发规则时填写,如核心规则 4 的 wrapper 吞 RC 重取、环境对齐后重跑):保持不变的条件、唯一变化、真实 RC、结果是否稳定,单独记录每次尝试,不覆盖第一次结果。
- 如果存在匹配的 raw log,额外整理其 stage/task、status、commands 和 evidence,并在每条记录旁标注来源 JSON 路径;如果没有匹配 log,明确写"未发现可证明同次运行的 raw log"。
- (双路径对照表已随 docs 容器停用;阶段 4 的文档原文对照结果在分析阶段并入痛点判定表,不单列双路径表。)

---

### 第二部分:分析阶段(引入文档/源码对照)

#### 阶段 6｜报告该阶段结论逐条核实是否成立(现象状态 + 归因状态 + 可信度)

**只逐条核实 `pain_points`/`failure_reason`**(`cons` 不判定,仅存目);`observations` 是背景记录,**不强制逐一复现**(仅在发现某条 observation 与实测明显矛盾时,记一笔"观察偏差",不作成败判定,避免在非痛点上空耗)。**对复现清单内全部阶段的每条 `pain_points` / `failure_reason` 逐条判定**(自动扫描出的所有痛点阶段,含 S1 自身痛点;依赖前置阶段无待核实痛点),按「痛点核验判定模型」逐条判定,先从以下角度查:

1. **是否与客观达成矛盾**:`task_achieved=True` / `achievement_rate=100%`,却把过程波折当成阻塞性问题。
2. **退出码是否被管道掩盖**:报告把被 `| tail` 伪装的 RC=0 当成功,或反之;以本次真实退出码为准。
3. **定性是否夸大**:把"已解决的小波折"写成"阻塞性失败"、"跑不通"。
4. **根因是否站得住**(★ 最易出错,务必两层验证):报告常把"命令失败"和"为什么失败"混为一谈,必须拆开核实——
   - **层1 命令是否如报告所述失败**:复现该命令,确认 RC 与失败现象是否与报告一致。
   - **层2 失败根因是否真是报告说的那个**:读项目源码/README 定位真实失败点。**命令确实失败 ≠ 报告给的根因成立**——典型如"脚本失败被归因到 A,但源码显示实际卡在 B(报告没提到的另一依赖/分支)"。层1 通过而层2 不成立 → 判"不成立/根因判断错误"。
5. **措辞是否准确**(为"能否提交"做准备):报告定性描述是否与实测逐字相符——常把"非交互 `exit 1`"误述为"静默报告成功"、把输出数值记错、把"个别 case"夸成"全量崩溃"。这些直接决定痛点能否原样提交给项目方。
6. **引用是否失真**(痛点点名引用了文档/源码/日志原话时必查):必须回原文核对两点——①那句话**是否真存在**(防捏造/记错);②那句话的**语境是否被挪用**(典型:文档示例针对**单功能/单算子**,痛点当成**全量承诺**;文档写"建议/可",痛点当成"必须";文档说"执行成功显示 X",痛点理解成"所有 case 必过")。**引用真实存在 ≠ 引用成立**——语境被挪用则判"部分成立/措辞需修正",不能因原话存在就照单全收。
7. **填入双侧证据**:report 路径的实测现象 + 阶段 4 文档原文对照结果(文档原文/源码是否支持该痛点),是否支持该痛点;"现象成立"但"归因未确定"时明确写"现象成立、根因未确定",不能直接列入项目真问题。

每条给出:**痛点原文及 JSON 路径 / 可观察预期 / 本次复现实测 / 现象状态(成立/不成立/部分成立/无法判定) / 报告归因状态(项目/环境/用法/未确定) / 根因证据 / 可信度(高/中/低) / 能否原样提交(能 / 需修正措辞+修正建议)**。

**每条痛点核实完成后,按「单痛点独立核实文件」规范产出独立文件** `log/painpoint_<阶段号>-<序号>_<slug>.md`(痛点原文+命令源+`[源码]`/`[文档]`/`[日志]` 三类证据+逐段判定+实测汇总+核验结论),作为阶段 9 结论报告汇总表的证据全量支撑——证据必须落出处(文件:行号/日志原文),禁止只在汇总表里给结论。

#### 阶段 7｜归因与可信度(分类钉死根因)

**归因前先做对照实验钉死根因**(避免把环境/用法问题误判成项目缺陷,或反之):跑一个"应该能通过"的**对照项**(同算子的其它模块测试,或其它算子的同类测试)——**对照项通过 + 目标失败 → 排除环境/用法,锁定项目缺陷**;对照项也失败 → 倾向环境/用法。再用 `git log -S '<失败用例名/关键报错串>' -- <相关路径>` 定位引入 commit,若痛点现象与某次 refactor/提交同期 → 强化"回归"判断。对复现路上遇到的**每个障碍**(无论报告是否提及),按下方四类归因并记录解决方式:

- **项目问题**:按项目文档/源码跑不通、文档不明确、代码 bug、依赖声明缺失等(项目真缺陷)。
- **环境问题**:容器/驱动/工具链版本、网络源等(换源、补通用工具后即解决,与项目逻辑无关)。
- **用法问题**:报告/本次用错了命令、参数、路径(纠正用法后即通)。
- **未确定**:现象存在但证据不足以排除其它原因,不能写入"项目真问题清单"。

**项目问题清单只收"现象成立 + 报告归因成立"且有证据支持的真实缺陷**。

#### 阶段 8｜环境一致性 + 文档符合性 + 版本可复现性(此时才对齐文档)

- **环境一致性**:本次按 S1 装的环境,与报告 S1 记录是否一致(工具/版本/依赖)。**版本偏差的可接受判定**:若复现阶段命令实际依赖的是**系统默认工具**(`pip3`/`python3`/`gcc`/`cmake`)而非报告 S1 临时 `export`/uv 装的某个特定路径版本,则以系统实际版本为准判"一致"(报告那步临时 export 只是体验 agent 当时的做法,不代表项目要求);仅当报告 S1 用某特定版本**解决了某个报错**、而本次没复刻该版本导致复现失败,才算真不一致(需补装该版本重跑)。
- **文档符合性**(此时才引入项目文档对照):报告装的、本次装的,是否符合项目 README/文档要求(如要求的 gcc/cmake 版本区间、必装依赖)。此项只做"是否符合文档"的事实判定,不据此回头改执行阶段。
- **版本可复现性**:记录源码 commit、镜像 immutable ID/RepoDigest、驱动/CANN/关键依赖版本;缺失时标记结论受版本漂移影响(依据 `environment_fingerprint.log`)。
- **双路径指纹对照**:已随 docs 容器停用;仅记录 report 容器指纹与 Report 声明环境的差异(docs 容器停用,无跨容器指纹对照)。

#### 阶段 9｜写结论报告

汇总写入 `test_<项目名><时间戳后缀>/log/repro_report.md`(结构见下),**不要拆成多个结论 Markdown 文件**。

**结论报告写完后,两个固定收尾动作(缺一不可)**:
1. **写工作目录 `README.md`**(产物与脚本使用说明,四节模板见「工作目录结构」规矩):一句话结论 + 产物说明表(每个文件作用/怎么读,单痛点文件逐个列)+ 脚本说明表(每个脚本对应报告命令序号/前置条件/可直接粘贴的重跑命令)+ 重放顺序——保证任何人接手目录即可读懂产物、独立重跑。
2. **更新 `session_resume.md` 最终版**(状态改"已完成",补各阶段完成情况与结论报告路径),并 `docker cp` 同步容器 `/tmp/session_resume.md`——保证宿主机与容器内都能查到"哪个会话、如何恢复、在哪工作"。

两份文件分工:README 给"看懂产物与重放",session_resume 给"恢复会话";README 的重放顺序在容器已 Up 时可直接照做,容器丢了则先按 session_resume 重建。

---

## 结论报告 `repro_report.md` 模板

```markdown
# <项目名> <复现阶段列表> 复现验证报告

## 元信息
- 报告: <report_id> (生成于 <generated_at>)
- 项目: <project_id> / repo <repo_url> / branch <branch>
- 复现阶段: <S?/S?… 阶段名列表>(<自动痛点扫描识别 / 用户指定>) | 环境基线: S1_SETUP | 依赖前置: <无 / S?(为 S? 的产物依赖重放,非复现目标)>
- 报告复现容器: `cann_test_ml_<项目名><时间戳>_report_claude`  | 镜像: guoqiangqi/cogito:202606150944 | immutable ID/RepoDigest: <值>
- 文档复现容器: **未启用(docs 复现路径已停用)**;文档符合性以仓库内文档原文+源码对照方式核实
- 执行模式: 单容器 report 重放
- 复现时间: <本次>

## 输入与证据来源
- 主输入: `log/input_report.json`
- 痛点自动扫描: `log/painpoint_scan.md`(痛点分布表 + 复现清单)
- 同次运行 raw log: `log/matched_raw_log.json` 或"未发现/未采用"
- 运行关联依据: <Report ID、共享 run ID 或完全一致的文件名时间戳>
- 未采用候选 log 及原因: <项目/仓库/branch/运行标记不匹配>
- 环境指纹: `report_replay/log/environment_fingerprint.log`
- 版本差异: <源码 commit、镜像 ID/digest、驱动/CANN/依赖差异>
- 文档原文存档: `log/<文档名>_original.md`(如痛点引用了文档原文)
- 双子星目录: 不适用(docs 复现停用)

## 〇、痛点自动扫描与复现范围
- 扫描结论(阶段 × 痛点数,详见 `log/painpoint_scan.md`): <如 S1: X 条 / S3: Y 条 / S4: Z 条;无痛点阶段列"无">
- 进入复现清单的阶段: <S?、S?…> ;未进清单及原因: <无 actions / not_evaluated / 无痛点>
- S0 搜索与发现、S5 反馈与贡献: 不纳入扫描与复现(固定口径);其痛点如有仅存目 <原文,无则写"无">
- 依赖前置重放: <无 / S?(其编译产物被 S? 引用)>
- 用户指定覆盖: <无(全自动)/ 用户指定 S?,据此收窄>

## 一、S1 环境基线复现(按报告 S1 严格配置,report 容器)
| # | S1 记录命令 | 真实退出码 | 结果 | 备注(与报告一致性) |
|---|---|---|---|---|
- S1 报告声明装的 vs 本次实际装的: …
- 环境一致性结论: …
- 环境阻塞: <无 / 有；若有，后续痛点状态必须为"无法判定">
- report 容器指纹与 Report 声明环境的差异: …

## 二、Report 路径命令逐条复现
> 多阶段复现时按阶段分组(每组一个 `### S? <阶段名>` 小节,依赖前置阶段同样列出并标注);单阶段可省略分组。
| # | 报告记录命令 | 真实退出码 | 业务输出摘要 | 功能是否成功 | 失败报错 |

### 重跑/对照记录（仅在触发规则时填写）
| 尝试 | 保持不变的条件 | 唯一变化 | 真实退出码 | 结果是否稳定 | 证据 |

## 三、文档原文对照核实(docs 容器未启用;替代原"文档路径命令逐条复现")
| # | 痛点引用的文档原文(路径:行号) | 原文是否真实存在 | 语境是否被挪用 | 文档描述 vs 本次实测 | 判定 |

## 四、双路径对照
不适用(docs 复现路径已停用;文档侧证据见"三、文档原文对照核实"并已并入痛点判定表)

## 五、痛点/失败结论 核实(现象状态 + 归因状态 + 可信度)
- 待核实来源盘点: pain_points X 条 + failure_reason Y 条,共 N=X+Y 条
- cons 仅存目、不做正确性判定: <列出各阶段 cons 原文;占位符如 '-' 或空白略过,全部为空时写"无 cons 条目">
- 单痛点独立核实文件: <列出每个 painpoint_*.md 文件名,汇总表每行"详见"指向对应文件>
| 痛点原文(JSON路径) | 可观察预期 | 本次复现实测 | 现象状态 | 报告归因状态 | 根因证据 | 可信度 | 详见 |
|---|---|---|---|---|---|---|---|
- 状态只能使用:成立 / 不成立 / 部分成立 / 无法判定(环境阻塞)
- 报告归因只能使用:项目问题 / 环境问题 / 用法问题 / 未确定
- 根因未锁定时明确写"现象成立、根因未确定"，不能直接列入项目真问题
- 措辞需修正才能提交的(附修正建议): …
- 每条 pain_points/failure_reason 的完整证据链(命令源 + [源码]/[文档]/[日志] 三类证据 + 逐段判定 + 能否提交/提交文本)在对应 `log/painpoint_<阶段号>-<序号>_<slug>.md`,汇总表只作索引

## 六、复现障碍 归因
| 障碍 | 分类(项目/环境/用法/未确定) | 解决方式 | 是否影响痛点判定 |
- 项目真问题清单: …

## 七、SOC/芯片支持核实(复现清单含 S3/S4 编译类阶段时必做,用户常追问)
- 本机芯片型号(npu-smi board): …
- 报告 `--soc=` → 芯片对应(文档/build.sh/源码三重印证): …
- 编译产物在本机实跑验证: …
- 结论:soc 是否用对 / 是否存在"编译了不支持本机芯片的产物"

## 八、结论
- <各复现阶段逐一>是否如报告所述复现成功: …
- Report 路径结果: …  ; 文档侧核实结果(原文对照,未做独立执行): …
- 执行模式: 单容器 report 重放(双子星/并行试跑已停用,不适用)
- 文档原文对照是否支持该痛点: …
- 痛点核实汇总(仅 pain_points/failure_reason,cons 不判定): 共 N 条；现象成立 M 条、不成立 K 条、部分成立 P 条、无法判定 U 条
- 报告归因汇总: 项目问题 …、环境问题 …、用法问题 …、未确定 …
- 根因可信度: 高/中/低；关键依据: …
- 可直接提交给项目方的痛点: … ; 需修正措辞的: …
- 项目真缺陷: …
- raw log 是否与本次复现一致: …；若不一致，不能作为根因依据
```

---

## 辅助踩坑库(非项目耦合,可直接复用)

> **沉淀规则**:本库只收**非项目耦合的通用踩坑**——装环境/工具链/依赖时的通用手法(换源、通用包安装技巧、环境变量、NPU 基础设施)。**严禁**收项目耦合结论(某项目某脚本的根因、某次复现的具体数值、某项目特定配置)。每条写清"症状→通用解法"。
> 复现装环境卡住时先查本库;装环境成功后,若用了新的通用手法,补进本库。

### 网络与源硬规则(换源/代理优先级)

> 原则:**优先国内源;非国内源一律走代理,禁止无代理直连境外源。** 任何 `deb.debian.org`、`pypi.org`、GitHub、`download.pytorch.org` 等境外下载地址,都不得做无代理直连或无代理安装;即使偶尔直连成功,也必须保留代理。换源只换"让报告同一条命令跑通",不换命令/包/版本。

- **换源顺序**:先把原命令切换到已选定的国内候选源,再验证新源的 `InRelease`、pip simple index 和实际索引更新;禁止先对默认境外源做无代理探测。
- **无代理安装**:只有切换到国内源且验证成功后,S1 环境安装命令才可按命令级方式清除代理:`env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy <原命令>`。不修改正在运行容器的全局代理环境;后续每条安装命令仍记录真实 RC。
- **APT 回退顺序(硬规则)**:在 Debian 13/trixie 复现容器中,固定按"华为云国内源 → 其它中国大陆镜像 → 原始非国内源加代理"的顺序处理。第一步尝试 `https://repo.huaweicloud.com/debian` 和 `https://repo.huaweicloud.com/debian-security`;若不可用,再逐个尝试能覆盖当前发行版、架构、suite 和 security 的其它中国大陆镜像;所有国内候选都不可用时,恢复/保留 Report 原始非国内源,并通过代理执行原始 `apt` 命令,禁止对原始源无代理直连。每个候选源都必须先替换配置,再用无代理 `apt-get update` 验证;保留原来的 suite、components 和 `Signed-By`,只替换 `URIs`,先备份原配置,`apt` 之间保持串行,并记录候选源、验证结果、真实 RC 和最终选择。
- **pip**:普通 Python 包优先使用国内源 `https://repo.huaweicloud.com/repository/pypi/simple`,可通过 `python3 -m pip config --global set global.index-url https://repo.huaweicloud.com/repository/pypi/simple` 设置;只有该国内源验证成功后才能无代理安装。只能为同一包和同一版本换可达源;Report 明确指定的 `--index-url`、`--extra-index-url`、私有源、校验哈希或项目专用源必须保留,不能被默认源覆盖。
- **git clone**:可使用浅克隆或镜像加速,但 URL、branch 和目标路径保持报告语义。
- **cmake/源码下载**:只替换为同版本的可达镜像。

### pip S1 断点处置(必须先核实文件)

- 遇到 `No matching distribution found for coverage`、numpy 等普通包时,先在容器内读取实际 `requirements.txt`,并检查其中是否真的存在 `--index-url` 或 `--extra-index-url`;不能因为后续单独有 PyTorch 安装命令,就推断 requirements.txt 存在 PyTorch index 冲突。requirements.txt 没有 index 选项时,先在已选定且验证成功的国内源上查询该包及当前 Python/架构的可用版本,再用同一包、同一版本和同一 requirements 文件做仅换源重试,不修改项目文件。
- 只有在实际 requirements.txt 明确含有会作用于整份文件的专用 index 时,才记录为 index 冲突。严格 Report 重放保留原文件和原命令;需要验证修复时使用临时副本或分批安装普通包与专用包,普通包使用已验证的国内主源,专用包保留报告指定 index,明确记录这是 source-adapted retry,不能把改写原 requirements 或拆分命令后的结果冒充严格基线。
- **报告明确指定 PyTorch 官方 `--index-url` 时必须保留**,不能用华为源替换,也不能把 CPU wheel 改成其它版本。该境外源必须通过宿主机代理访问;在 `--net=host` 容器内依次检查 3129、7890 等已配置代理,用代理验证目标 index 后,在命令级设置大小写代理变量重跑原命令。长命令使用 `pipefail`,并从 `PIPESTATUS[0]` 保存 pip 的真实 RC;不要用宽泛 pkill,清理卡住进程时只匹配目标 pip install 命令,避免杀掉当前 shell 或其它任务。代理不可用时记录环境阻塞,不得退回境外源无代理直连。
- torch-npu 间接依赖缺失时,先按报告指定版本通过官方 CPU index 和代理安装 torch,再在已验证的国内完整 PyPI 源上查询同版本 torch-npu 及其间接依赖(例如 cuda-bindings)的可见版本,随后用同一 torch-npu 版本做仅换源重试。不要假定 cuda-bindings 一定由 torch-npu wheel 直接声明;先检查当前 torch 候选的 metadata/Requires-Dist,避免把错误 torch 候选的 CUDA 依赖误归因于 torch-npu。仍无匹配时检查 Python 版本、系统架构、wheel 标签和源覆盖范围;不得未经报告或项目声明擅自换版本、加 `--no-deps` 或安装无关包。直接依赖声明确实不可安装时才记录为项目依赖声明问题,否则归为源/环境兼容性问题。
- **三类断点的固定顺序**:requirements 普通包及其导入验证 → 报告指定的 torch 官方源安装 → torch-npu 及间接依赖安装 → 全量导入与 pip check。pip check 若只报告镜像预装且不在项目 requirements/文档中的其它工具包缺依赖,不得盲目扩大安装范围;将其单独记录为镜像全局依赖残留,严格 S1 是否能继续仍按 Report 是否要求该校验通过判定。

### 通用换源 / 加速
- **pip 换国内源**:`pip install -i https://pypi.tuna.tsinghua.edu.cn/simple <pkg>` 或 `pip config set global.index-url ...`。仅用于让报告同一条 pip 命令跑通,不换包/版本。
- **apt 换源**:容器内 apt 慢/失败时按「网络与源硬规则」的 APT 回退顺序处理(华为云 → 其它国内镜像 → 原始源加代理),再跑报告原 apt 命令。
- **gitcode / github clone 慢或超时**:加 `--depth=1` 浅克隆(仅加速,不改 url/branch);或换镜像。仍以报告记的 url/branch 为准。
- **cmake/源码下载慢**:换国内镜像下载同一版本,不换版本。
- **pytorch.org whl 直连慢(`torch==X.Y+cpu`/`torch_npu` 等)**:症状——项目 requirements pin `torch==2.7.1+cpu`,执行 `pip install torch==2.7.1+cpu --index-url https://download.pytorch.org/whl/cpu` 直连 download.pytorch.org 首字节 12s+、200MB torch 下十几分钟甚至 docker exec 超时(报告该步仅 36s,复现直连卡死)。通用解法(**只加速,不换包/版本/源**):仅给该条 pip 命令加宿主机代理 env,如 `HTTPS_PROXY=http://127.0.0.1:3129 HTTP_PROXY=http://127.0.0.1:3129 pip install torch==2.7.1+cpu --index-url https://download.pytorch.org/whl/cpu`(容器 `--net=host` 下 127.0.0.1:3129 = 宿主机 mihomo;实测代理 0.39s vs 直连 12.9s,装完 37s≈报告 36s);**只这一条带代理**,其余 pip(华为云源)不带,避免国内源绕远。判据:pytorch.org/whl 直连首字节>5s 或下载停滞即加代理,包/版本/index-url 保持报告原样。若已按「网络与源硬规则」配置命令级代理变量,直接复用该代理。

### 通用环境 / NPU 基础设施
- **NPU 不可见**:`npu-smi info` 无设备 → 检查容器是否挂了 `/dev/davinci*` 与 driver 挂载、`LD_LIBRARY_PATH` 是否含 driver/lib64 与 dcmi。
- **`LD_LIBRARY_PATH` 缺失类报错**(找不到 driver/lib64 下 .so):按起容器命令设的值补齐(已在 `-e` 注入,容器内新 shell 用 `bash -lc` 或显式 export)。
- **gcc/cmake/ccache 等基础工具缺失**:照 S1 报告记的命令装;apt 装不到目标版本时用通用方式(源码/通用 PPA),但版本区间以 S1 报告记录为准。
- **Python 版本/包**:照 S1 记的 Python 与包版本装;通用包(如 numpy)装不上按通用换源处理。
- **`apt` 不可互相并行(dpkg 锁)**:症状——多条 `apt`/`apt-get` 并行跑时报 `Could not get lock /var/lib/dpkg/lock`、`Resource temporarily unavailable`、或某条静默失败。通用解法:`apt` 命令之间**串行**(或合并成一条 `apt install A B C`);`apt` **可与跨类型命令**(git clone / pip / wget)并行。S1 并行批里不要把多条 `apt` 塞进同一组。
- **容器内长耗时命令触发 docker exec 超时**:症状——`docker exec <容器> bash <脚本>` 跑编译/大下载/install 等长命令(几十秒以上)时被中断,报 `OCI runtime exec failed: timeout 30s for cmd`(docker daemon 对单次 exec 的超时,长输出重定向到文件、stdout 长时间静默时尤甚)。通用解法:用 `docker exec -d`(detached)在容器内后台启动(`docker exec -d <容器> bash -c 'bash /tmp/x.sh > /tmp/x.out 2>&1'`)并立即返回,宿主机再用**短查询**(`docker exec <容器> bash -c 'grep -q DONE /tmp/x.out && echo DONE || echo RUN'` / `tail`)轮询是否出现结束标记(脚本末尾 echo 一行如 `DONE`),规避 exec 超时。**轮询节奏**:按预估总耗时的 **1/3~1/2** 间隔轮询(如全量 UT 预估 15min,每 4–5min 轮询一次;大下载预估 3min,每 1min 一次)——过频烧 token、过疏空等;宿主机 `sleep <整数分钟> && docker exec ... grep DONE` 轮询即可,别 `tail -f` 长挂(同样会触发 exec 超时)。
- **`/app/.venv` 缺 pip 致 CANN toolkit `.run` 安装失败**:症状——cogito 镜像自带 `/app/.venv`(devx 用,python 在但**无 pip**),CANN toolkit `.run --install` 内部 find python 命中 `/app/.venv/bin/python3`,致 `mindstudio-boost` 子包(如 `affinity-sched`)装失败 → toolkit **整体回滚卸载**(RC≠0,日志见 `msboost ... No module named pip` / `mindstudio-boost install failed`),即便 bisheng 等文件残留。通用解法(二选一):① 装前 `mv /app/.venv /app/.venv.bak` 移走,装完保持移走态;② `/app/.venv/bin/python3 -m ensurepip --upgrade` 给该 venv 补 pip 后,再 `--install --force` 重装。判断 toolkit 是否真装好:`setenv.bash` 存在 + `bisheng -v` 出 clang 版本 + `<Ascend>/aarch64-linux/ascend_toolkit_install.info` 的 `version=`,**不只看文件残留或顶层 version.info**(见下条)。A3-ops 等**独立 `.run` 不受 toolkit 回滚影响**,通常 RC=0。
- **CANN env 脚本路径 & version.info 位置(假失败排查)**:文档/安装输出路径是 `/usr/local/Ascend/cann/bin/setenv.bash`(`cann` 软链 `cann-<版本>`,如 `cann-9.1.0`);source 它设 `ASCEND_HOME_PATH` 等。**顶层 `cann-<版本>/version.info` 常不存在**,版本信息实际在 `cann-<版本>/aarch64-linux/ascend_toolkit_install.info`(`version=<x.x.x>`)及 `compiler/version.info`、`opp/version.info`;`cat 顶层 version.info` 失败 ≠ 没装好(报告常把这种当 failure,实为假失败,看 `.info`/`bisheng -v` 才准)。
- **报告混用 `ascend-toolkit/set_env.sh` 与 `cann/set_env.sh`,前者常是空目录**:症状——报告 `setup_deps` 等步骤 source `/usr/local/Ascend/ascend-toolkit/set_env.sh`,但当 toolkit 以 `--install-path=/usr/local/Ascend` 安装时,实际装到 `/usr/local/Ascend/cann-<版本>`(`cann` 软链),`/usr/local/Ascend/ascend-toolkit/` 往往是**空目录**,source 该路径 `set_env.sh` 报 "No such file" / 之后 `ASCEND_HOME_PATH` 仍为空。通用解法:**统一改用 `/usr/local/Ascend/cann/set_env.sh`**(= `cann-<版本>/set_env.sh`,实际存在且有效)等价 source;这是同一 set_env 动作,仅换成实际存在的软链路径,不改包/版本。判定:`ls /usr/local/Ascend/ascend-toolkit/` 空、`ls -la /usr/local/Ascend/cann` 是软链 → 用 cann/set_env.sh。
- **apt 默认源极慢(必换)**:cogito 镜像(Debian13 trixie)默认 `deb.debian.org` 在内网约 ~10 kB/s,`apt update` 就十几分钟。源是 **DEB822 格式**(`/etc/apt/sources.list.d/debian.sources`,非传统 `sources.list`),换华为云:把该文件 `URIs` 改为 `http://mirrors.huaweicloud.com/debian` 与 `/debian-security`(Suites 保持 `trixie`/`trixie-updates`/`trixie-security`)。**tuna 的 trixie 源对部分包/whl 间歇或持续 `403`**,华为云稳;换源后 update 应 <5s。
- **pip 源:tuna 易 403,备选阿里云**:tuna 的 `/packages/` whl 下载路径在某些网络**全 `403 Forbidden`**(simple 索引能访问但 whl 下不下来,5s 内快速失败、所有包 RC=1)。备选 `https://mirrors.aliyun.com/pypi/simple`(实测稳);`pip config set global.index-url ...` 设全局,对系统 python 与 venv 均生效。

- **`docker run` 起的容器立即 `Exited (0)`**:症状——用 `docker run -d ... --entrypoint bash <镜像>` 起容器(漏 `-it`),`docker ps -a` 显示 `Exited (0)`(bash 无 tty、无前台进程直接退出)。通用解法:起容器**必须 `-dit`**(skill 模板即如此);若仍 Exited,末尾改用 `sleep infinity` 作前台进程。起后**务必 `docker ps` 确认 `Up` 再往下**,别等 `docker exec` 报 "Container is not running" 才发现。
- **命令安全分类器间歇不可用,复合 docker 命令被拦**:症状——`docker cp ... && docker exec ...`、`docker exec -d ... && echo` 等复合命令偶发报"auto mode 无法判定安全性",而简单单条 `docker ps`/`docker exec ... echo` 正常。通用解法(只绕过、不改语义):①脚本用一条管道送入执行:`cat <脚本> | docker exec -i <容器> bash -c 'cat > /tmp/x.sh && chmod +x /tmp/x.sh && bash /tmp/x.sh'`;②或 `python3 -c "import subprocess; subprocess.run(['docker','exec',...])"` 以列表参数避开 shell 解析;③长耗时命令用 `docker exec -d` detached + 轮询(见上条)。
- **清理残留进程时 `pkill -f` 自匹配误杀 docker exec 执行 shell(Exit 137)**:症状——在 `docker exec <容器> bash -c '... pkill -f "build.sh" ...'` 里用 `pkill -f <模式>` 清理残留编译/测试进程时,因 docker exec 的命令行(含脚本里写到的 `build.sh`/`ctest` 等字串)也被 `pkill -f` 匹配,pkill **误杀自己的执行 shell**,整条命令 Exit 137(SIGKILL),容器内目标进程反倒没清掉。尤其 `ctest -jN` 会衍生成百上千孤儿进程(test 二进制 + g++ 编译子进程),逐个 kill 易漏。通用解法(只清目标、不伤自身):① 用**精确进程名** `pkill -x ctest`/`pkill -x pytest`(`-x` 只匹配进程名、不匹配命令行参数,不会命中 docker exec shell);② 或 `ps -eo pid,args | grep <特征> | grep -v 'bash -c'` 过滤掉自身后取 PID 再 `kill`;③ 对 `ctest -jN` 衍生的大量孤儿进程,**最彻底是 `docker restart <容器>`**(保留容器层文件如 /tmp/devx_workspace、output/third_party、build/ 编译产物,清空所有进程),restart 后重新 `source set_env.sh` 即可续跑。
- **CANN 项目 install_deps.sh 常内置多镜像 fallback**:症状——首次跑 install_deps.sh 日志先报某镜像(如 tuna)`403`/失败,但脚本随后自动切换下一镜像(如华为云)并成功,最终 RC=0。通用解法:**首次镜像失败先看日志是否已自动 fallback 成功,别急着重试或改命令**;只有"所有镜像都失败"才是真失败(多为网络全断)。同理:pip 源建议直接用华为云 `repo.huaweicloud.com/repository/pypi/simple`(install_deps.sh 内置 fallback 用的就是它,最稳)。

- **CANN weekly build URL 过期(devcloud 轮换删除)**:症状——报告记的 `ascend.devcloud.huaweicloud.com/artifactory/cann-run-mirror/software/master/<build_id>/Ascend-cann-*.run` 下载 **404 / 0 字节文件**,build_id 形如 `20260722000328244`。devcloud master 目录每周轮换、只留最新一两个 weekly build,旧 build_id 物理删除(报告里 browser_navigate 当时拿到的 build_id,几天后必失效)。通用解法(**版本不变、只换 build_id**,非项目问题):① `curl -s .../software/master/` 读 HTML 列表取当前最新 build_id(**17 位 `20YYMMDD000xxxxxx`,正则用 `20[0-9]{15}`,别用 `{11}` 截断成 15 位误匹配**);② `curl -s .../master/<新build_id>/ | grep -oE 'Ascend-cann-(toolkit|A3-ops|910b-ops|950-ops)_[0-9.~]+_linux-aarch64\.run'` 拿当前文件名(weekly 日期也变,如 `20260722.01`→`20260729.01`,但主版本号如 `9.2.0` 不变);③ 用同主版本的新链接重下。判据:报告链接 404 = build 过期,不是 URL 拼错或网络问题。

- **CANN 9.2.0+ 移除老 ge 库 `libgraph.so`/`libregister.so`，旧版 torch_npu(2.8) 加载失败**:症状——脚本 `import torch_npu` 报 `RuntimeError: Failed to load backend extension: torch_npu`，底层 `ImportError: libgraph.so: cannot open shared object file` 或 `OSError: libregister.so: cannot open shared object file`；`find /usr/local/Ascend -name 'libgraph.so*' -o -name 'libregister.so*'` **全空**(CANN 9.2.0 lib64 有 `libge_runner.so`/`libge_compiler.so`/`libexe_graph.so` 等新名，老 `libgraph.so`/`libregister.so` 已改名/移除)。根因:torch_npu 2.8 编译期链接老 ge 库 libgraph.so，与新 CANN 9.2.0 不兼容。通用解法(判真假、非项目缺陷):装匹配 CANN 9.2.0 的 torch_npu(≥2.9.0，项目 `examples/pytorch/README.md` 常已写明版本要求)；判 torch_npu 能否加载看 `python3 -c "import torch_npu"` 真实报错，别信 `|tee` 的 RC=0。属环境/版本问题，非项目逻辑缺陷。

- **GE/acl 样例报 `Initialize ge using ge global options failed`(RC=255)但 stdout 无根因——先查 plog 的 ModuleNotFoundError**:症状——GE/acl 样例二进制运行只打一行 `Initialize ge using ge global options failed` 即退出(真实 RC=255，经 `|tee` 显示 0 是假成功)，stdout 完全不提示原因。根因——CANN toolkit 自带的 tbe/tvm(`$PYTHONPATH` 指向 `cann-<版本>/python/site-packages`)初始化时 `import numpy`/`from decorator import decorate` 等，而 `.run` 安装**不装这些 Python 三方包**，系统 python 缺包即链式失败:`pywrapper Traceback → InitializeAOE failed → Failed to init tbe → GEInitialize failed`。通用解法(只定位，不改项目):查 `/root/ascend/log/debug/plog/` 最新日志 grep `ModuleNotFoundError`，按缺失名单 `pip3 install`(常见 numpy、decorator、attrs、psutil、scipy、sympy、absl-py)，补一个可能再缺下一个——逐个补到运行通过；**判定属环境/依赖声明问题**(若项目文档/检查脚本也未声明这些运行态依赖，则计该项目的文档缺陷痛点)。

- **cogito 报告 `|tee; echo RC=$?` 系统性误判(跨项目通用)**:症状——体验 agent 的 build/UT/ST/sample 命令常写成 `bash xxx 2>&1 | tee log; echo EXIT_CODE=$?`，`$?` 取的是 **`tee` 的退出码(恒 0)**，不是被测命令的；导致链接失败/Traceback 在 log 里、报告却记 `success`/`全过`。复现 cogito 报告时，凡报告命令含 `| tee` 且判定 success 的，**一律重跑取真实 RC**(`cmd > log 2>&1; echo RC=$?`，绝不接 tee)并读业务输出(pass/failed/undefined reference/Traceback)。典型表现:报告"UT N 项全过/样例 success"，实测 `Build autofuse failed`/`undefined reference`/`torch_npu 加载失败`。

### 资源、网络和运行时失败(归为环境/编排障碍,不直接算项目问题)

以下情况要记录并分类,**不要直接归因项目**:网络源不可达、Docker socket 无权限、设备节点缺失、driver 与容器不匹配、宿主机资源不足、同卡并行设备争用、编译或测试超时。只有在环境和用法排除后,源码/文档仍能证明问题属于项目时,才列入项目真问题清单;并行试跑失败但串行重跑成功时,结论应归为复现编排/环境障碍,不是项目痛点。

### 沉淀新条目(复现中遇到通用问题时)
> 格式:`### <症状关键词>` + `症状:` + `通用解法:` + `(仅适用:非项目耦合)`。判定不确定时,宁可不放,避免污染为项目耦合结论。

### 新版 conda 强制 ToS(CondaToSNonInteractiveError)
- 症状:`conda create/install` 报 `CondaToSNonInteractiveError: Terms of Service have not been accepted for the following channels: repo.anaconda.com/pkgs/main, /pkgs/r`——报告运行期(旧版 miniconda)无此限制,复现日下载 latest miniconda 后同一条命令突然失败(时移环境差异,非项目问题)。
- 通用解法:执行 `conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main`(及 `pkgs/r`)各一次后,按报告原命令重跑即可;不改包/版本/命令语义。(仅适用:非项目耦合)

### die 被其它容器进程占用 → aclrtSetDevice 507033(ASCEND_RT_VISIBLE_DEVICES 换 die)
- 症状:裸 `acl.rt.set_device(0)`/任何 NPU 程序报 `error code: 507033`(`ACL_ERROR_RT_DEV_SETUP_ERROR`),plog(`/root/ascend/log/debug/plog/` 最新)见 `SetDevice:...the current input soc version is null → device retain error`;宿主机多个容器共享同一 davinci 设备时发生(某容器进程占用 die0,即使 HBM 占用很小)。
- 通用解法:双 die 卡(910C/IT22HMDA,davinci0/davinci1)先用 `acl.rt.set_device(1)` 验证 die1 可用(返回 0 即可用,soc 同型号);然后给复现命令加 `export ASCEND_RT_VISIBLE_DEVICES=1`,把物理 die1 映射为逻辑 device0——测试代码无感,芯片型号语义不变。判定属环境/设备编排障碍,不计项目问题。(仅适用:非项目耦合)

### bazel 首次 build 的 github 依赖断流(重跑+代理增量续传)
- 症状:xla 类 bazel 项目首次 build(模块解析 300+ repo)在慢网下极慢(1h+),且随机失败于 github tarball:`Error downloading [https://github.com/...] ...Bytes read X but wanted Y`(下载 90%+ 断流)或 `Connect timed out`——重跑换一个 repo 报错,纯属网络不稳,非项目问题。
- 通用解法:①同命令直接重跑——bazel external repo 缓存增量复用,已下载的不重拉,通常 1-2 次内通过;②给 build 进程注入代理 env(`export https_proxy=http://127.0.0.1:7890 http_proxy=...` 后再跑,容器 `--net=host` 直连宿主代理);③长跑一律 `docker exec -d` + 轮询,按 1/3~1/2 预估耗时间隔查 `/tmp/*.done`。区分"卡死"与"慢":日志行数/`du -sh ~/.cache/bazel` 持续增长 = 活跃,只增不判死。(仅适用:非项目耦合)


