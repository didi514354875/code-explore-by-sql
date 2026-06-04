"""C# language configuration."""

from __future__ import annotations

import re

from ..configs import LanguageConfig


def make_csharp_language() -> LanguageConfig:
    """C# language configuration."""
    return LanguageConfig(
        name="csharp",
        class_re=re.compile(
            r"(?:^|\s)(class|struct|interface|record)"
            r"(?:\s+(?:class|struct))?"
            r"\s+"
            r"(\w+)"
            r"\s*(?::\s*(\w+))?",
        ),
        enum_re=re.compile(r"\benum\s+(\w+)"),
        namespace_re=re.compile(r"\bnamespace\s+([\w.]+)"),
        func_name_re=re.compile(r"(\w+)\s*\([^)]*\)\s*$"),
        export_macro_re=re.compile(r"(?!x)x"),
        calling_conv_re=re.compile(r"(?!x)x"),
        attribute_re=re.compile(r"\[[^\]]*\]"),
        template_re=re.compile(r"<[^<>]*>"),
        dtor_re=re.compile(r"(?!x)x"),
        control_flow_re=re.compile(r"\b(if|else\s+if|else|while|for|foreach|do|switch|catch|try|using|lock)\b"),
        control_flow_names=frozenset({
            "if", "else", "while", "for", "foreach", "do", "switch", "catch", "try",
            "return", "break", "continue", "throw", "using", "lock", "yield",
            "async", "await", "new", "this", "base", "typeof", "sizeof", "nameof",
            "default", "checked", "unchecked", "delegate",
        }),
        trailing_mods_re=re.compile(r"\s*(?:override|virtual|abstract|sealed|static|async)\s*[;{]*\s*$"),
        access_spec_re=re.compile(r"^(?!x)x"),
        macro_like_re=re.compile(r"(?!x)x"),
        define_re=re.compile(r"(?!x)x"),
        extern_c_re=re.compile(r"(?!x)x"),
        operator_re=None,
        uses_braces=True,
        uses_namespaces=True,
        uses_colon_inheritance=True,
        scope_operator=".",
        base_keyword="base",
        static_call_re=re.compile(r"\b([A-Z][A-Za-z0-9_]+)\.([A-Za-z_][A-Za-z0-9_]*)\s*\("),
        super_call_re=re.compile(r"\bbase\.([A-Za-z_][A-Za-z0-9_]*)\s*\("),
        type_re=re.compile(r"\b([A-Z][A-Za-z0-9_]+)\b"),
        param_type_re=re.compile(r"([A-Z][A-Za-z0-9_]+)\s+\w+"),
        basic_skip_types=frozenset({
            "int", "uint", "long", "ulong", "short", "ushort",
            "byte", "sbyte", "float", "double", "decimal",
            "bool", "string", "object", "void", "char",
            "var", "dynamic", "nint", "nuint",
        }),
        block_keyword_re=re.compile(r"\b(?:namespace|class|struct|interface|record|enum)\b"),
        lambda_re=re.compile(r"(?:\w+\s*=>|delegate\s*\()"),
        namespace_sig_re=re.compile(r"namespace\s+([\w.]+)\s*$"),
        init_list_re=None,
        access_spec_names=frozenset({
            "public", "private", "protected", "internal",
            "protected internal", "private protected",
        }),
        view_structural_kws=("class ", "struct ", "interface ", "record ", "enum ", "namespace "),
        view_modifier_kws=("virtual ", "static ", "override", "abstract ", "sealed ", "async "),
        local_var_modifiers="const|static|volatile|readonly|ref|out",
        verbatim_string_prefix="@",
        raw_string_char=None,
        range_for_re=re.compile(
            r"foreach\s*\(\s*(\w+(?:\s*<[^>]*>)?)\s+(\w+)\s+in\s+(\w+)"
        ),
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
        preprocessor_prefix="",
        has_preprocessor_macros=False,
        # Statement / block close
        statement_terminator=";",
        block_close_suffix="}",
        summary_comment_prefix="//",
        # Config-driven control flow
        control_flow_patterns=(
            ("for", re.compile(r"^\s*for\s*\((.{1,80})\)\s*\{?\s*$")),
            ("foreach", re.compile(r"^\s*foreach\s*\((.{1,80})\)\s*\{?\s*$")),
            ("while", re.compile(r"^\s*while\s*\((.{1,80})\)\s*\{?\s*$")),
            ("if", re.compile(r"^\s*(?:else\s+)?if\s*\((.{1,80})\)\s*\{?\s*$")),
            ("switch", re.compile(r"^\s*switch\s*\((.{1,40})\)\s*\{?\s*$")),
        ),
        return_re=re.compile(r"^\s*return\s+(.{1,60});"),
        # Extra syntax hints
        type_indicator_chars="",
        define_line_re=None,
        has_template_strings=False,
        raw_string_style="cpp",
    )
