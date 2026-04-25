# Finding Duplicate Model Definitions

The compilation errors show:
```
Invalid redeclaration of 'WearableProvider'
Invalid redeclaration of 'SmartwatchConnection'
Invalid redeclaration of 'BiometricData'
Invalid redeclaration of 'RecoveryStatus'
Invalid redeclaration of 'ConnectDeviceRequest'
```

This means these types are defined in **multiple files**.

## How to Find Them

### Option 1: Xcode Search
1. Open Xcode
2. Press `Cmd+Shift+F` (Find in Project)
3. Search for: `struct BiometricData`
4. Look at ALL results - there should be duplicates

### Option 2: Terminal Search
```bash
cd /path/to/SportsHub
grep -r "struct BiometricData" --include="*.swift"
grep -r "struct SmartwatchConnection" --include="*.swift"
grep -r "enum WearableProvider" --include="*.swift"
grep -r "struct RecoveryStatus" --include="*.swift"
grep -r "struct ConnectDeviceRequest" --include="*.swift"
```

## Expected Results

**Correct:** Only ONE definition in `WearableModels.swift`

**If you find duplicates:** Delete the duplicate definitions

## Likely Locations for Duplicates

1. **Old API models file** - Check if there's an older wearables/smartwatch models file
2. **Bottom of SmartwatchSyncView.swift** - Models might have been defined inline
3. **APIClient.swift** - Sometimes models are defined near their usage
4. **Separate WearableTypes.swift or SmartwatchModels.swift** - Check for similar filenames

## The Fix

Once you find the duplicates:

1. **Keep:** `WearableModels.swift` (the new, correct file)
2. **Delete:** All duplicate definitions in other files
3. **Import:** Add `// No import needed - same module` at top of files that use these types

OR if the types are in a different module/target, you need to import them properly.

## Quick Fix if You Can't Find Them

The nuclear option - delete `WearableModels.swift` and recreate it fresh:

1. In Xcode, delete `WearableModels.swift` (Move to Trash)
2. Create new file: File → New → File → Swift File
3. Name it `WearableModels.swift`
4. Copy the content from the existing file back in
5. Make sure it's added to the correct target

This forces Xcode to forget about any duplicate registration issues.

## What the Error Means

`Invalid redeclaration` = "You've defined this type more than once"

Swift doesn't allow the same type name to be defined twice in the same module/namespace.

Each of these types can only exist ONCE:
- `WearableProvider` enum
- `SmartwatchConnection` struct
- `BiometricData` struct  
- `RecoveryStatus` struct
- `ConnectDeviceRequest` struct

Find where they're duplicate and delete one set of definitions.
