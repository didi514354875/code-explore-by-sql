"""C/C++ language configuration."""

from __future__ import annotations

import re

from ..configs import LanguageConfig


def make_cpp_language() -> LanguageConfig:
    """C/C++ language configuration."""
    return LanguageConfig(
        name="cpp",
        class_re=re.compile(
            r"(?:^|\s)(class|struct)\s+"
            r"(?:(?:[A-Z][A-Z0-9_]*_API|[A-Z][A-Z0-9_]*(?:\s*\([^)]*\))?)\s+)*"
            r"(\w+)"
            r"\s*(?::\s*(?:public|protected|private)\s+(\w+))?",
        ),
        enum_re=re.compile(r"\benum\s+(?:(?:class|struct)\s+)?(\w+)"),
        namespace_re=re.compile(r"\bnamespace\s+(\w+)"),
        func_name_re=re.compile(r"(\w+(?:\s*::\s*\w+)*)\s*\([^)]*\)\s*$"),
        export_macro_re=re.compile(r"\b[A-Z][A-Z0-9_]*_API\b"),
        calling_conv_re=re.compile(
            r"\b(?:__cdecl|__stdcall|__fastcall|__thiscall|__vectorcall|WINAPI|CALLBACK|"
            r"STDMETHODCALLTYPE|FORCEINLINE|FORCENOINLINE|FORCEINLINE_DEBUGGABLE|inline)\b"
        ),
        attribute_re=re.compile(
            r"\b(?:__declspec|__attribute__|alignas)\s*\([^)]*(?:\)[^)]*)?\)|\[\[[^\]]*\]\]"
        ),
        template_re=re.compile(r"\btemplate\s*<[^<>]*>"),
        dtor_re=re.compile(r"~(\w+)\s*\("),
        control_flow_re=re.compile(r"\b(if|else\s+if|else|while|for|do|switch|catch|try)\b"),
        control_flow_names=frozenset({
            "if", "else", "while", "for", "do", "switch", "catch", "try",
            "return", "delete", "goto", "break", "continue", "throw",
            "co_await", "co_yield", "co_return",
        }),
        trailing_mods_re=re.compile(
            r"\s*(?:const|override|final|noexcept|mutable|constexpr|inline|static)\s*[;{]*\s*$"
        ),
        access_spec_re=re.compile(r"^(?:public|private|protected)\s*:\s*(?://.*)?$"),
        macro_like_re=re.compile(r"^[A-Z][A-Z0-9_]*\s*(?:\([^{};]*\))?\s*$"),
        define_re=re.compile(r"#\s*define\s+"),
        extern_c_re=re.compile(r'\bextern\s+"C"'),
        operator_re=re.compile(r"\boperator\b"),
        uses_braces=True,
        uses_namespaces=True,
        uses_colon_inheritance=True,
        scope_operator="::",
        base_keyword="Super",
        static_call_re=re.compile(r"\b([A-Z][A-Za-z0-9_]+)::([A-Za-z_][A-Za-z0-9_]*)\s*\("),
        super_call_re=re.compile(r"\bSuper::([A-Za-z_][A-Za-z0-9_]*)\s*\("),
        type_re=re.compile(r"\b([A-Z][A-Za-z0-9_]+)\b"),
        param_type_re=re.compile(
            r"(?:const\s+)?([A-Z][A-Za-z0-9_]+)\s*(?:\*+|&)?\s+\w+"
        ),
        basic_skip_types=frozenset({
            "int8", "int16", "int32", "int64",
            "uint8", "uint16", "uint32", "uint64",
            "float", "double", "bool", "void", "int", "char", "long", "short",
            "unsigned", "size_t", "auto", "nullptr_t",
        }),
        block_keyword_re=re.compile(r"\b(?:namespace|class|struct|enum)\b"),
        lambda_re=re.compile(r"\[.*\]\s*[\(]"),
        namespace_sig_re=re.compile(r"(?:inline\s+)?namespace\s+(\w+)?\s*$"),
        init_list_re=re.compile(r"\)\s*:"),
        access_spec_names=frozenset({"public:", "protected:", "private:"}),
        view_structural_kws=("class ", "struct ", "enum ", "namespace "),
        view_modifier_kws=("virtual ", "static ", "override", "FORCEINLINE"),
        local_var_modifiers="const|static|mutable|constexpr|volatile",
        verbatim_string_prefix=None,
        raw_string_char="R",
        range_for_re=re.compile(
            r"for\s*\(\s*(?:const\s+)?(\w+(?:\s*<[^>]*>)?)\s*[*&]?\s+(\w+)\s*:\s*(\w+)"
        ),
        # Comment syntax
        line_comment="//",
        block_comment_pair=("/*", "*/"),
        # String syntax
        string_delimiters=frozenset({'"', "'"}),
        string_escape_char="\\",
        triple_quote_strings=(),
        # Block style
        uses_indent_blocks=False,
        # Preprocessor
        preprocessor_prefix="#",
        has_preprocessor_macros=True,
        # Statement / block close
        statement_terminator=";",
        block_close_suffix="};",
        summary_comment_prefix="//",
        # Config-driven control flow
        control_flow_patterns=(
            ("for", re.compile(r"^\s*for\s*\((.{1,80})\)\s*\{?\s*$")),
            ("while", re.compile(r"^\s*while\s*\((.{1,80})\)\s*\{?\s*$")),
            ("if", re.compile(r"^\s*(?:else\s+)?if\s*\((.{1,80})\)\s*\{?\s*$")),
            ("switch", re.compile(r"^\s*switch\s*\((.{1,40})\)\s*\{?\s*$")),
        ),
        return_re=re.compile(r"^\s*return\s+(.{1,60});"),
        # Extra syntax hints
        type_indicator_chars="*&",
        define_line_re=re.compile(r"#\s*define\s+(\w+)(\([^)]*\))?\s*(.*)"),
        has_template_strings=False,
        raw_string_style="cpp",
    )
