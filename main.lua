--- @since 25.2.7
--- NOTE: REMOVE :parent() :name() :is_hovered() :ext() tab.id after upgrade to v25.4.4
--- https://github.com/sxyazi/yazi/pull/2572

local PackageName = "pref-by-location"

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

local STATE_KEY = {
	loaded = "loaded",
	disabled = "disabled",
	no_notify = "no_notify",
	save_path = "save_path",
	last_hovered_folder = "last_hovered_folder",
	prefs = "prefs",
}

local set_state = ya.sync(function(state, key, value)
	state[key] = value
end)

local get_state = ya.sync(function(state, key)
	return state[key]
end)
local function success(s, ...)
	if not get_state(STATE_KEY.no_notify) then
		ya.notify({ title = PackageName, content = string.format(s, ...), timeout = 3, level = "info" })
	end
end

---@enum NOTIFY_MSG
local NOTIFY_MSG = {
	TOGGLE = "%s auto-save preference",
}

local function fail(s, ...)
	ya.notify({ title = PackageName, content = string.format(s, ...), timeout = 3, level = "error" })
end

---@enum PUBSUB_KIND
local PUBSUB_KIND = {
	prefs_changed = "@" .. PackageName .. "-" .. "prefs-changed",
	disabled = "@" .. PackageName .. "-" .. "disabled",
}

--- broadcast through pub sub to other instances
---@param _ table state
---@param pubsub_kind PUBSUB_KIND
---@param data any
---@param to number default = 0 to all instances
local broadcast = ya.sync(function(_, pubsub_kind, data, to)
	ps.pub_to(to or 0, pubsub_kind, data)
end)

local function escapeStringPattern(str)
	return str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

--- @return table<{location: string, sort: {[1]?: SORT_BY, reverse?: boolean, dir_first?: boolean, translit?: boolean, sensitive?: boolean }, linemode?: LINEMODE, show_hidden?: boolean }>
local read_prefs_from_saved_file = function(pref_path)
	local file = io.open(pref_path, "r")
	if file == nil then
		return {}
	end
	local prefs_encoded = file:read("*all")
	file:close()
	local prefs = ya.json_decode(prefs_encoded)
	-- NOTE: Temporary fix json_encode not save mixed key properly
	for _, pref in ipairs(prefs) do
		if pref.sort ~= nil and type(pref.sort.by) == "string" then
			pref.sort[1] = pref.sort.by
			pref.sort.by = nil
		end
	end

	return prefs
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
			sensitive = cx.active.pref.sort_sensitive,
		},
		linemode = cx.active.pref.linemode,
		show_hidden = cx.active.pref.show_hidden,
	}
end)

local function deepClone(original)
	if type(original) ~= "table" then
		return original
	end

	local copy = {}
	for key, value in pairs(original) do
		copy[deepClone(key)] = deepClone(value)
	end

	return copy
end

-- Save preferences to files, Exclude predefined preferences in setup({})
---comment
---@param opts ?{exclude_cwd?: boolean}
local save_prefs = function(opts)
	if get_state(STATE_KEY.disabled) then
		return
	end

	local cwd = current_dir()
	--- @type table<{location: string, sort: {[1]?: SORT_BY, reverse?: boolean, dir_first?: boolean, translit?: boolean, sensitive?: boolean }, linemode?: LINEMODE, show_hidden?: boolean, is_predefined?: boolean }>
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

	if not opts or not opts.exclude_cwd then
		local cur_pref = current_pref()
		table.insert(prefs, 1, {
			location = escapeStringPattern(cwd),
			sort = cur_pref.sort,
			linemode = cur_pref.linemode,
			show_hidden = cur_pref.show_hidden,
		})
	end

	local save_path = Url(get_state(STATE_KEY.save_path))
	-- create parent directories
	local save_path_created, err_create =
		fs.create("dir_all", type(save_path.parent) == "function" and save_path:parent() or save_path.parent)
	if err_create then
		fail(
			"Can't create folder: %s",
			tostring(type(save_path.parent) == "function" and save_path:parent() or save_path.parent)
		)
	end

	-- save prefs to file
	if save_path_created then
		-- NOTE: Temporary fix json_encode not save mixed key properly
		local prefs_tmp = deepClone(prefs)
		for _, pref in ipairs(prefs_tmp) do
			if pref.sort ~= nil and type(pref.sort[1]) == "string" then
				pref.sort.by = pref.sort[1]
				pref.sort[1] = nil
			end
		end

		local _, err_write = fs.write(save_path, ya.json_encode(prefs_tmp))
		if err_write then
			fail("Can't write to file: %s", tostring(save_path))
		end
	end

	-- restore predefined preferences
	for _, p in ipairs(prefs_predefined) do
		table.insert(prefs, p)
	end
	set_state(STATE_KEY.prefs, prefs)
	-- trigger update to other instances
	broadcast(PUBSUB_KIND.prefs_changed, prefs)
end

-- This function trigger everytime user change cwd
local change_pref = ya.sync(function()
	local prefs = get_state(STATE_KEY.prefs)
	local cwd = tostring(cx.active.current.cwd)
	-- change pref based on location
	for _, pref in ipairs(prefs) do
		if string.match(cwd, pref.location .. "$") then
			-- sort
			local sort_pref = pref.sort
			if sort_pref then
				ya.dict_merge(sort_pref, {
					tab = (type(cx.active.id) == "number" or type(cx.active.id) == "string") and cx.active.id
						or cx.active.id.value,
				})
				ya.manager_emit("sort", sort_pref)
			end

			-- linemode
			local linemode_pref = pref.linemode
			if linemode_pref then
				ya.manager_emit("linemode", {
					linemode_pref,
					tab = (type(cx.active.id) == "number" or type(cx.active.id) == "string") and cx.active.id
						or cx.active.id.value,
				})
			end

			--show_hidden
			local show_hidden_pref = pref.show_hidden
			if show_hidden_pref ~= nil then
				ya.manager_emit("hidden", {
					show_hidden_pref and "show" or "hide",
					tab = (type(cx.active.id) == "number" or type(cx.active.id) == "string") and cx.active.id
						or cx.active.id.value,
				})

				-- Restore hovered hidden folder
				local last_hovered_folder = get_state(
					STATE_KEY.last_hovered_folder
						.. tostring(
							(type(cx.active.id) == "number" or type(cx.active.id) == "string") and cx.active.id
								or cx.active.id.value
						)
				)

				if last_hovered_folder then
					if
						-- NOTE: Case user move left to right
						(last_hovered_folder.preview_cwd == cwd)
						and last_hovered_folder.preview_hovered_folder
							~= (cx.active.current.hovered and tostring(cx.active.current.hovered.url))
					then
						-- hacky way to wait for hidden fully updated UI, then restore hover
						local args = ya.quote("private-restore-hover")
							.. " "
							.. ya.quote(last_hovered_folder.preview_hovered_folder)
							.. " "
							.. ya.quote(
								(type(cx.active.id) == "number" or type(cx.active.id) == "string") and cx.active.id
									or cx.active.id.value
							)

						ya.manager_emit("plugin", {
							get_state("_id"),
							args,
						})
					elseif
						--NOTE: Case user move from right to left
						(last_hovered_folder.parent_cwd == cwd or not last_hovered_folder.parent_cwd)
						and last_hovered_folder.hovered_folder
							~= (cx.active.current.hovered and tostring(cx.active.current.hovered.url))
					then
						-- hacky way to wait for hidden fully updated UI, then restore hover
						local args = ya.quote("private-restore-hover")
							.. " "
							.. ya.quote(last_hovered_folder.hovered_folder)
							.. " "
							.. ya.quote(
								(type(cx.active.id) == "number" or type(cx.active.id) == "string") and cx.active.id
									or cx.active.id.value
							)

						ya.manager_emit("plugin", {
							get_state("_id"),
							args,
						})
					end
				end
				-- Save parent cwd + parent hovered folder + preview hovered folder

				local parent_folder = cx.active.parent
				set_state(
					STATE_KEY.last_hovered_folder
						.. tostring(
							(type(cx.active.id) == "number" or type(cx.active.id) == "string") and cx.active.id
								or cx.active.id.value
						),
					{
						parent_cwd = parent_folder and tostring(parent_folder.cwd),
						hovered_folder = cwd,
						preview_cwd = cx.active.preview.folder and tostring(cx.active.preview.folder.cwd),
						preview_hovered_folder = cx.active.preview.folder
							and cx.active.preview.folder.hovered
							and tostring(cx.active.preview.folder.hovered.url),
					}
				)
			end
			return
		end
	end
end)

local reset_pref_cwd = function()
	local cwd = current_dir()
	local cur_location = escapeStringPattern(cwd)
	local prefs = get_state(STATE_KEY.prefs)
	for idx = #prefs, 1, -1 do
		if not prefs[idx].is_predefined and prefs[idx].location == cur_location then
			table.remove(prefs, idx)
		end
	end
	set_state(STATE_KEY.prefs, prefs)
	change_pref()
	save_prefs({ exclude_cwd = true })
end

local reload_prefs_from_file = function()
	local saved_prefs = read_prefs_from_saved_file(get_state(STATE_KEY.save_path))
	local old_prefs = get_state(STATE_KEY.prefs)
	local prefs = {}
	-- restore saved preferences from save file
	for idx = #saved_prefs, 1, -1 do
		table.insert(prefs, 1, saved_prefs[idx])
	end
	-- restore predefined prefs
	for _, pref in ipairs(old_prefs) do
		if pref.is_predefined then
			table.insert(prefs, pref)
		end
	end
	set_state(STATE_KEY.prefs, prefs)
	-- trigger update to other instances
	broadcast(PUBSUB_KIND.prefs_changed, prefs)
end

-- sort value is https://yazi-rs.github.io/docs/configuration/keymap#manager.sort
--- @param opts {prefs: table<{ location: string, sort: {[1]?: SORT_BY, reverse?: boolean, dir_first?: boolean, translit?: boolean, sensitive?: boolean }, linemode?: LINEMODE, show_hidden?: boolean, is_predefined?: boolean }>, save_path?: string, disabled?: boolean, no_notify?: boolean }
function M:setup(opts)
	local prefs = type(opts.prefs) == "table" and opts.prefs or {}
	local save_path = (ya.target_family() == "windows" and os.getenv("APPDATA") .. "\\yazi\\config\\pref-by-location")
		or (os.getenv("HOME") .. "/.config/yazi/pref-by-location")
	if type(opts) == "table" then
		set_state(STATE_KEY.disabled, opts.disabled)
		set_state(STATE_KEY.no_notify, opts.no_notify)
		save_path = opts.save_path or save_path
	end

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
	-- dds subscribe on changed directory
	ps.sub("cd", function(_)
		if not get_state(STATE_KEY.loaded) then
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
			set_state(STATE_KEY.loaded, true)
		end
		if get_state(STATE_KEY.disabled) then
			return
		end
		-- NOTE: Trigger if folder is already loaded
		-- NOTE: REMOVE AFTER NEXT UPDATE
		local has_lua54_call_metamethod, loaded = pcall(cx.active.current.stage) -- Triggers error
		if not has_lua54_call_metamethod then
			loaded = not cx.active.current.stage.is_loading
		end

		if loaded then
			change_pref()
		end
	end)

	-- NOTE: project.yazi compatibility
	ps.sub_remote("project-loaded", function(_)
		change_pref()
	end)

	ps.sub("load", function(body)
		if get_state(STATE_KEY.disabled) then
			return
		end
		-- NOTE: Trigger if folder is already loaded
		-- NOTE: REMOVE AFTER NEXT UPDATE
		local has_lua54_call_metamethod, loaded = pcall(body.stage) -- Triggers error
		if not has_lua54_call_metamethod then
			loaded = not body.stage.is_loading
		end

		if loaded and current_dir() == tostring(body.url) then
			change_pref()
		end
	end)

	ps.sub_remote(PUBSUB_KIND.prefs_changed, function(new_prefs)
		set_state(STATE_KEY.prefs, new_prefs)
		change_pref()
	end)

	ps.sub_remote(PUBSUB_KIND.disabled, function(disabled)
		set_state(STATE_KEY.disabled, disabled)
		if not disabled and get_state(STATE_KEY.loaded) then
			change_pref()
		end
	end)
end

function M:entry(job)
	local action = job.args[1]
	if action == "toggle" then
		local disabled = not get_state(STATE_KEY.disabled)
		set_state(STATE_KEY.disabled, disabled)
		-- trigger update to other instances
		broadcast(PUBSUB_KIND.disabled, disabled)
		success(NOTIFY_MSG.TOGGLE, disabled and "Disabled" or "Enabled")
		if not disabled then
			-- reload prefs from saved file
			reload_prefs_from_file()
			change_pref()
		end
	elseif action == "disable" then
		set_state(STATE_KEY.disabled, true)
		-- trigger update to other instances
		broadcast(PUBSUB_KIND.disabled, true)
		success(NOTIFY_MSG.TOGGLE, "Disabled")
	elseif action == "save" then
		save_prefs()
	elseif action == "reset" then
		reset_pref_cwd()
	elseif action == "private-restore-hover" then
		ya.manager_emit("hover", { job.args[2], tab = job.args[3] })
	end
end

return M
