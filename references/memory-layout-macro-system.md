# MemoryLayout.h Macro System & Frozen Memory Image Serialization

## Design Purpose

MemoryLayout.h implements a **compile-time type layout reflection system** for UE's **Frozen Memory Image** pipeline. Enables:
- Cross-platform serialization of Shader data (64-bit editor → 32-bit target)
- VTable patching on thaw (frozen data has no vtable)
- Pointer relocation (frozen pointers → offsets, thawed back to pointers)
- Layout compatibility verification via SHA1 hash (DDC cache keys)

## Core Data Structures

### FTypeLayoutDesc — Type-level descriptor
```cpp
struct FTypeLayoutDesc {
    const TCHAR* Name;
    const FFieldLayoutDesc* Fields;  // linked list head
    uint64 NameHash;
    uint32 Size;              // sizeof(T)
    uint32 Alignment;         // alignof(T)
    uint32 SizeFromFields;    // computed from fields (may differ from Size due to EditorOnly stripping)
    ETypeLayoutInterface::Type Interface;  // NonVirtual / Virtual / Abstract
    uint8 NumBases, NumVirtualBases;
    uint8 IsIntrinsic : 1, IsInitialized : 1;
    // 6 function pointers (replace virtual functions):
    FWriteFrozenMemoryImageFunc* WriteFrozenMemoryImageFunc;
    FUnfrozenCopyFunc* UnfrozenCopyFunc;
    FAppendHashFunc* AppendHashFunc;
    FGetTargetAlignmentFunc* GetTargetAlignmentFunc;
    FToStringFunc* ToStringFunc;
    FDestroyFunc* DestroyFunc;
    FGetDefaultFunc* GetDefaultObjectFunc;  // for vtable patching
};
```

### FFieldLayoutDesc — Field-level descriptor
```cpp
struct FFieldLayoutDesc {
    const TCHAR* Name;
    const FTypeLayoutDesc* Type;     // recursive: field's type descriptor
    const FFieldLayoutDesc* Next;    // singly linked list
    FWriteFrozenMemoryImageFunc* WriteFrozenMemoryImageFunc;  // per-field override
    uint32 Offset;                   // STRUCT_OFFSET(DerivedType, Name)
    uint32 NumArray;                 // 1 for scalars, N for arrays
    EFieldLayoutFlags::Type Flags;   // EditorOnly, RayTracing, Transient
    uint8 BitFieldSize;              // 0 for normal, N for bitfield
    uint8 UFieldNameLength;          // name length without _DEPRECATED
};
```

## Macro Expansion Mechanism: `__COUNTER__` + Template Recursion

### Core Trick
C++ doesn't allow recursive macro expansion inside class bodies, but **template specialization** with `__COUNTER__` indexing works:

1. `DECLARE_TYPE_LAYOUT(T, Interface)` defines `CounterBase = __COUNTER__` and a base template `InternalLinkType<N>` with empty `Initialize()`
2. Each `LAYOUT_FIELD(T, Name)` increments `__COUNTER__` and creates a specialization `InternalLinkType<N>` that:
   - Calls `InternalLinkType<N+1>::Initialize(TypeDesc)` (recursion)
   - Creates a static `FFieldLayoutDesc` with head-insertion into the linked list
3. `IMPLEMENT_TYPE_LAYOUT(T)` generates `StaticGetTypeLayout()` that lazily initializes the descriptor

### Example Expansion

```cpp
// User code:
class FMyShader : public FShader {
    DECLARE_TYPE_LAYOUT(FMyShader, NonVirtual);  // CounterBase=0
    LAYOUT_FIELD(FShaderParameter, MyParam)       // counter=1
    LAYOUT_FIELD(int32, Count)                    // counter=2
};
IMPLEMENT_TYPE_LAYOUT(FMyShader)

// Macro expansion produces:
// InternalLinkType<1>: registers MyParam
// InternalLinkType<2>: registers Count
// InternalLinkType<3>: empty terminator

// StaticGetTypeLayout() triggers on first access:
//   InternalLinkType<1>::Initialize(TypeDesc)
//     → InternalLinkType<2>::Initialize(TypeDesc)
//       → InternalLinkType<3>::Initialize(TypeDesc)  // empty, stop
//       → register Count field (head-insert)
//     → register MyParam field (head-insert)
//   Fields chain: TypeDesc.Fields → MyParam → Count → nullptr
//   (reverse order because head-insertion + recursion unwind)
```

### Key Macro Definitions

| Macro | Purpose |
|-------|---------|
| `DECLARE_TYPE_LAYOUT(T, Interface)` | Declares layout in class body (out-of-line StaticGetTypeLayout) |
| `DECLARE_INLINE_TYPE_LAYOUT(T, Interface)` | Declares layout with inline StaticGetTypeLayout |
| `DECLARE_EXPORTED_TYPE_LAYOUT(T, API, Interface)` | Exported version for DLL boundaries |
| `IMPLEMENT_TYPE_LAYOUT(T)` | Implements StaticGetTypeLayout + registers globally |
| `IMPLEMENT_TEMPLATE_TYPE_LAYOUT(Prefix, T)` | Template class version |
| `LAYOUT_FIELD(T, Name, ...)` | Register field with optional flags |
| `LAYOUT_ARRAY(T, Name, N, ...)` | Register array field |
| `LAYOUT_BITFIELD(T, Name, Bits, ...)` | Register bitfield |
| `LAYOUT_FIELD_EDITORONLY(T, Name, ...)` | Editor-only field (stripped in shipping) |
| `LAYOUT_FIELD_WITH_WRITER(T, Name, Func)` | Field with custom freeze writer |
| `LAYOUT_WRITE_MEMORY_IMAGE(Func)` | Override entire type's freeze writer |
| `DECLARE_INTRINSIC_TYPE_LAYOUT(T)` | For built-in types (int, float, void*, etc.) |

## Serialization: Freeze (Write Frozen Memory Image)

`Freeze::DefaultWriteMemoryImage` (MemoryImage.cpp L418-550):

```
For each field in linked list:
  ├─ IncludeField()? — check EditorOnly/RayTracing flags
  ├─ Non-bitfield:
  │   ├─ WriteAlignment(fieldAlignment)
  │   ├─ WriteFrozenMemoryImageFunc() — field's write function
  │   │   ├─ Intrinsic: memcpy sizeof(T)
  │   │   ├─ UObject: UProperty system
  │   │   └─ Custom: recursive DefaultWriteMemoryImage
  │   └─ WritePaddingToSize()
  ├─ Bitfield:
  │   └─ ExtractBitFieldValue → accumulate → write when full
  └─ VTable:
      └─ HasVTable && NumVirtualBases==0 → WriteVTable()
```

**Key**: NOT a raw memcpy. Each field is individually written with target-platform alignment, enabling cross-platform (32-bit↔64-bit) serialization.

`FPlatformTypeLayoutParameters` controls cross-platform behavior:
- `MaxFieldAlignment`: target max field alignment
- `Is32Bit`: pointer size (4 vs 8 bytes)
- `HasAlignBases`: whether to align base class subobjects
- `WithEditorOnly`: include EditorOnly fields

## Deserialization: UnfrozenCopy (Thaw)

`Freeze::DefaultUnfrozenCopy` (MemoryImage.cpp L909+):

```
For each field in linked list:
  ├─ FrozenOffset aligned per FrozenLayoutParameters
  ├─ FieldDst = OutDst + FieldDesc->Offset (current platform offset)
  ├─ FieldType.UnfrozenCopyFunc(frozen, type, dst)
  │   ├─ Intrinsic: placement new copy
  │   └─ Custom: recursive DefaultUnfrozenCopy
  └─ VTable patching via GetDefaultObject()
```

## Layout Hash (DDC Cache Key)

`Freeze::DefaultAppendHash` (MemoryImage.cpp L575-685) hashes **layout structure** (not data values):

```
Hash = {
    TypeName,
    per-field: { Offset, NumArray, FieldType.recursive_hash, BitFieldSize }
}
```

Used as DDC cache key — different layouts on different platforms force recompilation.

## Intrinsic vs Compound Types

| | Intrinsic (DECLARE_INTRINSIC_TYPE_LAYOUT) | Compound (DECLARE_TYPE_LAYOUT + LAYOUT_FIELD) |
|---|---|---|
| Fields | None | Linked list |
| Write | Direct memcpy | Recursive field traversal |
| UnfrozenCopy | Placement new | Recursive field copy |
| SizeFromFields | = sizeof(T) | Computed from fields (may < sizeof due to EditorOnly) |
| Examples | int, float, void*, bool, FThreadSafeCounter | FMaterialShader, FMeshMaterialShader, all LAYOUT_FIELD users |

## Function Pointer Table (6 functions, no virtual)

| Function | Intrinsic | Compound |
|----------|-----------|----------|
| WriteFrozenMemoryImage | IntrinsicWriteMemoryImage → memcpy | DefaultWriteMemoryImage → field traversal |
| UnfrozenCopy | IntrinsicUnfrozenCopy → placement new | DefaultUnfrozenCopy → field traversal |
| AppendHash | IntrinsicAppendHash → name+size | DefaultAppendHash → field layout hash |
| GetTargetAlignment | Return TypeDesc.Alignment | Max of all field alignments |
| ToString | Type-specific formatters | DefaultToString → recursive |
| Destroy | Freeze::DestroyObject (memset 0xFE) | Same, but calls destructor first if not frozen |

## Source File Locations

| Component | File |
|-----------|------|
| All macros + FTypeLayoutDesc + FFieldLayoutDesc | Core/Public/Serialization/MemoryLayout.h |
| DefaultWriteMemoryImage, DefaultUnfrozenCopy, DefaultAppendHash | Core/Private/Serialization/MemoryImage.cpp |
| FPlatformTypeLayoutParameters | MemoryLayout.h L798 |
| Intrinsic type registrations | MemoryLayout.h L770-796 |
| Freeze::DestroyObject | MemoryLayout.h L251 |
| IMPLEMENT_TYPE_LAYOUT expansion | MemoryLayout.h L565-604 |
