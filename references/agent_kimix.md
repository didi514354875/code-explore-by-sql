 KimiX Context HistoryIndex 与 Retrieve/Compact 逻辑流程分析

  一、核心架构概览

  ┌──────────────────────────────────────────────────────────────────────┐
  │  KimiSoul._step() 每步执行                                           │
  │                                                                      │
  │  2e.1 通知投递                                                        │
  │  2e.2 动态注入 ← _maybe_auto_retrieve_history() ← HistoryIndex      │
  │  2e.3 历史归一化                                                     │
  │  2e.4 LLM 调用                                                       │
  │  2e.5 使用情况统计更新                                                │
  │  2e.6 工具执行                                                       │
  │  2e.7 上下文增长 → context.append_message → _on_append → index_messages│
  │  2e.8 结果判定                                                       │
  └──────────────────────────────────────────────────────────────────────┘
           │                    │                         │
           ▼                    ▼                         ▼
    compact_context()    _maybe_auto_retrieve     HistoryIndex
    → mark_compacted()   → search_with_recency    (BM25 内存索引)
    → history_index.save → 三层检索注入            (JSON 文件持久化)

  二、HistoryIndex 详解

  文件: kimi-cli/src/kimi_cli/soul/history_index.py

  数据结构

  class HistoryIndex:
      _index: InvertedIndex          # BM25 倒排索引（来自 kimix.retrieval）
      _tokenizer: NgramTokenizer(n=2) # 二元组分词器
      _searcher: Searcher            # BM25 搜索器
      _turns: list[dict]             # 所有 turn 的元数据列表
      _persist_path: Path            # JSON 持久化路径
      _doc_id_counter: int           # 文档 ID 计数器

  # 每个 turn 的结构
  {
      "turn_id": 0,           # 单调递增 ID
      "timestamp": 1718000000.0,  # Unix 时间戳
      "role": "user",         # "user" 或 "assistant"
      "text": "...",           # 消息文本
      "is_compacted": False,  # 是否已被压缩
  }

  容量上限: _MAX_TURNS = 500

  索引流程

  1. 消息追加触发
     context.append_message(msgs)
       → _on_append 回调（KimiSoul.__init__ 中注册）
         → history_index.index_messages(msgs)

  2. index_messages 内部
     for msg in messages:
       if msg.role not in {"user", "assistant"}: skip  # 跳过 system/tool
       text = 提取 TextPart
       turn = {turn_id, timestamp, role, text, is_compacted: False}
       _turns.append(turn)
       tokens = _tokenizer.tokenize(text)     # 二元组分词
       _index.add_document(turn_id, tokens)   # 加入倒排索引
       _doc_id_counter += 1

     while len(_turns) > 500:  # 超出上限丢弃最老的
       _turns.pop(0)

  检索流程

  search(query, top_k=3) — 纯 BM25 搜索：

  query → tokenize → BM25 搜索 → 返回 [{turn_id, role, text, is_compacted, score}]

  search_with_recency(query, top_k, recency_weight) — BM25 + 时间衰减：

  1. candidates = search(query, top_k=top_k * 3)  # 先取3倍候选
  2. for each candidate:
       hours_ago = (now - turn.timestamp) / 3600
       boost = 1.0 + recency_weight * exp(-hours_ago / 24.0)
       boosted_score = bm25_score * boost
  3. 按 boosted_score 排序，取 top_k

  时间衰减曲线:
  - 1 小时前: boost ≈ 1.0 + 1.0 × e^(-0.04) ≈ 1.96
  - 24 小时前: boost ≈ 1.0 + 1.0 × e^(-1) ≈ 1.37
  - 72 小时前: boost ≈ 1.0 + 1.0 × e^(-3) ≈ 1.05

  持久化

  save():  # 写 JSON 文件
      {doc_id_counter, turns: [...]} → orjson.dumps → persist_path.write_text

  load():  # 读 JSON 文件 + 重建倒排索引
      persist_path.read_text → orjson.loads → _turns
      for turn in _turns: _index.add_document(turn.turn_id, tokenize(turn.text))

  存储路径: {session_dir}/history_index/{session_id}.json

  三、三层自动检索机制（_maybe_auto_retrieve_history）

  触发条件（三个条件全部满足）:
  1. 至少一个检索层启用（auto_retrieve_history / auto_retrieve_working_memory / auto_retrieve_recency_memory）
  2. current_step_no == 1（每个 turn 的第一步，不重复检索）
  3. current_turn_user_text 长度 ≥ 10（避免短查询浪费 token）

  Token 预算: auto_retrieve_max_tokens_per_turn = 2000（默认），每条注入约 15 token 包装开销

  去重: _recently_retrieved_turn_ids 集合，保留最近 10 个，防止连续重复注入

  A 层: 长期记忆（Long-term Memory）

  条件: auto_retrieve_history == True
  过滤: is_compacted == True（只看已被压缩掉的历史）
  阈值: score >= auto_retrieve_history_threshold (默认 5.0)
  注入格式:
    [Auto-retrieved from past conversation — relevance: 5.23]
    > **user**
    > 用户之前讨论的文件路径和决策内容...

  B 层: 工作记忆（Working Memory）

  条件: auto_retrieve_working_memory == True
  过滤: is_compacted == False（只看当前对话中的）且排除最近 2 条（已在上下文末尾）
  阈值: score >= auto_retrieve_working_memory_threshold (默认 5.0)
  注入格式:
    [Relevant context from our current conversation]
    > **assistant**
    > 之前讨论过的中间结论...

  C 层: 时效记忆（Recency Memory）

  条件: auto_retrieve_recency_memory == True
  过滤: 所有 turn（compacted + non-compacted），使用 boosted_score
  阈值: boosted_score >= auto_retrieve_recency_memory_threshold (默认 4.0)
  注入格式:
    [Recently discussed — relevance: 6.12]
    > **user**
    > 最近讨论过的话题...

  执行顺序: A → B → C，每层最多注入 1 条，总计最多 auto_retrieve_max_injections_per_turn = 3 条

  四、Compaction 与 HistoryIndex 的协同

  compact_context() 流程:
    1. SimpleCompaction.prepare(messages)
       → 找到 preserve_start_index
       → to_compact = messages[:preserve_start_index]
       → to_preserve = messages[preserve_start_index:]
       → 首条消息始终保留（primacy bias）

    2. SimpleCompaction.compact(messages, llm)
       → 序列化 to_compact 为 TextPart
       → LLM 调用生成摘要
       → 返回 CompactionResult(messages=[summary_user_msg, ...to_preserve])

    3. 关键协同点:
       self._history_index.mark_compacted()    # ← 标记所有 turn 为 is_compacted=True
       self._history_index.save()               # ← 持久化到磁盘
       self._recently_retrieved_turn_ids.clear() # ← 清除去重记录
       await self._context.clear()               # ← 清空上下文
       await self._context.append_message(compaction_result.messages)  # ← 写入压缩后消息

  mark_compacted() 的意义：压缩后，原始对话不再在 LLM 上下文中，但 HistoryIndex 中仍保留完整索引。标记为 is_compacted=True 使得自动检索可以将这些 turn 归类为"长期记忆"，在后续 turn 中按需召回。

  五、ContextRetrieval 工具

  文件: kimi-cli/src/kimi_cli/tools/context_retrieval.py

  这是一个注册到 Agent 工具集的 LLM-callable 工具，允许 Agent 主动搜索历史：

  class ContextRetrieval(CallableTool2):
      name = "ContextRetrieval"
      description = "搜索归档的对话历史..."

      async def __call__(self, params):
          results = self._history_index.search(params.query, top_k=params.k)
          # 格式化返回，标注 [compacted] 标记和 relevance 分数

  与自动检索的互补关系：
  - 自动检索：每 turn 第一步自动触发，无需 LLM 决策
  - ContextRetrieval：LLM 主动调用，按需查询，适用于"我记得之前讨论过..."

  ---
  六、映射到 Pi 架构的改造方案

  方案 A: 纯 Extension 实现（推荐，零侵入）

  ┌──────────────────────────────────────────────────────┐
  │  Pi Extension: history-index                         │
  │                                                      │
  │  ┌─ 初始化 ────────────────────────────────────────┐ │
  │  │ session_start:                                  │ │
  │  │   historyIndex = new HistoryIndex(sessionDir)   │ │
  │  │   historyIndex.load()                           │ │
  │  └─────────────────────────────────────────────────┘ │
  │                                                      │
  │  ┌─ 写入路径 ──────────────────────────────────────┐ │
  │  │ message_end (role=user/assistant):              │ │
  │  │   historyIndex.indexMessages(message)           │ │
  │  │   historyIndex.save()                           │ │
  │  └─────────────────────────────────────────────────┘ │
  │                                                      │
  │  ┌─ 压缩协同 ──────────────────────────────────────┐ │
  │  │ session_before_compact:                         │ │
  │  │   historyIndex.markCompacted()                  │ │
  │  │   historyIndex.save()                           │ │
  │  │   recentlyRetrievedTurnIds.clear()              │ │
  │  │   → 可选：提供自定义 compaction 摘要             │ │
  │  └─────────────────────────────────────────────────┘ │
  │                                                      │
  │  ┌─ 读取路径（自动注入）──────────────────────────┐ │
  │  │ before_agent_start:                             │ │
  │  │   injections = maybeAutoRetrieveHistory(        │ │
  │  │     query: userText,                            │ │
  │  │     historyIndex, config                        │ │
  │  │   )                                             │ │
  │  │   → 注入为 custom message                       │ │
  │  └─────────────────────────────────────────────────┘ │
  │                                                      │
  │  ┌─ Agent 工具 ────────────────────────────────────┐ │
  │  │ 注册 ContextRetrieval tool:                     │ │
  │  │   pi.registerTool({                             │ │
  │  │     name: "search_history",                     │ │
  │  │     handler: (query, k) =>                      │ │
  │  │       historyIndex.search(query, k)             │ │
  │  │   })                                            │ │
  │  └─────────────────────────────────────────────────┘ │
  └──────────────────────────────────────────────────────┘

  所需 Pi Extension Hook 点（均已存在）:

  ┌────────────────────────┬─────────────────────────────────────┬──────┐
  │          Hook          │                用途                 │ 已有 │
  ├────────────────────────┼─────────────────────────────────────┼──────┤
  │ session_start          │ 初始化 HistoryIndex，加载持久化数据 │ ✅   │
  ├────────────────────────┼─────────────────────────────────────┼──────┤
  │ message_end            │ 索引新消息到 BM25                   │ ✅   │
  ├────────────────────────┼─────────────────────────────────────┼──────┤
  │ session_before_compact │ mark_compacted + save               │ ✅   │
  ├────────────────────────┼─────────────────────────────────────┼──────┤
  │ session_compact        │ 清除去重记录                        │ ✅   │
  ├────────────────────────┼─────────────────────────────────────┼──────┤
  │ before_agent_start     │ 自动检索注入 custom message         │ ✅   │
  ├────────────────────────┼─────────────────────────────────────┼──────┤
  │ Extension Tool         │ 注册 ContextRetrieval 工具          │ ✅   │
  ├────────────────────────┼─────────────────────────────────────┼──────┤
  │ context                │ 可选：检索结果作为上下文补充        │ ✅   │
  └────────────────────────┴─────────────────────────────────────┴──────┘

  Extension 需要自建的组件:
  1. BM25 索引库（纯 JS/TS 实现）: InvertedIndex + NgramTokenizer + BM25 Scorer
  2. HistoryIndex 类: 封装索引/搜索/持久化/标记逻辑
  3. Auto-retrieve 逻辑: 三层检索 + token 预算控制 + 去重
  4. 配置: 通过 Extension settings 暴露阈值参数

  方案 B: 核心层改造（侵入性强）

  如果选择在 Pi 核心层添加，需要修改以下文件：

  ┌─────────────────────────────────────────────────────┬────────────────────────────────────┐
  │                        文件                         │              修改内容              │
  ├─────────────────────────────────────────────────────┼────────────────────────────────────┤
  │ packages/agent/src/harness/types.ts                 │ 新增 HistoryIndexEntry 类型        │
  ├─────────────────────────────────────────────────────┼────────────────────────────────────┤
  │ packages/agent/src/harness/session/session.ts       │ buildSessionContext 中注入检索结果 │
  ├─────────────────────────────────────────────────────┼────────────────────────────────────┤
  │ packages/agent/src/harness/compaction/compaction.ts │ 压缩后调用 mark_compacted          │
  ├─────────────────────────────────────────────────────┼────────────────────────────────────┤
  │ packages/coding-agent/src/core/session-manager.ts   │ 新增 HistoryIndex 持久化路径管理   │
  ├─────────────────────────────────────────────────────┼────────────────────────────────────┤
  │ packages/coding-agent/src/core/agent-session.ts     │ _handleAgentEvent 中索引新消息     │
  ├─────────────────────────────────────────────────────┼────────────────────────────────────┤
  │ packages/coding-agent/src/core/agent-session.ts     │ prompt() 中调用自动检索            │
  ├─────────────────────────────────────────────────────┼────────────────────────────────────┤
  │ packages/coding-agent/src/core/system-prompt.ts     │ 或将检索结果注入 system prompt     │
  └─────────────────────────────────────────────────────┴────────────────────────────────────┘

  方案对比

  ┌────────────┬───────────────────────────┬──────────────────────┐
  │    维度    │    方案 A (Extension)     │   方案 B (核心层)    │
  ├────────────┼───────────────────────────┼──────────────────────┤
  │ 侵入性     │ 零侵入，独立 npm 包       │ 多文件修改，需 PR    │
  ├────────────┼───────────────────────────┼──────────────────────┤
  │ 可维护性   │ 跟随 Pi 版本独立升级      │ 紧耦合               │
  ├────────────┼───────────────────────────┼──────────────────────┤
  │ 性能       │ Extension hook 有调用开销 │ 直接函数调用，零开销 │
  ├────────────┼───────────────────────────┼──────────────────────┤
  │ 分发       │ 用户可选装                │ 所有用户默认拥有     │
  ├────────────┼───────────────────────────┼──────────────────────┤
  │ 配置灵活   │ Extension 自管理配置      │ 需改 settings schema │
  ├────────────┼───────────────────────────┼──────────────────────┤
  │ 自定义工具 │ pi.registerTool           │ 需改 tool registry   │
  ├────────────┼───────────────────────────┼──────────────────────┤
  │ 推荐场景   │ MVP / 实验阶段            │ 成熟后核心化         │
  └────────────┴───────────────────────────┴──────────────────────┘

  方案 C: 混合方案（最推荐）

  1. Phase 1 — 用 Extension 实现完整功能，验证价值
  2. Phase 2 — BM25 索引下沉到 packages/agent/src/harness/ 作为通用基础设施
  3. Phase 3 — 自动检索逻辑作为 buildSessionContext 的可选阶段

  关键差异需要适配的点:

  ┌───────────────────────────┬───────────────────────────────────────────────────────┬─────────────────────────────────────────────────────────────────┐
  │        KimiX 概念         │                      Pi 对应概念                      │                            适配说明                             │
  ├───────────────────────────┼───────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────┤
  │ _on_append 回调           │ _handleAgentEvent message_end                         │ Pi 用事件驱动而非回调                                           │
  ├───────────────────────────┼───────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────┤
  │ DynamicInjection          │ CustomMessageEntry / before_agent_start hook          │ Pi 有 custom message 类型可直接用                               │
  ├───────────────────────────┼───────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────┤
  │ Context.clear()           │ agent.state.messages = buildSessionContext().messages │ Pi 是不可变树，不需要 clear                                     │
  ├───────────────────────────┼───────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────┤
  │ mark_compacted()          │ CompactionEntry 已有此信息                            │ Pi 的 buildSessionContext 已知哪些 entry 在 compaction 边界之前 │
  ├───────────────────────────┼───────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────┤
  │ BM25 库 (kimix.retrieval) │ 需自建或引入 JS BM25 库                               │ 如 flexsearch、orama、或自实现                                  │
  ├───────────────────────────┼───────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────┤
  │ _MAX_TURNS = 500          │ 无限制（JSONL 全量）                                  │ 需要决定索引范围                                                │
  ├───────────────────────────┼───────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────┤
  │ NgramTokenizer(n=2)       │ 同上                                                  │ 中英文分词需特殊处理                                            │
  ├───────────────────────────┼───────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────┤
  │ JSON 文件持久化           │ SessionManager.appendCustomEntry                      │ 可用 Pi 原生的 custom entry 存储索引元数据                      │
  └───────────────────────────┴───────────────────────────────────────────────────────┴─────────────────────────────────────────────────────────────────┘
