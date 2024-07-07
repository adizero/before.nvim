# before.nvim

## Fork changes
* Edit locations persistence across nvim restarts using shada file global variable storage
* Supports normal mode counts that allow jump to last/next edit command multiplication
* Selects current edit location cursor in telescope/quickfix
* Exposes get_line_content and custom_show_edits_default_opts_fn for easier telescope picker customization
* Reverses edit locations to see newest edits first when using telescope/quickfix
* Fixes empty/nil input handling bugs

### Example with get_line_content and custom_show_edits_default_opts_fn
```lua
    local before = require('before')
    before.setup({
        history_size = 100,
        history_wrap_enabled = false
    })

    -- will be merged to the before's default opts (necessary to get the same config via ":Telescope before")
    before.custom_show_edits_default_opts_fn = function()
        local finders = require('telescope.finders')
        local opts = {
            preview_title = nil,  -- we want to have filename as preview window title
            finder = finders.new_table({
                results = before.create_sorted_edit_locations(),
                entry_maker = function(entry)
                    -- local short_path = require("utils").shorten_path(entry.file, true, true)
                    local short_path = entry.file
                    local line_content = before.get_line_content(entry)
                    return {
                        value = entry.file .. entry.line,
                        display = short_path .. ':' .. entry.line .. ':' ..  entry.col .. '| ' .. line_content,
                        ordinal = entry.file .. ':' .. entry.line .. ':' ..  entry.col .. '| ' .. line_content,
                        filename = entry.file,
                        -- bufnr = entry.bufnr,  -- force telescope to use filename instead of bufnr (necessary)
                        lnum = entry.line,
                        col = entry.col,
                    }
                end,
            }),
        }
        return opts
    end
```

## Purpose
Track edit locations and jump back to them, like [changelist](https://neovim.io/doc/user/motion.html#changelist), but across buffers.

![peeked](https://github.com/bloznelis/before.nvim/assets/33397865/1130572d-dd75-4a07-9c79-9afc91b5d67a)

## Installation
### lazy.nvim
```lua
{
  'bloznelis/before.nvim',
  config = function()
    local before = require('before')
    before.setup()

    -- Jump to previous entry in the edit history
    vim.keymap.set('n', '<C-h>', before.jump_to_last_edit, {})

    -- Jump to next entry in the edit history
    vim.keymap.set('n', '<C-l>', before.jump_to_next_edit, {})

    -- Look for previous edits in quickfix list
    vim.keymap.set('n', '<leader>oq', before.show_edits_in_quickfix, {})

    -- Look for previous edits in telescope (needs telescope, obviously)
    vim.keymap.set('n', '<leader>oe', before.show_edits_in_telescope, {})
  end
}
```

### Configuration
#### Settings
```lua
require('before').setup({
  -- How many edit locations to store in memory (default: 10)
  history_size = 42,
  -- Wrap around the ends of the edit history (default: false)
  history_wrap_enabled = true
})
```
#### Telescope picker
```lua
-- You can provide telescope opts to the picker as show_edits_in_telescope argument:
vim.keymap.set('n', '<leader>oe', function()
  before.show_edits_in_telescope(require('telescope.themes').get_dropdown())
end, {})
```

#### Register Telescope extension

You may also register the extension via telescope:

```lua
require 'telescope'.setup({ '$YOUR_TELESCOPE_OPTS' })
require 'telescope'.load_extension('before')
```

Then call via vimscript:

```vim
:Telescope before
```

or lua:

```lua
require 'telescope'.extensions.before.before
```
