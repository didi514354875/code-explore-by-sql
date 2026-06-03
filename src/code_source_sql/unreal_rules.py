"""Unreal Engine framework rules — UE-specific configuration for symbol analysis.

Extracts all hardcoded UE constants from symbol_analyzer and edge_extractor
into a single FrameworkConfig instance.
"""

from __future__ import annotations

import re

from .configs import FrameworkConfig

# ── UE decoration macros ──────────────────────────────────────────────────

_UE_DECORATION_RE = re.compile(
    r"^\s*(UCLASS|USTRUCT|UENUM|UFUNCTION|UPROPERTY|UINTERFACE)"
    r"\s*\(([^)]*)\)"
)

_UE_DECORATION_NAMES = frozenset({
    "UCLASS", "USTRUCT", "UENUM", "UFUNCTION", "UPROPERTY", "UINTERFACE",
})

_UE_DECLARE_RE = re.compile(r"^\s*(DECLARE_\w+(?:_\w+)*)\s*\(")

_UE_NOISE_RE = re.compile(
    r"^\s*(?:GENERATED_BODY|GENERATED_UCLASS_BODY|GENERATED_USTRUCT_BODY|UMETA|UPARAM)\s*\(?"
)

# ── UE type skip lists ────────────────────────────────────────────────────

_UE_SKIP_TYPES = frozenset({
    # Basic UE container / value types
    "TArray", "TMap", "TSet", "TSharedPtr", "TSharedRef", "TWeakPtr",
    "TUniquePtr", "TFunction", "TTuple", "TPair", "TOptional",
    "FString", "FName", "FText",
    # Basic math types
    "FLinearColor", "FVector", "FVector2D", "FVector4",
    "FRotator", "FQuat", "FTransform", "FMatrix",
    "FGuid", "FDateTime", "FTimespan",
    # Core UE base classes — too common to be useful as edges
    "AActor", "UObject", "ACharacter", "APawn", "AController",
    "UActorComponent", "USceneComponent", "UPrimitiveComponent",
    "UGameInstance", "UGameModeBase", "UWorld", "APlayerState",
    "UGameStateBase", "APlayerController",
})

_BASIC_SKIP_TYPES = frozenset({
    # C/C++ primitive / standard types — NOTE: moved to LanguageConfig.basic_skip_types
    # for make_cpp_language(). Kept here only for reference / backward compat.
})

_NOISE_TYPE_NAMES = frozenset({
    "FORCEINLINE", "FORCENOINLINE", "INLINE", "PRAGMA", "Deprecated",
    "The", "Type", "Tag", "Name", "Value", "Key", "Data", "Result",
    "Index", "Count", "Size", "Offset", "Flags", "Mode", "State",
    "Id", "ID", "Handle", "Ptr", "Ref", "Desc", "Info", "Error",
    "CbField", "Design", "ObjectData", "VOIP", "Begin", "End",
    "Max", "Min", "Default", "None", "Null", "True", "False",
    "Out", "In", "Src", "Dst", "Len", "Buf", "Res",
    "Header", "Footer", "Body", "Title", "Label",
    "Module", "Package", "Plugin", "Project",
    "Source", "Target", "Input", "Output",
    "Self", "Super", "This",
})

_RPC_SPECIFIERS = frozenset({"Server", "Client", "NetMulticast"})
_BLUEPRINT_NATIVE_EVENT = "BlueprintNativeEvent"
_RPC_VALIDATION_PARAM = "WithValidation"

_UE_PREFIXES = ("A", "U", "F", "E", "I", "T")


# ── Callback implementations ───────────────────────────────────────────────


def extract_ue_rpc_edges(qn: str, decoration_meta: dict) -> list[tuple[str, str]]:
    """Extract UE RPC routing edges from decoration metadata.

    Returns [(target_qn, edge_type), ...] pairs.
    e.g. ("AFoo::Bar", {"UFUNCTION": ["Server", "Reliable"]})
         -> [("AFoo::Bar_Implementation", "rpc_routing")]
    """
    if qn.endswith("_Implementation") or qn.endswith("_Validate"):
        return []

    results: list[tuple[str, str]] = []
    for macro_name, params in decoration_meta.items():
        if macro_name in _UE_DECORATION_NAMES:
            has_rpc = False
            for p in params:
                if p in _RPC_SPECIFIERS or p == _BLUEPRINT_NATIVE_EVENT:
                    has_rpc = True
                    break
            if has_rpc:
                results.append((f"{qn}_Implementation", "rpc_routing"))
                if _RPC_VALIDATION_PARAM in params:
                    results.append((f"{qn}_Validate", "rpc_routing"))
    return results


def parse_ue_delegate_name(stripped_line: str) -> str | None:
    """Parse delegate name from a UE DECLARE_* macro line."""
    paren_start = stripped_line.find("(")
    if paren_start < 0:
        return None
    inner = stripped_line[paren_start + 1:].strip()
    first_comma = inner.find(",")
    first_paren = inner.find(")")
    end = min(
        first_comma if first_comma >= 0 else len(inner),
        first_paren if first_paren >= 0 else len(inner),
    )
    delegate_name = inner[:end].strip().rstrip(")")
    if delegate_name and delegate_name[0].isupper():
        return delegate_name
    return None


def should_skip_ue_macro(name: str) -> bool:
    """Return True for UE macro names that should be excluded from extraction."""
    return name.startswith("_") or name.startswith("GENERATED_")


def format_ue_meta_display(meta: dict) -> list[str]:
    """Format UE decoration metadata into display parts for [Meta] line."""
    parts: list[str] = []
    for macro, params in meta.items():
        params_str = ",".join(params)
        parts.append(f"{macro}({params_str})")
        rpc_triggers = _RPC_SPECIFIERS | {_BLUEPRINT_NATIVE_EVENT} - {""}
        if any(p in rpc_triggers for p in params):
            parts.append("->_Implementation")
        if _RPC_VALIDATION_PARAM in params:
            parts.append("->_Validate")
    return parts


def resolve_ue_type_prefixes(qualified_name: str) -> list[str]:
    """Generate candidate QNs by prepending UE type prefixes (A, U, F, E, I, T)."""
    return [prefix + qualified_name for prefix in _UE_PREFIXES]


def make_unreal_framework() -> FrameworkConfig:
    """Create the Unreal Engine framework configuration."""
    return FrameworkConfig(
        name="unreal",
        skip_types=_UE_SKIP_TYPES,
        noise_type_names=_NOISE_TYPE_NAMES,
        decoration_macro_re=_UE_DECORATION_RE,
        decoration_macro_names=_UE_DECORATION_NAMES,
        noise_macro_re=_UE_NOISE_RE,
        declare_macro_re=_UE_DECLARE_RE,
        extract_decoration_meta=True,
        sniff_decoration_above=True,
        extra_symbol_types=frozenset({"delegate_def", "macro_def"}),
        # Framework behavior callbacks
        extract_framework_edges=extract_ue_rpc_edges,
        parse_delegate_name=parse_ue_delegate_name,
        macro_name_filter=should_skip_ue_macro,
        format_meta_display=format_ue_meta_display,
        resolve_type_prefixes=resolve_ue_type_prefixes,
    )
