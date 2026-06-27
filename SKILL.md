---
name: experience-report-repro
description: "在固定昇腾NPU容器里复现JSON体验评估报告中【用户指定的某个阶段】，核实该阶段的痛点/失败结论是否成立。输入是体验agent生成的JSON体验评估报告(记录某开源项目S0搜索→S1环境准备→S2快速体验→S3开发编译→S4测试验证→S5贡献各阶段的命令轨迹actual_path.actions、痛点pain_points/failure_reason、评分)。用户指定复现哪个阶段(没问题、无需复现的阶段不指定)。核心机制:S1是环境基线——无论复现哪个阶段,都先严格按S1_SETUP阶段记录的actions把容器环境配置成与报告一致(照S1原样装,不自行补装/修正/对齐文档),其他阶段依赖这个环境;然后再逐条复现用户指定阶段的命令轨迹,捕获真实退出码、读业务输出,逐条核实该阶段痛点是否成立。复现环境固定用docker容器(镜像guoqiangqi/cogito,容器名cann_test_{使用者}_{项目名},挂载davinci设备与Ascend driver/firmware/npu-smi等)。全程独立,只依据被复现报告+本项目文档/源码,不读workspace其他项目结果;但工具链/依赖安装的非项目耦合通用踩坑可复用。触发:用户给出JSON体验报告并要求复现/验证/核实某阶段(S2快速体验/S3编译/S4测试等)的失败结论或痛点是否成立,或要求起干净NPU容器验证某CANN/昇腾项目某阶段流程是否如报告所述。"
---

# 体验报告阶段复现与验证(昇腾NPU容器)

> **输入**:体验 agent 生成的 **JSON 体验评估报告** + 用户**指定要复现的阶段**。
> **目标**:在固定的昇腾 NPU docker 容器里,**先按 S1 把环境配成与报告一致,再复现用户指定阶段**的命令轨迹,核实该阶段的**痛点/失败结论是否成立**——很多报告里的"痛点/失败/0%"其实是体验 agent 那次特定环境或用法的问题,甚至是它自身的判断有偏差,并非项目缺陷。

---

## 核心执行规则

### 1. S1 是环境基线:每次复现都先按 S1 把环境配成一致

复现**任何**指定阶段,第一件事都是按报告 `S1_SETUP` 阶段记录的命令,把容器环境配置成与报告**同一个状态**——其它阶段都跑在这个环境上。

- 严格照 S1 原样执行:S1 里 clone 的仓库(url/branch/路径)、安装的工具与依赖(gcc/cmake/python/各类包),一律按 S1 记录的命令原样来。
- 不自行补装、不修正版本、不拿项目文档的安装步骤替代 S1。
- 换源只用于"让 S1 记的那条命令能跑通"(同一条命令、同一个包,换镜像源加速),不替换成别的命令或别的版本。
- S1 环境配好、确认与报告一致后,再进入用户指定的阶段。顺序不能颠倒,不能跳过 S1。
- "本次环境是否符合项目文档要求"留到分析阶段再判定,本阶段只对齐报告 S1。

### 2. 只复现用户指定的那一个阶段

- 用户指定复现哪个阶段,就只复现那个阶段;用户没指定的阶段不碰(没问题的阶段不会要求复现)。
- 按该阶段 `actual_path.actions` 的顺序,逐条执行其中的 `git_clone` 与 `shell_exec`;`file_read`/`web_search` 等是观察行为,不算可执行命令。
- 该阶段 `not_evaluated=True` 或没有 actions 时,告知用户该阶段报告未评估、无法复现,请改指定其它阶段。

### 3. 执行阶段以报告为准,文档/源码留到分析阶段

- 起容器、按 S1 配环境、复现指定阶段,都照报告记录原样执行,执行过程中不去翻项目文档补装或改命令。
- 项目文档与源码在**分析阶段**才引入,用来对照核实,不在执行阶段干预。

### 4. 判定命令成败看真实结果,不被退出码或管道骗到

- 每条命令都要拿到**真实退出码**:不要在命令后接 `| tail` / `| head` 这类管道——管道会把前面命令的真实失败掩盖成成功。用 `命令 > 日志 2>&1; echo RC=$?` 拿退出码。
- 退出码是 0 **不代表**功能成功:对测试、验证、运行类命令,还要看程序实际输出(测试 pass/failed、结果与预期是否一致、精度误差),才能判定这条命令到底成没成。

### 5. 复现中的问题分清是哪一类;报告该阶段的结论逐条对照核实

- 复现路上遇到的每个障碍,分清是:**项目本身的问题**(按文档/源码跑不通、文档不清、代码缺陷)、**环境问题**(容器/驱动/工具链/网络源,换个源或补通用工具就好,跟项目逻辑无关)、还是**用法问题**(命令/参数/路径用错了,纠正就好)。
- 报告里该阶段记的每条**痛点 / 失败原因 / 缺点**,逐条对照本次复现的真实结果核实:这条结论在干净环境、按报告用法下是否真的成立?会不会是体验 agent 那次特定环境或用法造成的、或它判断有偏差?给出"成立 / 不成立 / 部分成立"和依据。

### 6. 通用安装踩坑可直接用,但不参考别的项目结论

- 装 environment 时的**通用手法**(pip/apt/git 换源、NPU 基础设施、通用工具安装——这些跟具体项目无关)可直接拿来用,避免在装环境上反复卡壳(见文末「辅助踩坑库」)。
- 但不要去翻 workspace 里别的 `test_*/` 项目、别的项目版本得出的**项目相关结论**来对照或抄答案——每个项目的复现只依据它自己的报告 + 文档/源码。

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
      .pros / .cons        阶段优点/缺点(cons 也是痛点来源)
      .subjective / .objective  评分
journey_map / phase_analysis   各阶段总分、pros/cons 汇总(辅助理解)
```

**取数要点**:
- 复现命令 = 该阶段 `per_project_assessments[0].actual_path.actions[]` 里 `action_type=shell_exec` 的 `tool_args.command`,以及 `git_clone`(`tool_args.url/branch`)。`file_read`/`web_search` 等是观察行为,不当作可执行命令(但 file_read 的路径提示了报告读过哪些文档,分析阶段可对照)。
- 待核实痛点 = 该阶段 `task_completion.task_details[]` 的 `pain_points` + `failure_reason`,以及 `cons`。

---

## 阶段映射与可复现性

| step_id | 阶段 | 是否典型复现目标 |
|---|---|---|
| S0_DISCOVERY | S0 搜索与发现 | 一般**不指定**复现(主要是搜索/文档导航行为,非容器内命令) |
| **S1_SETUP** | **S1 环境检查与准备** | **永远是第一步(环境基线)**,即使不是用户指定的目标阶段也要先按它配环境 |
| S2_QUICKSTART | S2 样例快速体验 | ✅ 典型复现目标(跑样例/demo) |
| S3_DEVELOPMENT | S3 开发与编译 | ✅ 典型复现目标(编译/构建) |
| S4_TESTING | S4 测试与验证 | ✅ 典型复现目标(跑测试/精度验证) |
| S5_CONTRIBUTION | S5 反馈与贡献 | 通常 `not_evaluated=True`,无可复现 actions |

用户说"复现 S2 / 复现快速体验阶段 / 复现编译阶段"等 → 按上表映射到 `step_id`,在 `journey_steps` 里定位。**只能复现 `not_evaluated=False` 且 `actions` 非空的阶段**;若用户指定的阶段 `not_evaluated=True`,先告知该阶段报告未评估、无可复现内容,请其改指定其它阶段。

---

## 复现环境(固定 docker 容器)

**复现一律在固定的昇腾 NPU docker 容器内进行**。容器名按项目命名:`cann_test_{使用者}_{项目名}`,镜像固定。

**{使用者} 取法**:使用者自己的标识(如姓名拼音/缩写),用于区分不同人起的容器,例如 `zhangsan`。
**{项目名} 取法**:取报告 `project.project_id` 中 `/` 后的部分(如 `cann/asc-tools` → `asc-tools`),与宿主机工作目录 `test_<项目名>` 保持一致。

起容器命令(把 `{项目名}` 替换为实际项目名):

```bash
docker run -dit \
  --name cann_test_{使用者}_{项目名} \
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
- 容器内执行统一用 `docker exec cann_test_{使用者}_{项目名} bash -lc '<命令>'`;脚本先在宿主机 `test_<项目名>/scripts/` 写好,再 `docker cp` 进容器执行,便于审视与复用。
- **宿主机↔容器文件流转**:宿主机 `test_<项目名>/` 只放脚本/日志/报告;容器内按报告记录的路径操作(如 S1 里 git clone 到 `/tmp/devx_workspace` 就照此路径)。容器内日志用 `docker exec ... > 宿主机log` 或执行后 `docker cp` 取回 `test_<项目名>/log/`。
- 起容器后先自检 NPU 可用:`npu-smi info`(应能看到设备)与 `ls /dev/davinci*`,确认设备挂载成功,再进入复现。

---

## 工作目录结构(每个项目独立)

每复现一个项目,在 workspace 下建 `test_<项目名>/` 目录,**所有产物归档其中**,保持 workspace 根目录干净:

```
test_<项目名>/
├── <项目名>/     # (可选)宿主机侧留存的项目源码副本;主复现在容器内 clone
├── scripts/      # 复现脚本(自检/装环境/复现等,docker cp 进容器执行)
└── log/          # 体验报告(输入 JSON) + 过程日志 *.log + 结论报告 repro_report.md(输出)
```

规矩:
- 复现**第一步**建结构:`mkdir -p test_<项目名>/{scripts,log}`;把输入 JSON 报告放进 `log/`。
- ★ **结论报告固定写入 `test_<项目名>/log/repro_report.md` 这一个文件**——复现结论对照表 + S1 环境复现 + 指定阶段复现 + 痛点核实判定 + 问题三分类归因 + 项目问题清单**全部汇总进它**;过程日志另存 `log/*.log`(如 `s1_setup.log`、`s3_build.log`)。**禁止**拆成多个 `.md` 或起别名。
- 复现命令清单里的脚本路径一律用 `test_<项目名>/scripts/<脚本>`。

### 脚本组织规范(命名 / 分批 / 内部结构)

复现脚本按 **`s<阶段号>_<批次字母>.sh`** 命名、按逻辑分批,便于独立重跑、定位失败、控制超时:

- **命名**:`s1_a.sh`、`s1_b.sh`、`s2_a.sh`、`s3_b.sh` ……"阶段号"对齐报告 step(S1/S2/S3),同阶段内按执行顺序用 `_a/_b/_c` 分批。自检、换源等一次性辅助操作可直接 `docker exec`,不必都落脚本。
- **分批粒度**(每批是一个**可独立重跑**的逻辑块):
  - **重操作单独成批**:大文件下载(CANN toolkit/ops 的 `.run` 包)、长时间编译(`bash build.sh`,常 200s+)、首次会失败的依赖脚本(`install_deps.sh`)各拆一批——便于设超时、失败时只重跑这一批。
  - **按依赖顺序排**:批次内命令前后依赖,批次间也顺序(S1 先于 S2/S3);**核心核实命令(build / `--run` / 精度验证)单独成批**,完整捕获业务输出。
  - 参考拆法:S1 ≈ clone+自检 / `install_deps` 首次 / 通用工具(pigz+googletest)/ CANN 下载安装 / 验证+`install_deps` 重跑+pip;目标阶段按"编译运行 / 目录探查 / 其它"分批。
- **脚本内部结构**(每批统一):
  ```bash
  #!/usr/bin/env bash
  set +e                                                   # 命令失败不中断,逐条记录
  source /usr/local/Ascend/cann/set_env.sh 2>/dev/null     # S2 及之后需要
  cd /tmp/devx_workspace                                   # 按报告 S1 记的 clone 路径
  echo "===== [S?-??] 报告原命令摘要 (报告 success=? 报告dur=?) ====="   # 标编号+报告判定+报告耗时,便于核对与耗时指标核实
  START=$SECONDS
  <命令> > /tmp/xxx.log 2>&1                               # 长输出存容器内临时日志
  echo "RC??=$? 耗时=$((SECONDS-START))s"
  grep -iE "error|fail|pass|skip|..." /tmp/xxx.log | head  # 只回显关键行
  cat /tmp/run.log                                         # 测试/核实类:完整业务输出(pass/failed/精度/golden)
  ```
  要点:`set +e` 逐条记录;每条 echo 行**标注报告 `success` 与 `duration`**(报告dur,取自报告该 action 的 `duration` 字段),便于和本次 `$SECONDS` 实测耗时对照、核实报告耗时类指标(如 `SDX_BUILD_TIME_SEC`);每条 `命令 > log 2>&1; echo RC=$?`(**绝不**接 `| tail`/`| head`,管道会伪装失败为成功——见核心执行规则 4);耗时命令用 `$SECONDS` 计时;**核实/测试类命令务必 `cat` 完整业务输出**(RC=0 ≠ 功能成功,要看 pass/failed、精度比对)。

---

## 工作流

工作流分两部分:**第一部分 执行阶段**(严格忠于报告,先 S1 后指定阶段,不碰项目文档)和**第二部分 分析阶段**(此时才引入文档/源码对照核实)。

---

### 第一部分:执行阶段(严格忠于报告)

#### 阶段 0｜解析输入,定位阶段

1. 读 JSON 报告,取 `project.project_id` → 定 `{项目名}` 与工作目录。
2. 确认**用户指定复现的阶段** → 映射 `step_id`(见阶段映射表)。校验该阶段 `not_evaluated=False` 且 `actions` 非空;否则告知用户并请求改指定。
3. 从报告提取两类命令:
   - **S1 环境基线命令**:`journey_steps` 里 `step_id=S1_SETUP` 的 `per_project_assessments[0].actual_path.actions[]` 中所有 `git_clone` 与 `shell_exec`(**按报告顺序**)。
   - **目标阶段命令**:用户指定阶段的 `actual_path.actions[]` 中所有 `git_clone` 与 `shell_exec`(**按报告顺序**)。
4. 从报告提取**待核实痛点**:目标阶段 `task_completion.task_details[]` 的每条 `pain_points` / `failure_reason`,以及该阶段 `cons`。
5. 记录 S1 装了哪些工具/依赖(从 S1 的 `task_details.observations` 与 `actions.detail` 摘出,如 gcc/cmake/python/特定包版本),供后续"环境是否一致"对照。

#### 阶段 1｜起容器 + 自检

1. `mkdir -p test_<项目名>/{scripts,log}`,输入 JSON 放 `log/`。
2. 用上文固定 `docker run` 命令起 `cann_test_{使用者}_{项目名}`(已存在则先 `docker rm -f` 重建,保证干净)。
3. 自检:`npu-smi info`、`ls /dev/davinci*`、镜像内基础工具情况。自检结果记入 `log/container_check.log`。

#### 阶段 2｜按 S1 配置环境(环境基线,严格按 S1 原样)

**目标:让容器环境与报告 S1 记录一致,为后续阶段铺底。** 逐条按 S1 `actions` 顺序执行其 `git_clone`/`shell_exec`:

- **照 S1 原样执行**:clone 用 S1 记的 `url`/`branch`/`path`;装依赖用 S1 记的命令原样跑。**不补装、不修正、不对齐文档**。
- **换源仅限让 S1 那条命令能跑**:S1 记的 pip/apt/git 源拉不动时,换镜像源让**同一条命令、同一个包**跑起来;**不替换为文档里的其它命令/版本**。
- 每条捕获真实退出码(`cmd > log 2>&1; echo RC=$?`),全过程记 `log/s1_setup.log`。
- 全程记录:S1 报告声明装了什么 → 本次实际装成功什么、哪些与报告不一致(版本/缺失),供"环境一致性"判定。
- 非项目耦合的通用安装踩坑(见文末踩坑库)可直接用,不在装环境上反复栽跟头。

> S1 配完后,**不要**急着对齐项目文档;环境是否"符合项目要求"留到分析阶段判定。本阶段只对齐"报告 S1 记录"。

#### 阶段 3｜复现用户指定阶段

逐条按目标阶段 `actions` 顺序执行其 `git_clone`/`shell_exec`:

- **照报告原样执行**目标阶段记录的命令(clone 若 S1 已 clone 且路径相同,可复用,不必重复;以报告记录为准)。
- 每条**捕获真实退出码**(`cmd > log 2>&1; echo RC=$?`,**绝不接** `| tail`/`| head`);过程记 `log/s<阶段号>_<名>.log`(如 `log/s3_build.log`)。
- **RC=0 也要读业务输出**:对验证/测试/运行类命令,继续读 stdout/stderr 里的 pass/failed、内部 `ret=N`、golden 比对、精度误差,判定"功能是否真成功",而不止看退出码。
- 遇到失败:照报告原样复现到失败点即可(不绕过、不修),如实记录失败命令、退出码、报错、业务输出。换源同理,仅限让报告同一条命令能跑。

#### 阶段 4｜(执行阶段小结)如实记录每条结果

把阶段 2、3 的每条命令落成"命令 / 真实退出码 / 业务输出摘要 / 成功或失败 / 失败报错"清单,作为分析与写报告的依据。**此阶段不下结论、不归因、不碰文档**。

---

### 第二部分:分析阶段(引入文档/源码对照)

#### 阶段 5｜报告该阶段结论逐条核实是否成立

对目标阶段每条 `pain_points` / `failure_reason` / `cons`,逐条判定在干净环境、按报告用法下**是否成立**。从四个角度查:

1. **是否与客观达成矛盾**:`task_achieved=True` / `achievement_rate=100%`,却把过程波折当成阻塞性问题。
2. **退出码是否被管道掩盖**:报告把被 `| tail` 伪装的 RC=0 当成功,或反之;以本次真实退出码为准。
3. **定性是否夸大**:把"已解决的小波折"写成"阻塞性失败"、"跑不通"。
4. **根因是否站得住**:对照项目源码/README,报告说的根因(缺参数/缺依赖/脚本缺陷)在源码里是否成立。

每条给出:**痛点原文 / 报告判定 / 本次复现实测 / 是否成立(成立/不成立/部分) / 判定依据(引源码或日志)**。

#### 阶段 6｜三分类归因

对复现路上遇到的**每个障碍**(无论报告是否提及),归因并记录解决方式:

- **项目问题**:按项目文档/源码跑不通、文档不明确、代码 bug、依赖声明缺失等(项目真缺陷)。
- **环境问题**:容器/驱动/工具链版本、网络源等(换源、补通用工具后即解决,与项目逻辑无关)。
- **用法问题**:报告/本次用错了命令、参数、路径(纠正用法后即通)。

#### 阶段 7｜环境一致性 + 文档符合性判定(此时才对齐文档)

- **环境一致性**:本次按 S1 装的环境,与报告 S1 记录是否一致(工具/版本/依赖)。
- **文档符合性**(此时才引入项目文档对照):报告装的、本次装的,是否符合项目 README/文档要求(如要求的 gcc/cmake 版本区间、必装依赖)。此项只做"是否符合文档"的事实判定,不据此回头改执行阶段。

#### 阶段 8｜写结论报告

汇总写入 `test_<项目名>/log/repro_report.md`(结构见下)。

---

## 结论报告 `repro_report.md` 模板

```markdown
# <项目名> <复现阶段> 复现验证报告

## 元信息
- 报告: <report_id> (生成于 <generated_at>)
- 项目: <project_id> / repo <repo_url> / branch <branch>
- 复现阶段: <step_id 阶段名>  | 环境基线: S1_SETUP
- 容器: cann_test_{使用者}_<项目名>  | 镜像: guoqiangqi/cogito:202606150944
- 复现时间: <本次>

## 一、S1 环境基线复现(按报告 S1 严格配置)
| # | S1 记录命令 | 真实退出码 | 结果 | 备注(与报告一致性) |
|---|---|---|---|---|
- S1 报告声明装的 vs 本次实际装的: …
- 环境一致性结论: …

## 二、<复现阶段> 命令逐条复现
| # | 报告记录命令 | 真实退出码 | 业务输出摘要 | 功能是否成功 | 失败报错 |

## 三、痛点/失败结论 核实(是否成立)
| 痛点原文(来源) | 报告判定 | 本次复现实测 | 是否成立 | 判定依据 |
|---|---|---|---|---|
- 不成立/夸大清单: …

## 四、复现障碍 三分类归因
| 障碍 | 分类(项目/环境/用法) | 解决方式 |
- 项目真问题清单: …

## 五、结论
- <复现阶段>是否如报告所述复现成功: …
- 痛点核实汇总: 共 N 条, 不成立 M 条 …
- 项目真缺陷: …
```

---

## 辅助踩坑库(非项目耦合,可直接复用)

> **沉淀规则**:本库只收**非项目耦合的通用踩坑**——装环境/工具链/依赖时的通用手法(换源、通用包安装技巧、环境变量、NPU 基础设施)。**严禁**收项目耦合结论(某项目某脚本的根因、某次复现的具体数值、某项目特定配置)。每条写清"症状→通用解法"。
> 复现装环境卡住时先查本库;装环境成功后,若用了新的通用手法,补进本库。

### 通用换源 / 加速
- **pip 换国内源**:`pip install -i https://pypi.tuna.tsinghua.edu.cn/simple <pkg>` 或 `pip config set global.index-url ...`。仅用于让报告同一条 pip 命令跑通,不换包/版本。
- **apt 换源**:容器内 apt 慢/失败时换镜像源(如华为云/清华),再跑报告原 apt 命令。
- **gitcode / github clone 慢或超时**:加 `--depth=1` 浅克隆(仅加速,不改 url/branch);或换镜像。仍以报告记的 url/branch 为准。
- **cmake/源码下载慢**:换国内镜像下载同一版本,不换版本。

### 通用环境 / NPU 基础设施
- **NPU 不可见**:`npu-smi info` 无设备 → 检查容器是否挂了 `/dev/davinci*` 与 driver 挂载、`LD_LIBRARY_PATH` 是否含 driver/lib64 与 dcmi。
- **`LD_LIBRARY_PATH` 缺失类报错**(找不到 driver/lib64 下 .so):按起容器命令设的值补齐(已在 `-e` 注入,容器内新 shell 用 `bash -lc` 或显式 export)。
- **gcc/cmake/ccache 等基础工具缺失**:照 S1 报告记的命令装;apt 装不到目标版本时用通用方式(源码/通用 PPA),但版本区间以 S1 报告记录为准。
- **Python 版本/包**:照 S1 记的 Python 与包版本装;通用包(如 numpy)装不上按通用换源处理。

### 沉淀新条目(复现中遇到通用问题时)
> 格式:`### <症状关键词>` + `症状:` + `通用解法:` + `(仅适用:非项目耦合)`。判定不确定时,宁可不放,避免污染为项目耦合结论。
