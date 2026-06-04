"""Java language configuration."""

from __future__ import annotations

import re

from ..configs import LanguageConfig


def make_java_language() -> LanguageConfig:
    """Java language configuration."""
    return LanguageConfig(
        name="java",
        class_re=re.compile(
            r"(?:^|\s)(?:(?:public|private|protected|abstract|final|static)\s+)*"
            r"(class|interface|enum)\s+(\w+)"
            r"(?:\s+extends\s+(\w+))?"
        ),
        enum_re=re.compile(r"\benum\s+(\w+)"),
        namespace_re=re.compile(r"(?!x)x"),  # never-match; Java packages are directory-based
        func_name_re=re.compile(
            r"(\w+)\s*\([^)]*\)\s*(?:throws\s+[\w,\s]+)?\s*\{?\s*$"
        ),
        export_macro_re=re.compile(r"(?!x)x"),
        calling_conv_re=re.compile(r"(?!x)x"),
        attribute_re=re.compile(r"@\w+(?:\.\w+)*(?:\([^)]*\))?"),  # annotations
        template_re=re.compile(r"<[^<>]*>"),  # generics
        dtor_re=re.compile(r"(?!x)x"),
        control_flow_re=re.compile(r"\b(if|else\s+if|else|while|for|do|switch|catch|try|synchronized)\b"),
        control_flow_names=frozenset({
            "if", "else", "while", "for", "do", "switch", "catch", "try",
            "return", "break", "continue", "throw", "synchronized", "assert", "new",
        }),
        trailing_mods_re=re.compile(r"\s*(?:throws\s+[\w,\s]+)?\s*\{?\s*$"),
        access_spec_re=re.compile(r"(?!x)x"),  # Java has no standalone access-spec lines
        macro_like_re=re.compile(r"(?!x)x"),
        define_re=re.compile(r"(?!x)x"),
        extern_c_re=re.compile(r"(?!x)x"),
        operator_re=None,
        uses_braces=True,
        uses_namespaces=False,
        uses_colon_inheritance=True,
        scope_operator=".",
        base_keyword="super",
        static_call_re=re.compile(r"\b([A-Z][A-Za-z0-9_]+)\.([A-Za-z_][A-Za-z0-9_]*)\s*\("),
        super_call_re=re.compile(r"\bsuper\.([A-Za-z_][A-Za-z0-9_]*)\s*\("),
        type_re=re.compile(r"\b([A-Z][A-Za-z0-9_]+)\b"),
        param_type_re=re.compile(
            r"([A-Z][A-Za-z0-9_]+)\s*<[^>]*>\s+\w+|([A-Z][A-Za-z0-9_]+)\s+\w+"
        ),
        basic_skip_types=frozenset({
            "int", "long", "short", "byte", "float", "double", "boolean", "char", "void",
            "String", "Object", "Integer", "Long", "Double", "Float", "Boolean", "Byte",
            "Short", "Character",
        }),
        block_keyword_re=re.compile(r"\b(?:class|interface|enum)\b"),
        lambda_re=re.compile(r"->"),  # Java lambdas
        namespace_sig_re=None,
        init_list_re=None,
        access_spec_names=frozenset(),
        view_structural_kws=("class ", "interface ", "enum "),
        view_modifier_kws=("abstract ", "static ", "final ", "synchronized "),
        local_var_modifiers="final|static|volatile|transient",
        verbatim_string_prefix=None,
        raw_string_char=None,
        range_for_re=re.compile(
            r"for\s*\(\s*(\w+(?:<[^>]*>)?)\s+(\w+)\s*:\s*(\w+)"
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
