查询日志表

记录 Agent 每一次生成的搜索关键字（可能是多个词）。
sql

CREATE TABLE query_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    query_keywords TEXT NOT NULL,         -- Agent 转化后的关键字，如 "快速排序 递归"
    original_question TEXT,               -- 原始自然语言问题（可选，用于分析）
    session_id TEXT,                      -- 会话标识，关联多轮交互
    user_id TEXT,                         -- 可选
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

1.3 查询-代码反馈表（记录有效性）

这是 “有用日志”的核心，记录了某次查询后，用户（或 Agent）与特定代码片段的交互结果，从中可以挖掘出“哪个查询真正解决了问题”。
sql

CREATE TABLE query_code_feedback (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    query_log_id INTEGER NOT NULL REFERENCES query_log(id),
    code_id INTEGER NOT NULL REFERENCES code_snippets(id),
    -- 有效性指标（按需选用）
    was_adopted INTEGER DEFAULT 0,       -- 1: 最终被采纳/复制/执行成功，0: 仅浏览
    click_count INTEGER DEFAULT 1,       -- 该次查询中，此代码被点击/展开次数
    dwell_time_ms INTEGER,               -- 在代码上的停留时长（毫秒）
    user_rating INTEGER,                 -- 显式评分 (1-5)，若有
    feedback_time DATETIME DEFAULT CURRENT_TIMESTAMP
);

    was_adopted 是最强的有效性信号（Agent 判断该代码解决了当前问题，或用户选中粘贴）。

    综合这些字段，你可以计算一个 有效性得分，例如：
    text

    score = (was_adopted * 10) + log(click_count + 1) + log(dwell_time_ms + 1) * 0.01
2. 为查询日志建立 FTS5 索引（实现“以搜代搜”）

对 query_log.query_keywords 建 FTS5 索引，当 Agent 产生新的关键字时，快速匹配出历史上语义/关键词相似的查询。
sql

CREATE VIRTUAL TABLE query_log_fts USING fts5(
    query_keywords,
    content='query_log',
    content_rowid='id',
    tokenize='porter unicode61 remove_diacritics 2'  -- 英文可用 porter 词干，中文需配合分词
);

-- 保持同步的触发器
CREATE TRIGGER query_log_ai AFTER INSERT ON query_log BEGIN
    INSERT INTO query_log_fts(rowid, query_keywords) VALUES (new.id, new.query_keywords);
END;
-- ... delete 和 update 触发器类似

3. 利用“有用日志”加速搜索的具体方法

当 Agent 收到一个新问题，并将其转化为关键字 :new_keywords 后，按以下流程 优先利用历史有效日志：

    找相似历史查询
    在 query_log_fts 中搜索与 :new_keywords 最相关的查询日志。
    sql

    SELECT ql.id, ql.query_keywords, bm25(query_log_fts, 0) AS relevance
    FROM query_log_fts
    JOIN query_log ql ON ql.id = query_log_fts.rowid
    WHERE query_log_fts MATCH :new_keywords
    ORDER BY relevance
    LIMIT 20;

    聚合这些相似查询的“有效性”高代码
    对上一步得到的 top_k 个历史查询 ID，找出它们之中 被采纳最多、有效性得分最高 的代码片段。这就是“历史证明有效”的答案。
    sql

    WITH similar_queries AS (
        SELECT rowid AS log_id, bm25(query_log_fts, 0) AS sim_score
        FROM query_log_fts
        WHERE query_log_fts MATCH :new_keywords
        ORDER BY sim_score
        LIMIT 20
    )
    SELECT
        cs.id,
        cs.title,
        cs.code,
        -- 加权后的总有效性得分：相似度 * 累积有效性
        SUM( qcf.was_adopted * 10 + qcf.click_count ) * AVG(sq.sim_score) AS weighted_score
    FROM similar_queries sq
    JOIN query_code_feedback qcf ON qcf.query_log_id = sq.log_id
    JOIN code_snippets cs ON cs.id = qcf.code_id
    GROUP BY cs.id
    ORDER BY weighted_score DESC
    LIMIT 10;

    决定搜索策略

        若相似查询数量充足且得分高（例如加权最高得分 > 阈值），可直接将上述结果作为“缓存答案”返回给用户，完全跳过对代码库的大规模 FTS 搜索。这就是加速的关键——将实时搜索转化为历史日志匹配。

        若历史匹配不足，则回退到对 code_snippets 的全文搜索（代码库也需要建 FTS5 索引），并正常记录本次查询及后续反馈。

    记录新查询与反馈，形成闭环

        无论走哪条路径，新的 query_log 都要记录。

        当用户/Agent 最终选择了某个代码片段时，写入 query_code_feedback，更新其有效性数据，让未来相似查询能更快命中。

4. 有效性设计：让日志“更聪明”

除了被动收集反馈，还可以主动设计 时间衰减 和 反作弊：

    时间衰减：代码库会演进，太老的反馈可能过时。在聚合时乘以衰减因子：
    sql

    ... * (1.0 / (1 + (julianday('now') - julianday(qcf.feedback_time)))) ...

    全局热度 vs 查询相关性：

        全局热门代码（被所有查询高频采纳）可能淹没个性化推荐，可在计算得分时除以代码的总采纳次数（类似 TF-IDF），让结果更贴合当前查询。

    Agent 自动标记采纳：若你的 Agent 能判断任务执行成功（如编译通过、测试通过），可自动设置 was_adopted = 1，无需人工反馈。

5. 完整表结构汇总
sql

-- 代码库
CREATE TABLE code_snippets (...);
-- 代码 FTS（用于回退搜索）
CREATE VIRTUAL TABLE code_fts USING fts5(title, description, code, content='code_snippets', content_rowid='id');

-- 查询日志 + FTS
CREATE TABLE query_log (...);
CREATE VIRTUAL TABLE query_log_fts USING fts5(...);

-- 有效性反馈
CREATE TABLE query_code_feedback (...);
CREATE INDEX idx_feedback_qid ON query_code_feedback(query_log_id);
CREATE INDEX idx_feedback_cid ON query_code_feedback(code_id);

6. 总结：加速的本质

通过 query_log_fts 对新查询进行相似匹配，再用 query_code_feedback 中记录的“有效性得分”直接推荐历史高采纳代码。这样，高频相似查询不再每次都重搜整个代码库，实现了 “搜索→采纳→加速未来搜索” 的循环。有效性字段（尤其是 was_adopted）让日志从无用噪声变为可复用的知识资产。