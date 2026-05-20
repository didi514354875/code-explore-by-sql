一、 为什么 FTS5 能完美解决“一行一文件”的 Token 浪费问题？
如果您用传统的 Vector DB（向量数据库），整文件存储是灾难。但如果您用 SQLite 的 FTS5，整文件存储反而是标准且最高效的用法，核心魔法在于 FTS5 的 snippet()（片段提取） 功能。
1. 精准的代码片段提取 (Snippet Extraction)
在 FTS5 中，您把整个几千行的 BasePassPixelShader.usf 存入数据库的一行。当 Agent 搜索关键词（例如 Roughness 和 Lumen）时，您并不需要把整个文件返回给 Agent。
您可以让系统执行如下 SQL 查询：
code
SQL
SELECT 
    filename, 
    snippet(shader_table, 1, '<<<', '>>>', '...', 20) AS matched_code
FROM shader_table 
WHERE content MATCH 'Lumen AND Roughness' 
ORDER BY rank LIMIT 3;
结果：数据库会自动且极速地返回包含关键词的前后 20 个单词的代码片段，并用 <<< >>> 标记出来。
Token 消耗暴降：Agent 看到的不再是上万 Token 的完整文件，而是高度浓缩的、带有上下文的几十个 Token 的代码块。这不仅极大地节约了 Token，而且大模型的注意力会高度集中，回答准确率直线飙升。
2. 代码搜索的终极杀器：毫秒级精准匹配
Unreal Engine Shader 包含了大量特定的宏、变量名和函数签名（比如 FGBufferData, #define USE_RAYTRACING）。
向量大模型（Embedding）在处理这些“火星文”符号时往往很吃力（语义模糊）。
而 FTS5 构建的是倒排索引 (Inverted Index)。Agent 直接把变量名作为关键词去 MATCH，无论代码库有几百万行，查询速度都在毫秒级，而且是 100% 精准命中。
二、 架构演进：如何让这个系统在实际开发中完美运转？
为了让这个方案达到您“提速、省钱、准”的最终目的，我建议在工程细节上做以下设计：
1. 给 Agent 配备“双刃剑”工具 (Tool Design)
Agent 不需要直接写 SQL，您给它封装两个工具：
工具 A：search_code(keywords)
底层调用 FTS5 并使用 snippet()，只返回代码摘要。让 Agent 快速浏览哪些文件包含它要找的东西。
工具 B：read_file_lines(filename, start_line, end_line)
如果 Agent 看了 snippet() 觉得不够，它可以通过这个工具，精准读取那个文件的第 100 到 150 行。
(这样做，既利用了整文件存储的完整性，又实现了 Token 消耗的按需分配)
2. FTS5 的分词器陷阱 (Tokenizer Setup)
默认的 FTS5 分词器是针对自然语言（英文单词）的，它遇到标点符号会截断。Shader 代码里全是 . 和 _（比如 Material.Roughness）。
核心优化：建立 FTS5 表时，一定要使用 Trigram (trigram tokenizer)，或者自定义分词规则（将 _ 等视为字符的一部分）。这样 Agent 搜索 GetGBuffer 时，才能精确匹配出完整的函数名。
3. 您的点睛之笔：查询模板缓存 (Query Routing Cache)
在这个 FTS5 架构下，您的“查询模板”想法将发挥出 200% 的威力。
用户：“UE5 怎么把自发光写进 GBuffer？”
Agent 首次处理：思考 -> 决定调用 search_code('GBuffer Emissive') -> 阅读 Snippet -> 发现不够 -> 调用 read_file_lines('ShadingModels.ush', ...) -> 给出正确答案。 （耗时 15秒，消耗 3000 Token）。
系统记录：将 "自发光写进 GBuffer" 的语义特征，直接绑定到这条成功的 FTS5 SQL 语句或最终的代码片段上。
下一个用户提问：直接命中缓存，无需 Agent 推理，系统瞬间从 FTS5 提取对应代码片段丢给 LLM 生成人类语言回答。（耗时 2秒，消耗 500 Token）。
最终总结
如果您想表达的是 FTS5（或者是类似 BM25 的倒排索引数据库，比如 Elasticsearch），那么您的完整思路：【一文件一记录存储】 + 【FTS5 提取 Snippet】 + 【Agent 检索】 + 【记忆查询模板】，不仅完全合理，而且是目前业界处理庞大代码库（Codebase RAG）最实用、成本最低、落地效果最敏捷的架构之一。
它完美避开了向量数据库在代码检索时的“水土不服”，又用 snippet() 巧妙化解了“整文件塞入”带来的 Token 黑洞，非常值得动手去实现！
