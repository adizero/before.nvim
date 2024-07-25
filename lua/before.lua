local M = {}

M.edit_locations = {}
M.dedupe_table = {}
M.cursor = 1

M.max_entries = nil
M.history_wrap_enabled = nil

local function within_bounds(bufnr, line)
  local total_lines = vim.api.nvim_buf_line_count(bufnr)

  return line > 0 and line < total_lines + 1
end

local function bufvalid(bufnr)
  return vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_is_valid(bufnr)
end

local function same_line(this_location, that_location)
  return this_location.line == that_location.line and this_location.bufnr == that_location.bufnr
end

local function is_regular_buffer(bufnr)
  return vim.api.nvim_buf_get_option(bufnr, 'buftype') == ''
end

local function should_remove(location)
  return not bufvalid(location.bufnr) or not within_bounds(location.bufnr, location.line) or
      not is_regular_buffer(location.bufnr)
end

local function assign_location(new_location, location_idx, new_cursor)
  local key = string.format("%s:%d", new_location.file, new_location.line)

  local same_line_history_idx = M.dedupe_table[key]
  if same_line_history_idx then
    table.remove(M.edit_locations, same_line_history_idx)
    location_idx = location_idx - 1
    new_cursor = new_cursor - 1
  end

  M.edit_locations[location_idx] = new_location
  M.cursor = new_cursor
  M.dedupe_table[key] = #M.edit_locations
  vim.g.BEFORE_EDIT_LOCATIONS = M.edit_locations
end

local function find_backwards_jump(currentLocation)
  local number_of_earler_edits = M.cursor - 1
  local deleted = 0
  for i = 0, number_of_earler_edits do
    local local_cursor = M.cursor - i + deleted
    local location = M.edit_locations[local_cursor]

    if location and not bufvalid(location.bufnr) and location.file and location.file ~= '' then
      local new_bufnr = vim.fn.bufnr(location.file)
      if new_bufnr == -1 then
        vim.cmd.edit(location.file)
        new_bufnr = vim.api.nvim_get_current_buf()
      end
      location['bufnr'] = new_bufnr
      M.edit_locations[local_cursor] = location
      vim.g.BEFORE_EDIT_LOCATIONS = M.edit_locations
    end

    if location and should_remove(location) then
      table.remove(M.edit_locations, local_cursor)
      deleted = deleted + 1
      vim.g.BEFORE_EDIT_LOCATIONS = M.edit_locations
    else
      if location and not same_line(currentLocation, location) then
        M.cursor = local_cursor
        return location
      end
    end
  end

  if M.history_wrap_enabled then
    local fallback_location = M.edit_locations[#M.edit_locations]
    if fallback_location and should_remove(fallback_location) then
      table.remove(M.edit_locations, #M.edit_locations)
      vim.g.BEFORE_EDIT_LOCATIONS = M.edit_locations
    else
      M.cursor = #M.edit_locations
      return fallback_location
    end
  else
    return nil
  end
end

local function find_forward_jump(currentLocation)
  local number_of_later_edits = #M.edit_locations - M.cursor
  local deleted = 0
  for i = 0, number_of_later_edits do
    local local_cursor = M.cursor + i - deleted
    local location = M.edit_locations[local_cursor]

    if location and not bufvalid(location.bufnr) and location.file and location.file ~= '' then
      local new_bufnr = vim.fn.bufnr(location.file)
      if new_bufnr == -1 then
        vim.cmd.edit(location.file)
        new_bufnr = vim.api.nvim_get_current_buf()
      end
      location['bufnr'] = new_bufnr
      M.edit_locations[local_cursor] = location
      vim.g.BEFORE_EDIT_LOCATIONS = M.edit_locations
    end

    if location and should_remove(location) then
      table.remove(M.edit_locations, local_cursor)
      deleted = deleted + 1
      vim.g.BEFORE_EDIT_LOCATIONS = M.edit_locations
    else
      if location and not same_line(currentLocation, location) then
        M.cursor = local_cursor
        return location
      end
    end
  end

  if M.history_wrap_enabled then
    local fallback_location = M.edit_locations[1]
    if fallback_location and should_remove(fallback_location) then
      table.remove(M.edit_locations, 1)
      vim.g.BEFORE_EDIT_LOCATIONS = M.edit_locations
    else
      M.cursor = 1
      return fallback_location
    end
  else
    return nil
  end
end

local function trim(s)
  if not s then
    return ''
  end
  return s:gsub("^%s*(.-)%s*$", "%1")
end

--- Read a line from a file (uses file:seek to determine position)
--- @param filename string Path to the file
--- @param linenum number Number of the line to read
--- @return string|nil, string|nil The line content (or nil if error), error message (or nil if no error)
local function read_line_from_file(filename, linenum)
    local file = io.open(filename, "r")
    if not file then
        return nil, "UNABLE-TO-OPEN-FILE"
    end

    local position = 0
    for i = 1, linenum - 1 do
        file:seek("set", position)
        local line = file:read("*line")
        if not line then
            file:close()
            return nil, "LINE-NUMBER-EXCEEDS-FILE-LENGTH"
        end
        position = file:seek()
    end

    file:seek("set", position)
    local line = file:read("*line")
    file:close()

    return line
end

local function load_file_line(file, linenum)
  local _, error = vim.loop.fs_stat(file)
  if error ~= nil then
    return nil
  end
  local cnt = 1
  for line in io.lines(file) do
    if cnt == linenum then
      return trim(line)
    end
    cnt = cnt + 1
  end

  return ''
end

local function load_buf_line(bufnr, linenum)
  return trim(vim.api.nvim_buf_get_lines(bufnr, linenum - 1, linenum, false)[1])
end

function M.get_line_content(location)
  local line_content = nil

  if bufvalid(location.bufnr) then
    line_content = load_buf_line(location.bufnr, location.line)
  else
    line_content, error = read_line_from_file(location.file, location.line)
    if line_content == nil then
      line_content = string.format("[%s]", error)
    end
  end

  if line_content == nil then
    line_content = "[INVALID-LINE]"
  elseif line_content == '' then
    line_content = "[EMPTY-LINE]"
  end
  return line_content
end

M.custom_show_edits_default_opts_fn = nil

local function show_edits_default_opts()
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values

  local defaults = {
    prompt_title = "Edit Locations",
    finder = finders.new_table({
      results = M.edit_locations,
      entry_maker = function(entry)
        local line_content = M.get_line_content(entry)
        return {
          value = entry.file .. entry.line,
          display = entry.line .. ':' .. entry.bufnr .. '| ' .. line_content,
          ordinal = entry.line .. ':' .. entry.bufnr .. '| ' .. line_content,
          filename = entry.file,
          -- bufnr = entry.bufnr, -- telescope picker strongly prefers bufnr, but won't accept non-existent number
          lnum = entry.line,
          col = entry.col,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    previewer = conf.grep_previewer({}),
    default_selection_index = #M.edit_locations - M.cursor + 1,
  }
  if M.custom_show_edits_default_opts_fn then
    local opts = M.custom_show_edits_default_opts_fn() or {}
    local opts_finder = opts.finder
    -- vim.tbl_deep_extend somehow corrupts the passed opts.finder table
    defaults = vim.tbl_deep_extend("force", defaults, opts)
    if opts_finder then
        defaults.finder = opts_finder
    end
  end
  return defaults
end

-- newest edits first
function M.create_sorted_edit_locations()
  local sorted = {}
  local i = 1
  for _, location in pairs(M.edit_locations) do
      sorted[#M.edit_locations - i + 1] = location
      i = i + 1
  end
  return sorted
end

function M.show_edits_in_telescope(opts)
  local pickers = require('telescope.pickers')

  opts = opts or {}
  local opts_finder = opts.finder
  -- vim.tbl_deep_extend somehow corrupts the passed opts.finder table
  opts = vim.tbl_deep_extend("force", show_edits_default_opts(), opts)
  if opts_finder then
      opts.finder = opts_finder
  end

  pickers.new({}, opts):find()
end

function M.show_edits_in_quickfix()
  local qf_entries = {}
  for _, location in pairs(M.create_sorted_edit_locations()) do
    local line_content = M.get_line_content(location)
    if bufvalid(location.bufnr) then
      table.insert(qf_entries, { bufnr = location.bufnr, lnum = location.line, col = location.col, text = line_content })
    else
      table.insert(qf_entries,
        { filename = location.file, lnum = location.line, col = location.col, text = line_content })
    end
  end

  vim.fn.setqflist({}, 'r', { title = 'Edit Locations', items = qf_entries })
  vim.cmd([[copen]])
  local selection_index = #M.edit_locations - M.cursor
  if selection_index > 0 then
      vim.cmd(string.format([[normal! %dj]], selection_index))
  end
end

-- DEPRECATED, but don't want to brake the users by removing.
function M.show_edits(picker_opts)
  if M.telescope_for_preview then
    M.show_edits_in_telescope(picker_opts)
  else
    M.show_edits_in_quickfix()
  end
end

function M.track_edit()
  local bufnr = vim.api.nvim_get_current_buf()
  local file = vim.fn.expand("%:p")
  local pos = vim.api.nvim_win_get_cursor(0)
  local location = { bufnr = bufnr, line = pos[1], col = pos[2], file = file }

  if is_regular_buffer(bufnr) and within_bounds(location.bufnr, location.line) then
    assign_location(location, #M.edit_locations + 1, #M.edit_locations + 1)
  end

  if #M.edit_locations > M.max_entries then
    table.remove(M.edit_locations, 1)
    vim.g.BEFORE_EDIT_LOCATIONS = M.edit_locations
    M.cursor = M.max_entries
  end
end

--- Jumps to the last edit location
--- @param skip boolean|nil Skip over and do not count edits in the same file (defaults to false)
--- @param count number|nil Allows to jump multiple times (defaults to v:count1)
--- @return nil
function M.jump_to_last_edit(skip, count)
  if not count then
    count = vim.v.count1
  end
  if #M.edit_locations > 0 then
    local initial_bufnr = vim.api.nvim_get_current_buf()
    local bufnr = initial_bufnr
    local pos = vim.api.nvim_win_get_cursor(0)
    local current = { bufnr = bufnr, line = pos[1], col = pos[2] }

    local new_location = nil
    while current and count > 0 do
      current = find_backwards_jump(current)
      if current then
        new_location = current
        if bufnr ~= current.bufnr or not skip then
            count = count - 1
            bufnr = current.bufnr
        end
      end
    end

    if not new_location then
        print("[before.nvim]: At the oldest entry of the edits list.")
        return
    elseif initial_bufnr == new_location.bufnr and skip then
        print("[before.nvim]: Jumped within the oldest file of the edits list.")
    end

    if new_location then
      vim.api.nvim_win_set_buf(0, new_location.bufnr)
      vim.api.nvim_win_set_cursor(0, { new_location.line, new_location.col })
    end
  else
    print("[before.nvim]: No edit locations stored.")
  end
end

--- Jumps to the next edit location
--- @param skip boolean|nil Skip over and do not count edits in the same file (defaults to false)
--- @param count number|nil Allows to jump multiple times (defaults to v:count1)
--- @return nil
function M.jump_to_next_edit(skip, count)
  if not count then
    count = vim.v.count1
  end
  if #M.edit_locations > 0 then
    local initial_bufnr = vim.api.nvim_get_current_buf()
    local bufnr = initial_bufnr
    local pos = vim.api.nvim_win_get_cursor(0)
    local current = { bufnr = bufnr, line = pos[1], col = pos[2] }

    local new_location = nil
    while current and count > 0 do
      current = find_forward_jump(current)
      if current then
        new_location = current
        if bufnr ~= current.bufnr or not skip then
            count = count - 1
            bufnr = current.bufnr
        end
      end
    end

    if not new_location then
        print("[before.nvim]: At the newest entry of the edits list.")
        return
    elseif initial_bufnr == new_location.bufnr and skip then
        print("[before.nvim]: Jumped within the newest file of the edits list.")
    end

    if new_location then
      vim.api.nvim_win_set_buf(0, new_location.bufnr)
      vim.api.nvim_win_set_cursor(0, { new_location.line, new_location.col })
    end
  else
    print("[before.nvim]: No edit locations stored.")
  end
end

M.defaults = {
  history_size = 10,
  history_wrap_enabled = false,
  -- DEPRECATED, but don't want to brake the users by removing.
  telescope_for_preview = false
}

function M.setup(opts)
  opts = vim.tbl_deep_extend("force", M.defaults, opts or {})

  M.max_entries = opts.history_size
  M.history_wrap_enabled = opts.history_wrap_enabled
  M.telescope_for_preview = opts.telescope_for_preview

  -- restore edit locations from shada global variable vim.g.BEFORE_EDIT_LOCATIONS
  M.edit_locations = vim.g.BEFORE_EDIT_LOCATIONS or {}
  while #M.edit_locations > M.max_entries do
    table.remove(M.edit_locations, 1)
  end
  M.cursor = #M.edit_locations
  for _, location in pairs(M.edit_locations) do
    -- force reopen of new buffers (stored buffer numbers point to wrong buffers after nvim restart)
    location.bufnr = -1
  end
  vim.g.BEFORE_EDIT_LOCATIONS = M.edit_locations

  vim.api.nvim_create_autocmd({ "TextChanged", "InsertEnter" }, {
    pattern = "*",
    callback = function()
      require('before').track_edit()
    end,
  })
end

return M
