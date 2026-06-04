"""Swift language configuration."""

from __future__ import annotations

import re

from ..configs import LanguageConfig

_NEVER_MATCH = re.compile(r"(?!x)x")


def make_swift_language() -> LanguageConfig:
    """Swift language configuration."""
    return LanguageConfig(
        name="swift",
        class_re=re.compile(
            r"(?:(?:public|private|internal|open|fileprivate|final|static|override)\s+)*"
            r"(class|struct|protocol|enum|actor)\s+(\w+)"
            r"(?:\s*<[^>]*>)?"
            r"(?:\s*:\s*(\w+))?"
        ),
        enum_re=re.compile(r"(?:indirect\s+)?enum\s+(\w+)"),
        namespace_re=_NEVER_MATCH,
        func_name_re=re.compile(
            r"(?:(?:public|private|internal|open|fileprivate|static|override|mutating|nonmutating)\s+)*"
            r"(?:async\s+)?(?:throws\s+)?"
            r"func\s+(\w+)\s*\("
        ),
        export_macro_re=_NEVER_MATCH,
        calling_conv_re=_NEVER_MATCH,
        attribute_re=re.compile(r"@\w+(?:\([^)]*\))?"),
        template_re=re.compile(r"<[^<>]*>"),
        dtor_re=re.compile(r"deinit"),
        control_flow_re=re.compile(
            r"\b(if|else\s+if|else|while|for|switch|catch|try|guard|repeat)\b"
        ),
        control_flow_names=frozenset({
            "if", "else", "while", "for", "switch", "catch", "try",
            "return", "break", "continue", "throw", "guard", "repeat",
            "defer", "yield", "await",
        }),
        trailing_mods_re=_NEVER_MATCH,
        access_spec_re=_NEVER_MATCH,
        macro_like_re=_NEVER_MATCH,
        define_re=_NEVER_MATCH,
        extern_c_re=_NEVER_MATCH,
        operator_re=None,
        uses_braces=True,
        uses_namespaces=False,
        uses_colon_inheritance=True,
        scope_operator=".",
        base_keyword="super",
        static_call_re=re.compile(
            r"\b([A-Z][A-Za-z0-9_]+)\.([A-Za-z_][A-Za-z0-9_]*)\s*\("
        ),
        super_call_re=re.compile(
            r"\bsuper\.([A-Za-z_][A-Za-z0-9_]*)\s*\("
        ),
        type_re=re.compile(r"\b([A-Z][A-Za-z0-9_]+)\b"),
        param_type_re=re.compile(r"(\w+)\s*:\s*([A-Z][A-Za-z0-9_]+)"),
        basic_skip_types=frozenset({
            "Int", "Int8", "Int16", "Int32", "Int64",
            "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
            "Float", "Double", "Bool", "String", "Character",
            "Void", "Any", "AnyObject", "Optional", "Array",
            "Dictionary", "Set", "Result", "URL", "Data", "Date",
        }),
        block_keyword_re=re.compile(
            r"\b(?:class|struct|protocol|enum|actor|func|extension|typealias)\b"
        ),
        lambda_re=re.compile(r"\{"),
        namespace_sig_re=None,
        init_list_re=None,
        access_spec_names=frozenset(),
        view_structural_kws=(
            "class ", "struct ", "protocol ", "enum ", "actor ",
            "func ", "extension ",
        ),
        view_modifier_kws=(
            "public ", "private ", "internal ", "open ", "static ",
            "override ", "mutating ", "async ",
        ),
        local_var_modifiers="let|var|guard",
        verbatim_string_prefix=None,
        raw_string_char=None,
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
        preprocessor_prefix="",
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
            ("switch", re.compile(r"^\s*switch\s+(.{1,40})\s*\{?\s*$")),
        ),
        return_re=re.compile(r"^\s*return\s+(.{1,60})"),
        # Extra syntax hints
        type_indicator_chars="",
        define_line_re=None,
        has_template_strings=False,
        raw_string_style="cpp",
    )
