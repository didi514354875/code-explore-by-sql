"""Python language configuration."""

from __future__ import annotations

import re

from ..configs import LanguageConfig

_NEVER_MATCH = re.compile(r"(?!x)x")


def make_python_language() -> LanguageConfig:
    """Python language configuration."""
    return LanguageConfig(
        name="python",
        class_re=re.compile(
            r"^\s*(class)\s+(\w+)(?:\s*\(\s*(\w+))?[^:]*:"
        ),
        enum_re=_NEVER_MATCH,
        namespace_re=_NEVER_MATCH,
        func_name_re=re.compile(r"(\w+)\s*\([^)]*\)\s*(?:\s*->.*?)?\s*:\s*$"),
        export_macro_re=_NEVER_MATCH,
        calling_conv_re=_NEVER_MATCH,
        attribute_re=re.compile(r"@\w+(?:\.\w+)*(?:\([^)]*\))?"),
        template_re=_NEVER_MATCH,
        dtor_re=_NEVER_MATCH,
        control_flow_re=re.compile(
            r"^\s*(?:if|elif|else|while|for|try|except|finally|with|match|case)\b"
        ),
        control_flow_names=frozenset({
            "if", "elif", "else", "while", "for", "try", "except", "finally",
            "with", "match", "case", "return", "yield", "break", "continue",
            "raise", "pass", "del", "global", "nonlocal", "assert", "import",
            "from",
        }),
        trailing_mods_re=_NEVER_MATCH,
        access_spec_re=_NEVER_MATCH,
        macro_like_re=_NEVER_MATCH,
        define_re=_NEVER_MATCH,
        extern_c_re=_NEVER_MATCH,
        operator_re=None,
        uses_braces=False,
        uses_namespaces=False,
        uses_colon_inheritance=True,
        scope_operator=".",
        base_keyword="super()",
        static_call_re=re.compile(
            r"\b([A-Z][A-Za-z0-9_]+)\.([A-Za-z_][A-Za-z0-9_]*)\s*\("
        ),
        super_call_re=re.compile(
            r"\bsuper\(\)\.([A-Za-z_][A-Za-z0-9_]*)\s*\("
        ),
        type_re=re.compile(r"\b([A-Z][A-Za-z0-9_]+)\b"),
        param_type_re=re.compile(r"(\w+)\s*:\s*([A-Z][A-Za-z0-9_]+)"),
        basic_skip_types=frozenset({
            "int", "float", "str", "bool", "list", "dict", "set", "tuple",
            "bytes", "bytearray", "memoryview", "range", "enumerate", "type",
            "object", "complex", "frozenset",
            "None", "Any", "Optional", "Union", "Callable", "Type",
            "List", "Dict", "Set", "Tuple",
        }),
        block_keyword_re=re.compile(r"\b(?:class|def|async\s+def)\b"),
        lambda_re=re.compile(r"\blambda\b"),
        func_sig_end_re=re.compile(r"\)\s*(?:->.*?)?\s*:\s*$"),
        namespace_sig_re=None,
        init_list_re=None,
        access_spec_names=frozenset(),
        view_structural_kws=("class ", "def ", "async def "),
        view_modifier_kws=(
            "@staticmethod ", "@classmethod ", "@property ", "@abstractmethod ",
        ),
        local_var_modifiers="global|nonlocal",
        verbatim_string_prefix=None,
        raw_string_char="r",
        range_for_re=re.compile(r"^\s*for\s+(\w+)\s+in\s+(\w+)"),
        # Comment syntax
        line_comment="#",
        block_comment_pair=None,
        # String syntax
        string_delimiters=frozenset({'"', "'"}),
        string_escape_char="\\",
        triple_quote_strings=('"""', "'''"),
        # Block style
        uses_indent_blocks=True,
        # Preprocessor
        preprocessor_prefix="",
        has_preprocessor_macros=False,
        # Statement / block close
        statement_terminator="",
        block_close_suffix="",
        summary_comment_prefix="#",
        # Config-driven control flow
        control_flow_patterns=(
            ("for", re.compile(r"^\s*for\s+(.{1,80})\s*:\s*$")),
            ("while", re.compile(r"^\s*while\s+(.{1,80})\s*:\s*$")),
            ("if", re.compile(r"^\s*(?:elif\s+)?if\s+(.{1,80})\s*:\s*$")),
            ("match", re.compile(r"^\s*match\s+(.{1,40})\s*:\s*$")),
        ),
        return_re=re.compile(r"^\s*return\s+(.{1,60})\s*$"),
        # Extra syntax hints
        type_indicator_chars="",
        define_line_re=None,
        has_template_strings=False,
        raw_string_style="cpp",
    )
