符号提取分层机制分析

  设计意图 vs 实际实现

  项目在 configs.py 中定义了清晰的三层架构：

  ┌───────────┬─────────────────┬────────────────────────────────────────────────┐
  │    层     │     配置类      │                      职责                      │
  ├───────────┼─────────────────┼────────────────────────────────────────────────┤
  │ Language  │ LanguageConfig  │ 语法规则（C++ vs C#），按文件扩展名选择        │
  ├───────────┼─────────────────┼────────────────────────────────────────────────┤
  │ Framework │ FrameworkConfig │ 应用框架规则（Unreal/Generic），叠加在语言之上 │
  ├───────────┼─────────────────┼────────────────────────────────────────────────┤
  │ Project   │ ProjectConfig   │ 用户配置（扩展名、排除目录、模块推断）         │
  └───────────┴─────────────────┴────────────────────────────────────────────────┘

  设计目标是 Language x Framework 自由组合（如 Unreal C++ + Unreal C#）。但实际实现中，分层抽象有多处泄漏，逻辑分散到不该有的地方。

  ---
  问题 1: symbol_analyzer.py:_classify_block 绕过 LanguageConfig

  _classify_block() 接收了 lang: LanguageConfig 参数，但关键分类逻辑 硬编码了 C++ 关键字：

  # symbol_analyzer.py:139 — 硬编码了 namespace|class|struct|enum，没用 lang 的 regex
  re.search(r"\b(?:namespace|class|struct|enum)\b", open_text)

  # symbol_analyzer.py:253 — 硬编码 namespace 语法，没用 lang.namespace_re
  ns_match = re.match(r"(?:inline\s+)?namespace\s+(\w+)?\s*$", classifier_sig)

  # symbol_analyzer.py:273 — 硬编码 lambda 检测（C++ 特有）
  re.search(r"\[.*\]\s*[\(]", joined_clean)

  虽然 class_re、enum_re 正确地用了 lang.class_re / lang.enum_re，但 namespace 和 lambda 检测完全绕过了 LanguageConfig。如果支持新语言（如 Rust、Java），这些硬编码都会失效。

  ---
  问题 2: edge_extractor.py 完全不感知 Language 层

  这是最严重的分散问题。extract_edges() 接收 lang 参数但从未使用。所有正则全部硬编码 C++ 语义：

  # edge_extractor.py:25 — 只匹配 PascalCase，C# 的 camelCase 类型会被漏掉
  _TYPE_RE = re.compile(r"\b([A-Z][A-Za-z0-9_]+)\b")

  # edge_extractor.py:28 — C++ 作用域解析符 ::
  _STATIC_CALL_RE = re.compile(r"\b([A-Z][A-Za-z0-9_]+)::([A-Za-z_]...\(")

  # edge_extractor.py:31 — UE 特有的 Super::
  _SUPER_CALL_RE = re.compile(r"\bSuper::([A-Za-z_][A-Za-z0-9_]*)\s*\(")

  C# 用 . 代替 ::，用 base. 代替 Super::。这些应该由 LanguageConfig 提供，但目前 LanguageConfig 中根本没有定义 edge extraction 相关的 regex。Edge 提取逻辑完全脱离了分层设计。

  ---
  问题 3: code_block_summary.py 绕过整个配置系统

  这个模块创建了 硬编码的默认实例，完全绕过了分层配置：

  # code_block_summary.py:19-20
  _default_lang = make_cpp_language()
  _default_fw = make_generic_framework()

  然后：
  - _UE_MACRO_RE 硬编码了 UE 宏列表（symbol_analyzer.py:49），不用 FrameworkConfig.decoration_macro_re
  - _LOCAL_VAR_RE 硬编码了 C++ 类型修饰符（const|static|mutable|constexpr|volatile）
  - _CONTROL_FLOW_RES 硬编码了 C++ 控制流

  summarize_class_block() 接收 lang 和 fw 参数，但调用链上游（apply_view）从不传入它们——参数永远走 lang or _default_lang 的 fallback 路径。

  ---
  问题 4: unreal_rules.py 混淆 Language 与 Framework 层

  # unreal_rules.py:48-54 — 这是 C/C++ 语言级别的基础类型，不是 UE 框架特有的
  _BASIC_SKIP_TYPES = frozenset({
      "int8", "int16", "int32", "int64",
      "uint8", "uint16", "uint32", "uint64",
      "float", "double", "bool", "void", "int", ...
  })

  这些被放在 FrameworkConfig.skip_types 中，但它们是语言级别的关注点。如果将来添加 Java 或 Rust 框架配置，这些 C++ 基础类型仍然会被错误地混入。应该由 LanguageConfig 提供基础类型跳过列表。

  ---
  问题 5: bracket_scanner.py 假设 C/C++ 语法

  LanguageConfig 有 uses_braces: bool 字段，但 从未被检查。bracket_scanner.py 只处理 C/C++ 的注释/字符串语法：

  - // 和 /* */ — C/C++ 注释
  - R"delim(...)" — C++ raw string
  - 单引号字符字面量 'x'

  不支持 C# 的 @"..." verbatim string 或 Python 的 # 注释。如果 uses_braces=False 的语言被添加，scanner 仍会被调用。

  ---
  问题 6: build_db.py 的 Framework 分派过于简单

  # build_db.py:69-76 — 一个项目只能有一个 framework
  fw_name = project.framework_name
  if fw_name == "unreal":
      fw = make_unreal_framework()
  else:
      fw = make_generic_framework()
  frameworks[fw_name] = fw

  但 Unreal 项目同时包含 C++ 和 C# 文件。C# build system 代码（.cs）不该用 UE 的 UFUNCTION/UCLASS 规则去嗅探。目前代码把同一个 framework 配置应用到了所有语言的文件上。

  ---
  问题汇总

  ┌──────────┬───────────────────────┬────────────────────────────────────────────────────┐
  │ 严重程度 │         文件          │                        问题                        │
  ├──────────┼───────────────────────┼────────────────────────────────────────────────────┤
  │ 高       │ edge_extractor.py     │ 完全不使用 LanguageConfig，regex 全部硬编码 C++    │
  ├──────────┼───────────────────────┼────────────────────────────────────────────────────┤
  │ 高       │ code_block_summary.py │ 绕过配置系统，硬编码 C++/UE 规则，上游不传 lang/fw │
  ├──────────┼───────────────────────┼────────────────────────────────────────────────────┤
  │ 中       │ symbol_analyzer.py    │ _classify_block 中 namespace/lambda 检测硬编码     │
  ├──────────┼───────────────────────┼────────────────────────────────────────────────────┤
  │ 中       │ unreal_rules.py       │ 语言级基础类型混入框架层                           │
  ├──────────┼───────────────────────┼────────────────────────────────────────────────────┤
  │ 中       │ build_db.py           │ 单 framework 绑定到所有语言                        │
  ├──────────┼───────────────────────┼────────────────────────────────────────────────────┤
  │ 低       │ bracket_scanner.py    │ uses_braces 字段未使用，注释/字符串语法 C++ 专属   │
  └──────────┴───────────────────────┴────────────────────────────────────────────────────┘

  根本原因

  分层配置的数据结构（LanguageConfig / FrameworkConfig）设计正确，但消费者侧没有严格按层调用：

  1. LanguageConfig 缺少 edge extraction 所需的字段（scope operator、member access、base keyword 等）
  2. 已有的 LanguageConfig 字段（如 namespace_re）在部分路径上被绕过
  3. code_block_summary.py 作为"后加"模块，直接绕过了整个配置体系

  改进方向

  1. 补全 LanguageConfig：添加 scope_operator (:: / .)、base_keyword (Super / base)、static_call_re、param_type_re 等字段
  2. edge_extractor.py 消费 LanguageConfig：所有正则从 lang 参数获取
  3. code_block_summary.py 传入配置：apply_view() 的调用链需要一路传递 lang/fw
  4. 基础类型移到 LanguageConfig：_BASIC_SKIP_TYPES 从 unreal_rules.py 移到 make_cpp_language()
  5. 支持多框架：build_db.py 按语言+扩展名选择 framework，而非项目级单一选择
