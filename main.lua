--- @since 25.12.29

-- Default hint keys: left-hand home column-first. first_keys x second_keys
-- (overlap is INTENTIONAL - chords like "ww" are valid labels).
-- stylua: ignore
local DEFAULT_FIRST_KEYS = { "w", "e", "r", "a", "s", "d" }

-- stylua: ignore
local DEFAULT_SECOND_KEYS = { "w", "e", "r", "a", "s", "d" }

---@param str string
---@return string[]
local function string_to_table(str)
	local result = {}
	for i = 1, #str do
		table.insert(result, str:sub(i, i))
	end
	return result
end

---@param keys string|string[]
---@return string[]
local function normalize_keys(keys)
	if type(keys) == "string" then
		return string_to_table(keys)
	end
	return keys
end

--- Generate chord labels from first_keys × second_keys
---@param first_keys string[]
---@param second_keys string[]
---@return string[]
local function generate_double_labels(first_keys, second_keys)
	local labels = {}
	for _, fk in ipairs(first_keys) do
		for _, sk in ipairs(second_keys) do
			table.insert(labels, fk .. sk)
		end
	end
	return labels
end

--- Generate input key candidates
---@param first_keys string[]
---@param second_keys string[]
---@return string[]
local function generate_input_keys(first_keys, second_keys)
	local keys = {}
	local seen = {}
	-- Add all first_keys
	for _, k in ipairs(first_keys) do
		if not seen[k] then
			table.insert(keys, k)
			seen[k] = true
		end
	end

	-- Add all second_keys
	for _, k in ipairs(second_keys) do
		if not seen[k] then
			table.insert(keys, k)
			seen[k] = true
		end
	end

	-- Control keys ("q" cancels, "<C-q>" quits yazi; neither may be a hint key)
	table.insert(keys, "<Esc>")
	table.insert(keys, "<Backspace>")
	table.insert(keys, "q")
	table.insert(keys, "<C-q>")
	-- Movement keys: j/k stay free for cursor motion, never used as hints
	table.insert(keys, "j")
	table.insert(keys, "k")
	return keys
end

--- Build input candidates for ya.which
---@param input_keys string[]
---@return table[]
local function build_input_cands(input_keys)
	local cands = {}
	for _, v in ipairs(input_keys) do
		table.insert(cands, { on = v })
	end
	return cands
end

local status_mode_ej = function(self)
	local style = self:style()
	local m = self._tab.mode
	local txt = (m.is_select and "S" or (m.is_unset and "U" or "N")) .. "+⚡"
	return ui.Line({
		ui.Span(th.status.sep_left.open):fg(style.main:bg()):bg(App.bg()),
		ui.Span("" .. txt .. ""):style(style.main),
		ui.Span(th.status.sep_left.close):fg(style.main:bg()):bg(style.alt:bg()),
	})
end

---@param st easyjump.state
local toggle_ui = ya.sync(function(st)
	if st.entity_number_saved then
		Entity.number = st.entity_number_saved
		st.entity_number_saved = nil
		Status.mode = st.status_mode_saved
		st.status_mode_saved = nil
		ui.render()
		return
	end

	-- Render hints in the line-number gutter (relative-motions draws it via
	-- Entity.number), padded to the same width so the filename never shifts.
	st.entity_number_saved = Entity.number
	local orig_number = st.entity_number_saved
	local width = st.number_width or 3

	Entity.number = function(_, index, file, hovered, last_index)
		local pos = st.files_indices[tostring(file.url)]
		local label = pos and st.hint_pos_label[tostring(pos)]
		if not label then
			if orig_number then
				-- hovered row keeps its absolute number, grayed out while EZJ is active
				local idx = tostring(file.idx or index)
				local pad = string.rep(" ", math.max(0, width - 1 - #idx))
				return ui.Line({ ui.Span(pad .. idx .. " "):fg(st.opt_hovered_number_fg) })
			end
			return ui.Line({})
		end

		local pad = string.rep(" ", math.max(0, width - 1 - #label))
		if st.double_first_key ~= nil then
			if label:sub(1, 1) == st.double_first_key then
				return ui.Line({
					ui.Span(pad .. label:sub(1, 1)):fg(st.opt_first_key_fg),
					ui.Span(label:sub(2) .. " "):fg(st.opt_icon_fg),
				})
			end
			-- waiting for the second key: dim unreachable hints
			return ui.Line({ ui.Span(pad .. label .. " "):fg(st.opt_dim_fg) })
		end
		return ui.Line({ ui.Span(pad .. label .. " "):fg(st.opt_icon_fg) })
	end

	st.status_mode_saved = Status.mode
	Status.mode = status_mode_ej
	ui.render()
end)

---@param state easyjump.state
---@param str string?
local update_double_first_key = ya.sync(function(state, str)
	state.double_first_key = str
end)

local get_cursor = ya.sync(function()
	local folder = cx.active.current
	return { cursor = folder.cursor, offset = folder.offset }
end)

--- Jump to a window row (1-based) using a FRESH cursor/offset, so j/k movement
--- while hinting never skews the relative arrow.
local function jump_to(file_index)
	local cur = get_cursor()
	ya.emit("arrow", { file_index - cur.cursor - 1 + cur.offset })
end

-- State machine for reading input keys
-- Each state is a separate function. Type annotations document which fields are used.

---@alias easyjump.SecondKeyResult
---| "backspace" go back to first key state
---| "cancelled" user cancelled
---| "jumped" successfully jumped to file

--- State: waiting for the first chord key
--- Returns the first key pressed, or nil if cancelled
--- Uses: input_cands, input_keys, first_key_of_label
---@param ctx easyjump.InitResult
---@return string? first_key
local function read_double_first_key(ctx)
	while true do
		local cand = ya.which({ cands = ctx.input_cands, silent = true })

		if cand == nil then
		-- invalid key, wait for next
		elseif ctx.input_keys[cand] == "<Esc>" or ctx.input_keys[cand] == "z" or ctx.input_keys[cand] == "q" then
			return nil -- cancelled
		elseif ctx.input_keys[cand] == "<C-q>" then
			ya.emit("plugin", { "quit-ask" })
			return nil -- quit yazi
		elseif ctx.input_keys[cand] == "j" or ctx.input_keys[cand] == "k" then
			-- j/k are free while waiting for the first hint: normal movement
			ya.emit("arrow", { ctx.input_keys[cand] == "j" and 1 or -1 })
		else
			local key = ctx.input_keys[cand]
			if ctx.first_key_of_label[key] then
				update_double_first_key(key) -- update UI to highlight first key
				return key -- transition to second key state
			end
			-- invalid first key, wait for next
		end
	end
end

--- State: Double-key mode - waiting for second key
--- Returns the result of the second key input
--- Uses: input_cands, input_keys, double_key_files, current_files_count, cursor, offset
---@param ctx easyjump.InitResult
---@param first_key string
---@return easyjump.SecondKeyResult
local function read_double_second_key(ctx, first_key)
	while true do
		local cand = ya.which({ cands = ctx.input_cands, silent = true })

		if cand == nil then
		-- invalid key, wait for next
		elseif ctx.input_keys[cand] == "<Esc>" or ctx.input_keys[cand] == "z" or ctx.input_keys[cand] == "q" then
			return "cancelled"
		elseif ctx.input_keys[cand] == "<C-q>" then
			ya.emit("plugin", { "quit-ask" })
			return "cancelled" -- quit yazi
		elseif ctx.input_keys[cand] == "<Backspace>" then
			update_double_first_key(nil) -- clear UI highlight
			return "backspace" -- transition back to first key state
		else
			local second_key = ctx.input_keys[cand]
			local double_key = first_key .. second_key
			local file_index = ctx.hint_double[double_key]
			if file_index then
				jump_to(file_index)
				return "jumped"
			end
			-- invalid second key, wait for next
		end
	end
end

--- Main input handler with explicit state machine
---@param ctx easyjump.InitResult
local function read_single_key(ctx)
	while true do
		local cand = ya.which({ cands = ctx.input_cands, silent = true })

		if cand == nil then
		-- invalid key, wait for next
		elseif ctx.input_keys[cand] == "<Esc>" or ctx.input_keys[cand] == "z" or ctx.input_keys[cand] == "q" then
			return -- cancelled
		elseif ctx.input_keys[cand] == "<C-q>" then
			ya.emit("plugin", { "quit-ask" })
			return -- quit yazi
		elseif ctx.input_keys[cand] == "j" or ctx.input_keys[cand] == "k" then
			-- j/k are free while waiting for a hint: normal movement
			ya.emit("arrow", { ctx.input_keys[cand] == "j" and 1 or -1 })
		else
			local file_index = ctx.hint_lookup[ctx.input_keys[cand]]
			if file_index then
				jump_to(file_index)
				return -- jumped
			end
			-- invalid hint key, wait for next
		end
	end
end

--- Main input handler with explicit state machine
---@param ctx easyjump.InitResult
local function read_input(ctx)
	-- Few visible rows: the hint-key pool covers them all -> direct single keys
	if ctx.single_mode then
		read_single_key(ctx)
		return
	end

	-- Chord state machine: first key, then second key
	while true do
		-- State 1: Wait for first key
		local first_key = read_double_first_key(ctx)
		if not first_key then
			return -- cancelled
		end

		-- State 2: Wait for second key
		local result = read_double_second_key(ctx, first_key)
		if result == "jumped" or result == "cancelled" then
			return
		end
		-- result == "backspace": loop back to first key state
	end
end

---@class(exact) easyjump.state
---@field opt_icon_fg string
---@field opt_first_key_fg string
---@field opt_dim_fg string
---@field double_labels string[]
---@field input_keys string[]
---@field input_cands table[]
---@field hint_double table<string, number>
---@field hint_pos_label table<string, string>
---@field opt_hint_hovered boolean
---@field first_keys string[]
---@field hint_lookup table<string, number>
---@field single_mode boolean
---@field opt_hovered_number_fg string
---@field entity_label_id number
---@field status_mode_saved function?
---@field files_indices table<string, number> # file url to index
---@field current_files_count number
---@field double_first_key string?

---@class easyjump.InitResult
---@field current_files_count number
---@field cursor number
---@field offset number
---@field first_key_of_label table<string, string>
---@field input_keys string[]
---@field hint_double table<string, number>
---@field input_cands table[]
---@field single_mode boolean
---@field hint_lookup table<string, number>

-- init to record file position and the file num
---@param state easyjump.state
---@return easyjump.InitResult?
local init = ya.sync(function(state)
	state.files_indices = {}
	local first_key_of_label = {}
	local folder = cx.active.current

	local visible_files = folder.window
	state.current_files_count = #visible_files

	local last_idx = 1
	local hovered_pos = 0
	for i, file in ipairs(visible_files) do
		state.files_indices[tostring(file.url)] = i
		if (file.idx or i) > last_idx then
			last_idx = file.idx or i
		end
		if (file.idx or i) == folder.cursor + 1 then
			hovered_pos = i
		end
	end
	state.number_width = #tostring(last_idx) + 2

	-- Chords by default; direct single-key hints when the hint-key pool covers
	-- every visible row. Labels pack contiguously over the non-hovered rows (the
	-- hovered row keeps its motion number), so no label goes to waste.
	-- The hovered row keeps its number (unless hint_hovered), so size the
	-- threshold by the rows actually labeled: 7 visible rows need only 6 keys.
	local needed = state.opt_hint_hovered and #visible_files or (#visible_files - 1)
	state.single_mode = needed <= #state.first_keys
	local labels = state.single_mode and state.first_keys or state.double_labels
	state.hint_lookup, state.hint_pos_label = {}, {}
	local packed = 0
	for i, _ in ipairs(visible_files) do
		if i ~= hovered_pos or state.opt_hint_hovered then
			packed = packed + 1
			local label = labels[packed]
			if label then
				state.hint_lookup[label] = i
				if not state.single_mode then
					first_key_of_label[label:sub(1, 1)] = ""
				end
				state.hint_pos_label[tostring(i)] = label
			end
		end
	end

	return {
		current_files_count = state.current_files_count,
		cursor = folder.cursor,
		offset = folder.offset,
		first_key_of_label = first_key_of_label,
		input_keys = state.input_keys,
		single_mode = state.single_mode,
		hint_lookup = state.hint_lookup,
		input_cands = state.input_cands,
	}
end)

---@param state easyjump.state
local clear_state = ya.sync(function(state)
	state.files_indices = nil
	state.current_files_count = nil
	state.double_first_key = nil
	state.hint_lookup = nil
	state.hint_pos_label = nil
	state.single_mode = nil
end)

return {
	---@param state easyjump.state
	setup = function(state, opts)
		opts = opts or {}
		state.opt_icon_fg = opts.icon_fg or "#fda1a1"
		state.opt_first_key_fg = opts.first_key_fg or "#df6249"
		state.opt_dim_fg = opts.dim_fg or "#403E3C"
		state.opt_hint_hovered = opts.hint_hovered == true
		state.opt_hovered_number_fg = opts.hovered_number_fg or "#575653"

		-- Chord labels only (first x second, overlap allowed: ww ee ...)
		local first_keys = normalize_keys(opts.first_keys or DEFAULT_FIRST_KEYS)
		local second_keys = normalize_keys(opts.second_keys or DEFAULT_SECOND_KEYS)
		state.first_keys = first_keys
		state.double_labels = generate_double_labels(first_keys, second_keys)
		state.input_keys = generate_input_keys(first_keys, second_keys)

		state.input_cands = build_input_cands(state.input_keys)
	end,

	entry = function(_, _)
		local ctx = init()

		if ctx == nil or ctx.current_files_count == 0 then
			return
		end

		toggle_ui()
		read_input(ctx)
		toggle_ui()
		clear_state()
	end,
}
