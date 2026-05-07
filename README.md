# region-highlight.nvim

Code region declarations for Neovim, inspired by VS Code's `#region` / `#endregion` markers.

## Features

- **Region folding**: Use `za` on a `#region` line to fold/unfold
- **% jumping**: Press `%` on a `#region` or `#endregion` to jump to its pair
- **Visual highlighting**: Regions are visually tinted (stacking for nested regions)
- **Language-aware**: Uses treesitter to detect comment lines; falls back gracefully
- **Auto-fold**: `#region fold` auto-closes on initial file load only
- **Customizable colors**: Bring your own palette, or disable coloring entirely
- **Live refresh**: Highlights update automatically as you edit (debounce configurable)

## Installation

### lazy.nvim
```lua
{
  "Felix-Kettnaker/region-highlight.nvim",
  config = function()
    require("region-highlight").setup()
  end,
}
```

## Usage

Add region markers inside comments. The marker must appear within a comment line — bare code lines are ignored.

**C / C++ / JavaScript / TypeScript:**
```c
// #region My Section
void myFunction() {}
// #endregion
```

**Lua / Ruby / Shell:**
```lua
-- #region My Section
local function myFunction() end
-- #endregion
```

**Python** — since `#` is Python's comment character, `#region` alone is enough (no space needed):
```python
#region My Section
def my_function(): pass
#endregion
```

The `# #region` form (with a space) also works and matches VS Code's style:
```python
# #region My Section
def my_function(): pass
# #endregion
```

**GDScript** — `#region`/`#endregion` are native GDScript keywords and are recognized directly (this is the only syntax Godot accepts):
```gdscript
#region My Section
func my_function(): pass
#endregion
```



Regions can be nested. Each level adds another tint step, so nesting stays visually distinguishable.

```lua
-- #region Outer
local a = 1
-- #region Inner
local b = 2  -- double-tinted
-- #endregion
-- #endregion
```

### Auto-fold on load

Append `fold` to the marker to have the region auto-close when the file is first opened:

```lua
-- #region fold
local big_table = { ... }  -- hidden by default
-- #endregion
```

The fold only closes on the **initial** file open. Switching back to the buffer will not re-close it.

## Configuration

```lua
require("region-highlight").setup({
  -- Treat ALL #region markers as #region fold (auto-close everything on load)
  fold_all = false, -- default

  -- Debounce delay (ms) for re-processing after text changes
  refresh_debounce = 300, -- default

  -- Custom background colors, cycled by encounter order across the file.
  -- 3 colors + 4 regions → region 4 gets color 1 again.
  -- colors = { "#1e1e2e", "#1e2e1e", "#2e1e1e" }

  -- Set to false to disable background highlighting entirely.
  -- colors = false
})
```

### Default tinting

Without `colors`, the plugin automatically derives tint colors from your theme's `Normal` background:

- **Dark themes**: each region level blends 5% towards white
- **Light themes**: each region level blends 5% towards black

Tints stack: a region at depth 2 is twice as tinted as depth 1.

## Folding and navigation

Regions are registered with `foldmethod=expr`. This means:

- `za` on a `#region` line folds or unfolds the region
- `zR` / `zM` open / close all folds as usual
- `%` on a `#region` or `#endregion` line jumps to the matching pair (nesting-aware; falls through to matchit / built-in % on other lines)
- ⚠️ This overrides any other `foldmethod` set for that buffer

## Troubleshooting

### LSP highlights appear over region markers

Some language servers (e.g. `lua-language-server`) return a document-highlight response that spans the entire region when the cursor is on a `#region`/`#endregion` marker. This is intentional server behavior and unrelated to region-highlight.nvim. Disabling the document-highlight feature (e.g. `snacks.nvim` `words`) in your LSP config resolves it.

## Testing

```bash
make test
```

