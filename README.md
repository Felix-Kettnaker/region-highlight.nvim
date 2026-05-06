# region-highlight.nvim

Code region declarations for Neovim, inspired by VS Code's `#region` / `#endregion` markers.

## Features

- **Region folding**: Use `za` on a `#region` line to fold/unfold
- **Visual highlighting**: Regions are visually tinted (stacking for nested regions)
- **Language-aware**: Uses treesitter to detect comment lines
- **Auto-fold**: `#region fold` auto-closes on initial file load
- **Customizable colors**: Bring your own palette

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

In any source file, add region markers inside comments:

```python
# #region My Section
def my_function():
    pass
# #endregion
```

```lua
-- #region My Section
local function my_function()
end
-- #endregion
```

```javascript
// #region My Section
function myFunction() {}
// #endregion
```

### Auto-fold on load

```lua
-- #region fold  ← this region auto-closes when the file is opened
local big_table = { ... }
-- #endregion
```

## Configuration

```lua
require("region-highlight").setup({
  -- Treat ALL regions as `#region fold` (auto-close on load)
  fold_all = false,

  -- Custom background colors (cycled by encounter order)
  -- colors = { "#2a2a3a", "#2a3a2a", "#3a2a2a" }
  -- Set to false to disable background highlighting entirely
  -- colors = false
})
```

## Testing

```
NVIM_APPNAME=regionhighlight nvim
```
