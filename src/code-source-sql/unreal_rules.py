"""Unreal Engine framework rules — UE-specific configuration for symbol analysis.

Extracts all hardcoded UE constants from symbol_analyzer and edge_extractor
into a single FrameworkConfig instance.
"""

from __future__ import annotations

import re

from configs import FrameworkConfig

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
    # C/C++ primitive / standard types
    "int8", "int16", "int32", "int64",
    "uint8", "uint16", "uint32", "uint64",
    "float", "double", "bool", "void", "int", "char", "long", "short",
    "unsigned", "size_t", "auto", "nullptr_t",
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

_NOISE_CALL_TARGETS = frozenset({
    "StaticClass", "StaticStruct", "GetClass", "GetWorld", "GetOuter",
    "GetTransientPackage", "IsValid", "GetDefaultObject",
})

_RPC_SPECIFIERS = frozenset({"Server", "Client", "NetMulticast"})
_BLUEPRINT_NATIVE_EVENT = "BlueprintNativeEvent"

_UE_PREFIXES = ("A", "U", "F", "E", "I", "T")


def make_unreal_framework() -> FrameworkConfig:
    """Create the Unreal Engine framework configuration."""
    return FrameworkConfig(
        name="unreal",
        skip_types=_UE_SKIP_TYPES | _BASIC_SKIP_TYPES,
        noise_type_names=_NOISE_TYPE_NAMES,
        decoration_macro_re=_UE_DECORATION_RE,
        decoration_macro_names=_UE_DECORATION_NAMES,
        noise_macro_re=_UE_NOISE_RE,
        declare_macro_re=_UE_DECLARE_RE,
        generated_body_re=_UE_NOISE_RE,
        ue_prefixes=_UE_PREFIXES,
        rpc_specifiers=_RPC_SPECIFIERS,
        blueprint_native_event=_BLUEPRINT_NATIVE_EVENT,
        noise_call_targets=_NOISE_CALL_TARGETS,
        extract_ue_meta=True,
        sniff_decoration_above=True,
        extra_symbol_types=frozenset({"delegate_def", "macro_def"}),
    )
