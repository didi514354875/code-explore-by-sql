"""Rust language configuration."""

from __future__ import annotations

import re

from ..configs import LanguageConfig


def make_rust_language() -> LanguageConfig:
    """Rust language configuration."""
    return LanguageConfig(
        name="rust",
        class_re=re.compile(r"(?:pub\s+)?(struct|enum|trait)\s+(\w+)"),
        enum_re=re.compile(r"(?:pub\s+)?enum\s+(\w+)"),
        namespace_re=re.compile(r"\bmod\s+(\w+)"),
        func_name_re=re.compile(r"(?:pub\s+)?(?:async\s+)?fn\s+(\w+)"),
        export_macro_re=re.compile(r"(?!x)x"),
        calling_conv_re=re.compile(r"(?!x)x"),
        attribute_re=re.compile(r"#!?\[[^\]]*\]"),  # inner/outer attributes
        template_re=re.compile(r"<[^<>]*>"),  # generics
        dtor_re=re.compile(r"(?!x)x"),  # Rust uses Drop trait
        control_flow_re=re.compile(r"\b(if|else\s+if|else|while|for|loop|match|return|break|continue)\b"),
        control_flow_names=frozenset({
            "if", "else", "while", "for", "loop", "match",
            "return", "break", "continue", "yield", "await", "unsafe",
        }),
        trailing_mods_re=re.compile(r"(?!x)x"),
        access_spec_re=re.compile(r"(?!x)x"),  # Rust uses pub
        macro_like_re=re.compile(r"^[a-z_]+!\s"),  # Rust macros end with !
        define_re=re.compile(r"(?!x)x"),  # Rust has macro_rules!, not #define
        extern_c_re=re.compile(r"\bextern\s+"),
        operator_re=None,
        uses_braces=True,
        uses_namespaces=True,
        uses_colon_inheritance=False,
        scope_operator="::",
        base_keyword="",  # Rust has no super; uses Deref or explicit paths
        static_call_re=re.compile(r"\b([A-Z][A-Za-z0-9_]+)::([A-Za-z_][A-Za-z0-9_]*)\s*\("),
        super_call_re=None,
        type_re=re.compile(r"\b([A-Z][A-Za-z0-9_]+)\b"),
        param_type_re=re.compile(r":\s*(?:&)?(?:mut\s+)?([A-Z][A-Za-z0-9_]+)"),  # name: Type syntax
        basic_skip_types=frozenset({
            "i8", "i16", "i32", "i64", "i128",
            "u8", "u16", "u32", "u64", "u128",
            "f32", "f64", "bool", "char", "str", "String",
            "Vec", "Box", "Rc", "Arc", "Option", "Result",
            "Cow", "Cell", "RefCell",
        }),
        block_keyword_re=re.compile(r"\b(?:struct|enum|trait|impl|mod|fn|type)\b"),
        lambda_re=re.compile(r"\|[^|]*\|\s*"),  # Rust closures
        namespace_sig_re=re.compile(r"\bmod\s+(\w+)\s*\{?\s*$"),
        init_list_re=None,
        access_spec_names=frozenset(),
        view_structural_kws=("struct ", "enum ", "trait ", "impl ", "fn "),
        view_modifier_kws=("pub ", "async ", "unsafe ", "const "),
        local_var_modifiers="let|mut|const|static|ref",
        verbatim_string_prefix=None,
        raw_string_char="r",
        range_for_re=re.compile(r"for\s+(\w+)\s+in\s+(\w+)"),
        # Comment syntax
        line_comment="//",
        block_comment_pair=("/*", "*/"),
        # String syntax
        string_delimiters=frozenset({'"'}),
        string_escape_char="\\",
        triple_quote_strings=(),
        # Block style
        uses_indent_blocks=False,
        # Preprocessor
        preprocessor_prefix="",  # Rust # is for attributes, not preprocessor
        has_preprocessor_macros=False,
        # Statement / block close
        statement_terminator=";",
        block_close_suffix="}",
        summary_comment_prefix="//",
        # Config-driven control flow
        control_flow_patterns=(
            ("for", re.compile(r"^\s*for\s+(.{1,80})\s*\{?\s*$")),
            ("while", re.compile(r"^\s*while\s+(.{1,80})\s*\{?\s*$")),
            ("if", re.compile(r"^\s*(?:else\s+)?if\s+(.{1,80})\s*\{?\s*$")),
            ("match", re.compile(r"^\s*match\s+(.{1,40})\s*\{?\s*$")),
            ("loop", re.compile(r"^\s*loop\s*\{?\s*$")),
        ),
        return_re=re.compile(r"^\s*return\s+(.{1,60});"),
        # Extra syntax hints
        type_indicator_chars="&",  # Rust references use &
        define_line_re=None,
        has_template_strings=False,
        raw_string_style="rust",  # Rust uses r#"..."# raw strings
    )
