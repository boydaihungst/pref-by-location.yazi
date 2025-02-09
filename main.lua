--- @since 25.2.7

local PackageName = "Preference by location"

local M = {}

---@alias LINEMODE
---|"none"
---|"size"
---|"btime"
---|"mtime"
---|"permissions"
---|"owner"

---@alias SORT_BY
---|"none"
---|"mtime"
---|"btime"
---|"extension"
---|"alphabetical"
---|"natural"
---|"size"
---|"random",

local function success(s, ...)
	ya.notify({ title = PackageName, content = string.format(s, ...), timeout = 5, level = "info" })
end

local function fail(s, ...)
	ya.notify({ title = PackageName, content = string.format(s, ...), timeout = 5, level = "error" })
end

local STATE_KEY = {
	loaded = "loaded",
	disabled = "disabled",
	save_path = "save_path",
	prefs = "prefs",
}

local set_state = ya.sync(function(state, key, value)
	state[key] = value
end)

local get_state = ya.sync(function(state, key)
	return state[key]
end)

local function escapeStringPattern(str)
	return str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

--- @return table<{location: string, sort: {[1]?: SORT_BY, reverse?: boolean, dir_first?: boolean, translit?: boolean }, linemode?: LINEMODE, show_hidden?: boolean }>
local read_prefs_from_saved_file = function(pref_path)
	local file = io.open(pref_path, "r")
	if file == nil then
		return {}
	end
	local prefs_encoded = file:read("*all")
	file:close()
	return ya.json_decode(prefs_encoded)
end

local current_dir = ya.sync(function()
	return tostring(cx.active.current.cwd)
end)

local current_pref = ya.sync(function()
	return {
		sort = {
			cx.active.pref.sort_by,
			reverse = cx.active.pref.sort_reverse,
			dir_first = cx.active.pref.sort_dir_first,
			translit = cx.active.pref.sort_translit,
		},
		linemode = cx.active.pref.linemode,
		show_hidden = cx.active.pref.show_hidden,
	}
end)

-- Save preferences to files, Exclude predefined preferences in setup({})
local save_prefs = function()
	local cwd = current_dir()
	--- @type table<{location: string, sort: {[1]?: SORT_BY, reverse?: boolean, dir_first?: boolean, translit?: boolean }, linemode?: LINEMODE, show_hidden?: boolean, is_predefined?: boolean }>
	local prefs = get_state(STATE_KEY.prefs)
	local prefs_predefined = {}
	-- do not save predefined prefs
	-- loop backward to prevent logical issue with shifting element + index number in array
	for idx = #prefs, 1, -1 do
		if prefs[idx].is_predefined then
			table.insert(prefs_predefined, 1, prefs[idx])
		end

		if prefs[idx].is_predefined or prefs[idx].location == escapeStringPattern(cwd) then
			table.remove(prefs, idx)
		end
	end

	local pref = current_pref()
	table.insert(prefs, 1, {
		location = escapeStringPattern(cwd),
		sort = pref.sort,
		linemode = pref.linemode,
		show_hidden = pref.show_hidden,
	})
	local save_path = Url(get_state(STATE_KEY.save_path))
	-- create parent directories
	local save_path_created, err_create = fs.create("dir_all", save_path:parent())
	if err_create then
		fail("Can't create folder to file: %s", tostring(save_path:parent()))
	end

	-- save prefs to file
	if save_path_created then
		local _, err_write = fs.write(save_path, ya.json_encode(prefs))
		if err_write then
			fail("Can't write to file:  %s", tostring(save_path))
		end
	end

	-- restore predefined preferences
	for _, p in ipairs(prefs_predefined) do
		table.insert(prefs, p)
	end
	set_state(STATE_KEY.prefs, prefs)
end

-- This function trigger everytime user change cwd
local change_pref = ya.sync(function()
	if get_state(STATE_KEY.disabled) then
		return
	end
	local prefs = get_state(STATE_KEY.prefs)
	local cwd = cx.active.current.cwd
	-- change pref based on location
	for _, pref in ipairs(prefs) do
		if string.match(tostring(cwd), pref.location .. "$") then
			-- sort
			local sort_pref = pref.sort
			if sort_pref then
				ya.dict_merge(sort_pref, { tab = cx.active.id })
				ya.manager_emit("sort", sort_pref)
			end

			-- linemode
			local linemode_pref = pref.linemode
			if linemode_pref then
				ya.manager_emit("linemode", { linemode_pref, tab = cx.active.id })
			end

			--show_hidden
			local show_hidden_pref = pref.show_hidden
			if show_hidden_pref ~= nil then
				ya.manager_emit("hidden", { show_hidden_pref and "show" or "hide", tab = cx.active.id })
			end
			return
		end
	end
end)

-- sort value is https://yazi-rs.github.io/docs/configuration/keymap#manager.sort
--- @param opts {prefs: table<{ location: string, sort: {[1]?: SORT_BY, reverse?: boolean, dir_first?: boolean, translit?: boolean }, linemode?: LINEMODE, show_hidden?: boolean, is_predefined?: boolean }>, save_path?: string, disabled?: boolean }
function M:setup(opts)
	local prefs = type(opts.prefs) == "table" and opts.prefs or {}
	if type(opts) == "table" then
		set_state(STATE_KEY.disabled, opts.disabled)
		local save_path = opts.save_path
			or (ya.target_family() == "windows" and os.getenv("APPDATA") .. "\\yazi\\config\\pref-by-location")
			or (os.getenv("HOME") .. "/.config/yazi/pref-by-location")
		set_state(STATE_KEY.save_path, save_path)

		-- flag to prevent these predefined prefs is saved to file
		for _, pref in ipairs(prefs) do
			pref.is_predefined = true
		end
		-- restore saved prefs from file
		local saved_prefs = read_prefs_from_saved_file(get_state(STATE_KEY.save_path))
		for idx = #saved_prefs, 1, -1 do
			table.insert(prefs, 1, saved_prefs[idx])
		end
		-- set_state(STATE_KEY.prefs, prefs)
	end
	-- dds subscribe on changed directory
	ps.sub("cd", function(_)
		if not get_state(STATE_KEY.loaded) then
			set_state(STATE_KEY.loaded, true)
			-- Add fallback location from yazi.toml
			local current_location_pref = current_pref()
			table.insert(prefs, {
				location = ".*",
				sort = current_location_pref.sort,
				linemode = current_location_pref.linemode,
				show_hidden = current_location_pref.show_hidden,
				is_predefined = true,
			})
			set_state(STATE_KEY.prefs, prefs)
		end
		change_pref()
	end)
end

function M:entry(job)
	local action = job.args[1]
	set_state(STATE_KEY.disabled, action == "disable")
	if get_state(STATE_KEY.disabled) then
		return
	end

	if action == "save" then
		save_prefs()
	end
end

return M
