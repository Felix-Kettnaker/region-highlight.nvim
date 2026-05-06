# region-highlight.nvim

Code region declarations for Neovim, inspired by VS Code's `#region` / `#endregion` markers.

## Features

- **Region folding**: Use `za` on a `#region` line to fold/unfold
- **Visual highlighting**: Regions are visually tinted (stacking for nested regions)
- **Language-aware**: Uses treesitter to detect comment lines; falls back gracefully
- **Auto-fold**: `#region fold` auto-closes on initial file load only
- **Customizable colors**: Bring your own palette, or disable coloring entirely
- **Live refresh**: Highlights update automatically as you edit (debounced 300ms)

## Installation

### lazy.nvim
```lua
{
  "your-username/region-highlight.nvim",
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

**Lua / Python / Ruby / Shell:**
```lua
-- #region My Section
local function myFunction() end
-- #endregion
```
```python
# #region My Section
def my_function(): pass
# #endregion
```

### Nested regions

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

## Folding

Regions are registered with `foldmethod=expr`. This means:

- `za` on a `#region` line folds or unfolds the region
- `zR` / `zM` open / close all folds as usual
- ⚠️ This overrides any other `foldmethod` set for that buffer

## Development / Testing

```bash
# Interactive testing (isolated Neovim config)
NVIM_APPNAME=regionhighlight nvim <file>

# Run test suite
make test
```

