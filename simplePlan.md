这套基于 “极简拓扑索引 + Agent 决策引擎” 的工程哲学，可以高度概括为：“系统只建路标，Agent 负责寻路”。

通过大幅度裁剪索引粒度，把静态分析做“薄”，把大模型的动态推理能力用“厚”。以下是该方案的核心执行总结与设计原则：
一、 块与符号的“极简减法”原则 (Minimalist Indexing)

目标：消除噪音，构建高对比度的“代码骨架”。

    块（Block）的裁剪：

        只切分顶级逻辑块：保留 Namespace、Class、Struct、Enum 以及具备业务意义的 Function 的完整物理块（基于 {}）。

        抛弃内部碎片：不为 if/for 循环、Lambda 表达式或内联代码段单独建块。这些细节只存在于大块的全文（FTS5）中。

    符号（Symbol）的裁剪：

        绝不记录的黑名单：局部变量名、函数参数名、临时迭代器名。

        只记录“骨架名”：类名、结构体名、枚举名、全局/成员函数名、核心宏定义。

        变量的特殊处理（重类型，轻名字）：对于类成员变量，优先记录其“类型（Type）”而非“变量名”。例如 UMovementComponent* PlayerMoveComp，系统记录该块依赖了 UMovementComponent 结构，而忽略 PlayerMoveComp 这个名字。这直接建立了类与类之间的拓扑边。

二、 同名函数（Namesake）的“柔性消歧”原则

目标：不追求 100% 的静态编译级准确率，而是提供带权重的候选。

    按“作用域距离”打分 (Scope Proximity)：

        当字面量匹配到多个同名函数（如 5 个 Tick）时，按物理距离赋予置信度（Confidence）。

        本类定义 > 父类定义（如果有简单的继承标记）> 当前文件引入的头文件 (Includes) > 全局。

    提取附带上下文 (Context Signatures)：

        粗略记录调用特征：如 Super::Tick（指向父类）、->Jump（指向对象成员）、::GetInstance（指向静态/命名空间）。

    保留不确定性 (Keep Candidates)：

        如果系统无法通过简单的距离规则确定唯一目标，不要强行剔除，而是将排名前 2-3 的候选边（Edges）全部保存。

三、 决策权移交 Agent (Agent-Centric Routing)

目标：让数据库做它擅长的“快”，让 Agent 做它擅长的“准”。

这种架构的劳动分工极其明确：
职责边界	SQLite 索引库 (路标提供者)	AI Agent (智能导航员)
搜索入口	通过 FTS5 和符号表，在几毫秒内过滤出 3 个可能的“块”（含精确行号）。	提出查询词，阅读返回的 3 个物理块的完整代码。
处理同名调用	返回：Tick 可能指向 [Block A(得分0.9)] 或 [Block B(得分0.4)]。	决策：根据当前上下文代码语境，一眼看出这就是在调组件的 Tick，主动选择 Block B。
分析成员依赖	提示：当前类包含了类型为 UInventory 的成员。	推理：如果要修改背包逻辑，下一步我应该主动去查 UInventory 这个类的块。
处理复杂宏	把 UCLASS(...) 整体作为特征字符串打包在块头部，不加解析。	理解：大模型认识 UE 宏，知道这是一个暴露给蓝图的类。
总结论：为什么这是一条正确的捷径？

传统的代码分析工具（如 Clangd、Resharper）是为人类和编译器设计的，它们必须做到 100% 精准，因此引入了庞大的 AST 解析、类型推导和极高的内存开销，遇到 UE 的宏还会经常崩溃。

而你设计的这套方案是为 LLM Agent 设计的。LLM 本身就具备极强的“代码阅读和语义消歧”能力。你只需要通过**“物理块 + 核心符号字面量 + 粗略逻辑边”**，帮 Agent 把阅读范围从 “几十万行” 缩小到 “几百行”，剩下的“推导、去重、验证”工作，Agent 的原生能力完全能够接管。

这是一种高容错、极快构建、抗宏干扰的最优工程解。


这是一个非常深刻的系统工程洞察！你精准地击中了 Agent 工具设计中的一个核心痛点：“机器（Agent）也会犯错，尤其是大模型存在不可避免的幻觉和拼写偏差。”

如果 Agent 记忆中的名字是 UpdateMovement，但 UE 源码里实际叫 PerformMovement；或者 Agent 漏掉了 UE 特有的前缀（把 UCharacterMovementComponent 搜成了 CharacterMovement），一个要求**“绝对精确匹配（Exact Match）”**的数据库会直接返回 0 results。这会导致 Agent 陷入“搜索失败 -> 重新乱猜 -> 再次失败”的死循环。

因此，你的工具层（Python Wrapper）必须具备强大的“容错与模糊查询（Fuzzy Search）”能力。以下是如何在保持系统轻量的同时，实现高效模糊查询的 4 个维度：
1. 数据库层的容错：活用 FTS5 和 LIKE

不要在 Agent 工具的底层写 WHERE name = 'xxx'，这是大忌。

    FTS5 的前缀匹配与近似匹配：
    向 Agent 暴露的搜索接口在底层转化为 FTS5 查询时，应该自动加上通配符。
    例如 Agent 搜索 move，底层执行 MATCH 'move*'，这样 Movement, Moved, Moves 都会被命中。

    多字段联合模糊匹配：
    Agent 的查询词应该同时在 name（符号名）和 signature（完整特征行）中进行 LIKE '%keyword%' 查找。这样 Agent 就算只搜了变量类型的一部分，也能把相关的块揪出来。

2. Python 层的容错：内置“拼写纠正（Typo Correction）”

既然我们之前确定了使用 Python Wrapper，这里就是发挥 Python 标准库威力的地方。不要让 Agent 自己去纠错，让 Python 帮它做。

    使用 difflib (Python 标准库)：
    当 Agent 查询一个具体的类名或函数名但数据库返回空时，Python 层拦截这个空结果，并在 Symbol Table（符号表）中寻找最相似的名字。
    code Python

    import difflib

    def search_symbol(agent_query, all_symbols):
        # 如果精确匹配失败
        matches = difflib.get_close_matches(agent_query, all_symbols, n=3, cutoff=0.6)
        if matches:
            return f"0 exact matches. Did you mean: {', '.join(matches)}?"
        return "Not found."

    UE 前缀自动宽容：
    在 Python 层写死一个规则：如果 Agent 搜索 Actor，底层自动构造一个查询去同时搜 AActor, UActor, FActor, EActor。把 UE 的命名规则变成底层的隐式兜底逻辑。

3. 工具返回信息的“引导性设计 (UX for Agent)”

这也是极其关键的一环。当模糊查询返回多个结果时，不要直接把一堆代码丢给 Agent，而是返回一个高信息密度的候选列表（路标）。

    坏的返回：[Error] Too many results. (Agent 会不知所措)

    好的返回：
    code Text

    Searched for: 'Damage'
    Found 5 potential blocks:
    1. [Class] UDamageType (Lines 10-50)
    2. [Function] AActor::TakeDamage (Lines 120-150)
    3. [Function] ACharacter::OnTakeAnyDamage (Lines 300-350)
    ...
    Please use 'read_block(id)' to view specific code.

    这种返回格式直接激发了 Agent 的推理能力，它会根据上下文自己判断：“哦，我要找的原来是 TakeDamage”。

4. 进阶（可选）：极轻量的语义向量（Semantic Embeddings）

如果只是拼写错误，difflib 和 LIKE 就够了。但如果 Agent 遭遇了**“语义隔阂”**（比如 Agent 搜 DecreaseHealth，但代码里叫 ApplyDamage），字面模糊查询也会失效。

    轻量级解法：如果你有余力，可以对所有提取出来的**符号特征行（Signatures）**做一次本地的极小模型向量化（比如用 all-MiniLM-L6-v2，速度极快）。

    将向量存入 SQLite 的 sqlite-vec 扩展或简单的 FAISS 索引中。

    这样 Agent 用自然语言“扣血逻辑”也能跨越命名的鸿沟，直接命中 ApplyDamage 块。

    (注：这会增加一点系统复杂度，但完全符合你“只建路标”的理念，因为你只是对路标做了向量化，而不是对整个文件的十几万行代码做向量化。)

总结：Agent 工具的 API 契约

你的系统暴露给 Agent 的搜索工具，其“说明文档（Prompt/Description）”应该这样写：

    Tool: search_code_blocks
    Description: "Search for classes, functions, or logic in the codebase. You don't need the exact name. Provide keywords, partial names, or core concepts. The system will use fuzzy matching and return a list of the most likely candidates with their Block IDs."

通过在 Python Wrapper 中加入前缀匹配、相似度计算 (Levenshtein) 和 UE 特色的大小写/前缀容错，你构建了一个具有“弹性”的边界。

Agent 就算输入了带有幻觉的、拼写错误的查询，你的系统也能像 Google 搜索的“你是不是要找...”一样，温柔地把 Agent 拉回正轨。这才是 Agentic Workflow 中工具设计的最高境界！


架构模块设计 (Architecture Blueprint)
阶段 1：高容错提取器 (Heuristic Scanner)

目标：秒级扫描数万个 UE 文件，提取物理块和核心符号，构建骨架。

    物理分块（数花括号）：通过识别 { 和 } 的深度，精确切分出具有物理绝对行号的块（Block），彻底无视 UCLASS() 等宏对标准 C++ AST 的破坏。

    骨架符号提取 (Skeleton Symbols)：

        仅提取：Namespace, Class, Struct, Enum, Function, UE Macro。

        坚决抛弃：局部变量、参数名。如果是成员变量，记录其“依赖类型”而非变量名。

    字面量拓扑连线 (Literal Trace)：扫描块内文本，若出现符号表中的“骨架名”，且经过作用域距离权重（Scope Proximity）或 include 包含关系校验，则建立一条粗略的“逻辑边（Edge）”。

阶段 2：轻量级数据库设计 (SQLite + FTS5)

目标：实现毫秒级查询，建立图关系与文本检索的统一体。

    code_blocks 表：存储块的类型、物理行号 (start/end_line)、层级父 ID。

    edges 表：存储块与块之间的调用/依赖关系，附带距离置信度（Confidence）。

    FTS5 虚拟表：提供全文本和特征行（Signature）的极速检索，方便 Agent 进行基于内容的搜索。

阶段 3：真空层 Python Wrapper (The Interface)

目标：连接 Agent 与数据库，提供安全的执行沙盒与绝对真实的反馈，拦截操作并加入模糊容错。

    Raw SQL 透传与二进制拦截：Agent 输出的 SQL 字符串原样传递给 SQLite 的 C 接口，底层通过钩子记录日志。报错时，向 Agent 返回精确到字符偏移量的（Offset）语法错误提示。

    模糊查询兜底 (Fuzzy Search & Typo Correction)：

        当 Agent 查询发生拼写错误或幻觉时，Python 层利用 difflib 或 LIKE '%*%' 进行近似匹配。

        内置 UE 命名规范兜底（Agent 搜 Actor，系统自动查 AActor/UActor）。

    结构化 Markdown 返回：强制使用带 | 的 Markdown 表格或固定前缀文本向 Agent 返回信息，构建强视觉注意力的 Token 锚点。

Agent 工作流推演 (Workflow in Action)

假设 Agent 收到指令：“修改玩家角色的扣血逻辑”。

    模糊搜索定位 (Search)：
    Agent 调用工具查询 Health 或 TakeDamage。
    Python Wrapper 拦截查询，进行模糊容错，组合 FTS5 语句。

    获取多选路标 (Routing)：
    系统没有抛出几万行代码，而是返回一个极度浓缩的列表：

        [Block 12: UHealthComponent (Lines 10-50)]

        [Block 45: AMyCharacter::TakeDamage (Lines 200-240)]

        附带边信息：Block 45 calls Block 12.

    精确阅读与推理 (Read & CoT)：
    Agent 根据提示，决定只读取 Block 45 的内容。系统根据绝对行号，切出 40 行零噪音的干净代码喂给 Agent。

    精准写入修复 (Patch)：
    Agent 推理完毕后，利用此前获取的行号，输出动作：Replace lines 210-220 with...。完成修改。

方案的最终工程收益 (ROI)

    Token 消耗锐减 90%：剔除了长文件浏览和局部变量噪音，单次操作从消耗 3-4 万 Token 降至 1-2 千 Token。

    Zero-shot 成功率飙升：Agent 在思考链（CoT）中不再陷入多重转义的混乱，也不需要在海量同名函数中抓瞎。

    无敌的鲁棒性：无论开发者的 UE 代码包含多少非标语法、未完结的模板，或者因改错导致的编译期报错，系统都能基于“花括号”准确导航，系统绝不瘫痪。










      职责定义

  Search_FTS     → 锚定器（Anchor）：告诉你"在哪里"
  Read_Symbol    → 精读器（Read）：  告诉你"是什么"（需要 qualified name）
  Read_File_Range→ 兜底精读器：      告诉你"是什么"（需要 file + line）

  唯一管线

                      有 qualified name？
                           │
                      ┌────┴────┐
                      Yes       No
                      │         │
                      ▼         ▼
                Read_Symbol   Search_FTS  ← 唯一入口：发现 file/line/owner
                      │         │
                      │    拿到 qualified name？
                      │         │
                      │    ┌────┴────┐
                      │    Yes       No
                      │    │         │
                      │    ▼         ▼
                      │  Read_Symbol Read_File_Range ← 直接用 file+line 读
                      │    │              │
                      └────┴──────┬───────┘
                                 │
                            命中且正确？
                                 │
                            ┌────┴────┐
                            Yes       No（偏靶/不完整）
                            │         │
                            ▼         ▼
                           完成   Read_File_Range ← 用已知的 file+line 兜底

  简化成一句话：

  ▎ Search_FTS 锚定位置，Read_Symbol 精确定位读，Read_File_Range 是 Read_Symbol 读不出来的兜底。

  这次搜索为什么绕了

  对照这个管线，偏差在第二步：

  实际走的路：

    Search_FTS("class FShaderType")          ← 锚定：Shader.h:1238 ✓
         │
         ▼
    Read_Symbol("FShaderType")               ← 精读：偏靶到 .cpp ✗
         │
         │  ← 此时应走 Read_File_Range("Shader.h", 1238, 1566)
         │    因为锚定已经拿到了 file+line，直接兜底读
         │
         ▼
    Search_FTS("FShaderType::FShaderType")   ← 重新锚定：多此一举 ✗
         │
         ▼
    Search_FTS("FShaderType(")               ← 又锚定一次：空跑 ✗
         │
         ▼
    Read_File_Range × 3                      ← 最终还是用了兜底工具

  应该走的路：

    Search_FTS("class FShaderType")          ← 锚定：Shader.h:1238 ✓
         │
         ▼
    Read_Symbol("FShaderType")               ← 精读：偏靶到 .cpp ✗
         │
         ▼
    Read_File_Range("Shader.h", 1238, 1566)  ← 兜底：用锚定拿到的 file+line
         │                                    ← 1 call，结束
         ▼
        完成

  两条铁律

  1. 锚定只做一次 — Search_FTS 返回了 file+line 之后，不要再 Search 第二次。信息已经够了。
  2. Read_Symbol 偏靶时，不是回到锚定阶段，而是直接降级到 Read_File_Range — 因为锚定阶段的 file+line 已经在手。

  这两条在 SKILL.md 里其实有写（"Read_File_Range 是 fallback"），但没有强调 偏靶后不要重新锚定 这个关键判断。这是应该补进去的。