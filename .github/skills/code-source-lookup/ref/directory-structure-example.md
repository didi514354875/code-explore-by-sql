# Directory Structure Reference

This file shows example output from `get_directory_structure()`.
Module names listed in the `modules` field are valid values for the `module`
parameter in `search_code_source()` and the `scope` parameter in `find_callers()`.

## Example: Game Engine Codebase

```json
{
  "total_files": 84231,
  "modules": [
    {"module_name": "Runtime", "file_count": 42105},
    {"module_name": "Editor", "file_count": 12340},
    {"module_name": "Developer", "file_count": 5423},
    {"module_name": "Programs", "file_count": 3211},
    {"module_name": "NiagaraCore", "file_count": 2890},
    {"module_name": "Renderer", "file_count": 2156}
  ],
  "top_dirs": [
    {"path_prefix": "Engine/Source/Runtime", "file_count": 42105},
    {"path_prefix": "Engine/Source/Editor", "file_count": 12340},
    {"path_prefix": "Engine/Source/Developer", "file_count": 5423},
    {"path_prefix": "Engine/Source/Programs", "file_count": 3211},
    {"path_prefix": "Engine/Plugins/FX/Niagara", "file_count": 2890}
  ],
  "extensions": [
    {"extension": ".cpp", "file_count": 35000},
    {"extension": ".h", "file_count": 34000},
    {"extension": ".cs", "file_count": 12000},
    {"extension": ".hpp", "file_count": 3231}
  ]
}
```

## How to Use

1. Call `get_directory_structure()` at the start of a session.
2. From the `modules` list, pick the module name that best matches the subsystem
   you're investigating.
3. Pass it as `module="Runtime"` to `search_code_source()` or `scope="Runtime"`
   to `find_callers()`.
4. If the module filter returns empty results, check `top_dirs` for the actual
   path structure — the module name in the database may differ from the directory
   name due to how `infer_module_name()` was configured during indexing.

## Fallback

If `get_directory_structure()` is unavailable or returns empty modules, try
searching without the `module` parameter and use `scope_filter` or
`raw_query` column filters on `file_path` instead.
