---@since 25.5.31
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
	default_pref = "default_pref",
	disable_fallback_preference = "disable_fallback_preference",
	tasks_write_prefs_running = "tasks_write_prefs_running",
	tasks_write_prefs = "tasks_write_prefs",
}

local function hex_encode(s)
	return (s:gsub(".", function(c)
		return string.format("\\x%02X", c:byte())
	end))
end

local function hex_decode(s)
	return (s:gsub("\\x(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end))
end

local function hex_encode_table(t)
	local out = {}
	for k, v in pairs(t) do
		local new_k = type(k) == "string" and hex_encode(k) or k
		local new_v
		if type(v) == "table" then
			new_v = hex_encode_table(v)
		elseif type(v) == "string" then
			new_v = hex_encode(v)
		else
			new_v = v
		end
		out[new_k] = new_v
	end
	return out
end

local function hex_decode_table(t)
	local out = {}
	for k, v in pairs(t) do
		local new_k = type(k) == "string" and hex_decode(k) or k
		local new_v
		if type(v) == "table" then
			new_v = hex_decode_table(v)
		elseif type(v) == "string" then
			new_v = hex_decode(v)
		else
			new_v = v
		end
		out[new_k] = new_v
	end
	return out
end

local enqueue_task = ya.sync(function(state, task_name, task_data)
	if not state[task_name] or type(state[task_name]) ~= "table" then
		state[task_name] = {}
	end
	table.insert(state[task_name], task_data)
end)

local dequeue_task = ya.sync(function(state, task_name)
	if not state[task_name] or type(state[task_name]) ~= "table" then
		return {}
	end
	return table.remove(state[task_name], 1)
end)

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

local NOTIFY_MSG = {
	TOGGLE = "%s auto-save preference",
}

local function fail(s, ...)
	ya.notify({ title = PackageName, content = string.format(s, ...), timeout = 3, level = "error" })
end

local PUBSUB_KIND = {
	prefs_changed = PackageName .. "-" .. "prefs-changed",
	disabled = "@" .. PackageName .. "-" .. "disabled",
}

local broadcast = ya.sync(function(_, pubsub_kind, data, to)
	ps.pub_to(to or 0, pubsub_kind, data)
end)

local function escapeStringPattern(str)
	return str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

local function is_windows()
	return ya.target_family() == "windows"
end

local function strip_trailing_slash(s)
	if not s or s == "" then
		return s
	end
	return s:gsub("([/\\])+$", "")
end

local function normalize_slashes(s)
	if not s then
		return s
	end
	if is_windows() then
		s = s:gsub("/", "\\")
		if s:sub(1, 2) ~= "\\\\" then
			s = s:gsub("\\\\+", "\\")
		else
			local rest = s:sub(3):gsub("\\\\+", "\\")
			s = "\\\\" .. rest
		end
	else
		s = s:gsub("\\", "/")
		s = s:gsub("//+", "/")
	end
	return s
end

local function normalize_path(s)
	if not s or type(s) ~= "string" then
		return s
	end
	local str = s:gsub("^%s+", ""):gsub("%s+$", "")
	str = normalize_slashes(str)
	str = strip_trailing_slash(str)
	if is_windows() then
		if str:sub(1, 2) ~= "\\\\" then
			str = str:gsub("^([A-Z]):", function(d) return string.lower(d) .. ":" end)
		end
		str = string.lower(str)
	end
	return str
end

local function unescape_pattern_to_literal(escaped)
	if not escaped then
		return escaped
	end
	return escaped:gsub("%%(.)", "%1")
end

local function get_home()
	local home = os.getenv("HOME") or os.getenv("USERPROFILE")
	if not home then
		local hd = os.getenv("HOMEDRIVE")
		local hp = os.getenv("HOMEPATH")
		if hd and hp then
			home = hd .. hp
		end
	end
	return home
end

local function make_tilde_variant(path)
	if not path or type(path) ~= "string" then
		return nil
	end
	local home = get_home()
	if not home or home == "" then
		return nil
	end
	local home_norm = normalize_path(home)
	local p_norm = normalize_path(path)
	if p_norm:sub(1, #home_norm) == home_norm then
		local rest = p_norm:sub(#home_norm + 1)
		if rest == "" then
			return "~"
		end
		rest = rest:gsub("^[/\\]", "")
		local sep = is_windows() and "\\" or "/"
		return "~" .. sep .. rest
	end
	return nil
end

local function unique_list(tbl)
	local seen = {}
	local out = {}
	for _, v in ipairs(tbl) do
		if type(v) == "string" and not seen[v] then
			seen[v] = true
			table.insert(out, v)
		end
	end
	return out
end

local function resolve_link_target(cwd_str)
	if cx and cx.active and cx.active.parent and cx.active.parent.files then
		for i = 1, #cx.active.parent.files do
			local f = cx.active.parent.files[i]
			if tostring(f.url) == cwd_str or normalize_path(tostring(f.url)) == normalize_path(cwd_str) then
				if f.link_to then
					return tostring(f.link_to)
				end
				break
			end
		end
	end

	local try = function(fn, arg)
		local ok, res = pcall(fn, arg)
		if not ok or not res then
			return nil
		end
		return res
	end

	local url_obj
	local ok_url, UrlErr = pcall(function() url_obj = Url(cwd_str) end)
	if not ok_url then
		url_obj = nil
	end

	local info = nil
	if url_obj then
		info = try(fs.info, url_obj) or try(fs.cha, url_obj)
	else
		info = try(fs.info, cwd_str) or try(fs.cha, cwd_str)
	end

	if info then
		local fields = { "link_to", "target", "symlink", "link", "destination" }
		for _, fld in ipairs(fields) do
			if info[fld] then
				return type(info[fld]) == "string" and info[fld] or tostring(info[fld])
			end
		end
		if info.target_url then
			return type(info.target_url) == "string" and info.target_url or tostring(info.target_url)
		end
	end

	return nil
end

local function equivalent_paths_for(cwd_str)
	local out_raw = { cwd_str }
	local link_target = resolve_link_target(cwd_str)
	if link_target and link_target ~= "" then
		table.insert(out_raw, link_target)
	end

	local maybe = {}
	for _, p in ipairs(out_raw) do
		table.insert(maybe, p)
		local tvar = make_tilde_variant(p)
		if tvar then
			table.insert(maybe, tvar)
		end
	end

	local normalized = {}
	for _, p in ipairs(maybe) do
		if type(p) == "string" then
			table.insert(normalized, normalize_path(p))
		end
	end

	return unique_list(normalized)
end

local read_prefs_from_saved_file = function(pref_path)
	local file = io.open(pref_path, "r")
	if file == nil then
		return {}
	end
	local prefs_encoded = file:read("*all")
	file:close()
	local prefs = hex_decode_table(ya.json_decode(prefs_encoded))
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

local function save_prefs()
	if get_state(STATE_KEY.disabled) then
		return
	end

	if get_state(STATE_KEY.tasks_write_prefs_running) or #get_state(STATE_KEY.tasks_write_prefs) == 0 then
		return
	end
	set_state(STATE_KEY.tasks_write_prefs_running, true)
	local opts = dequeue_task(STATE_KEY.tasks_write_prefs)
	local cwd = current_dir()

	local prefs = get_state(STATE_KEY.prefs)
	local prefs_predefined = {}
	for idx = #prefs, 1, -1 do
		if prefs[idx].is_predefined then
			table.insert(prefs_predefined, 1, prefs[idx])
		end

		local eq_paths = equivalent_paths_for(cwd)
		local should_remove = false
		if prefs[idx].is_predefined then
			should_remove = true
		else
			local raw_loc = unescape_pattern_to_literal(prefs[idx].location or "")
			local raw_loc_norm = normalize_path(raw_loc)
			for _, ppath in ipairs(eq_paths) do
				if raw_loc_norm == ppath then
					should_remove = true
					break
				end
			end
		end
		if should_remove then
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
	local save_path_created, err_create = fs.create("dir_all", save_path.parent)
	if err_create then
		fail("Can't create folder: %s", tostring(save_path.parent))
	end

	if save_path_created then
		local prefs_tmp = deepClone(prefs)
		for _, pref in ipairs(prefs_tmp) do
			if pref.sort ~= nil and type(pref.sort[1]) == "string" then
				pref.sort.by = pref.sort[1]
				pref.sort[1] = nil
			end
		end

		local _, err_write = fs.write(save_path, ya.json_encode(hex_encode_table(prefs_tmp)))
		if err_write then
			fail("Can't write to file: %s", tostring(save_path))
		end
	end

	for _, p in ipairs(prefs_predefined) do
		table.insert(prefs, p)
	end
	set_state(STATE_KEY.prefs, prefs)
	broadcast(PUBSUB_KIND.prefs_changed, hex_encode_table(prefs))
	set_state(STATE_KEY.tasks_write_prefs_running, false)
	save_prefs()
end

local update_ui_pref = ya.sync(function(_, pref)
	local sort_pref = pref.sort
	if sort_pref then
		ya.dict_merge(sort_pref, {
			tab = (type(cx.active.id) == "number" or type(cx.active.id) == "string") and cx.active.id
				or cx.active.id.value,
		})
		ya.emit("sort", sort_pref)
	end

	local linemode_pref = pref.linemode
	if linemode_pref then
		ya.emit("linemode", {
			linemode_pref,
			tab = (type(cx.active.id) == "number" or type(cx.active.id) == "string") and cx.active.id
				or cx.active.id.value,
		})
	end

	local show_hidden_pref = pref.show_hidden
	if show_hidden_pref ~= nil then
		ya.emit("hidden", {
			show_hidden_pref and "show" or "hide",
			tab = (type(cx.active.id) == "number" or type(cx.active.id) == "string") and cx.active.id
				or cx.active.id.value,
		})
	end
end)

local change_pref = ya.sync(function()
	local prefs = get_state(STATE_KEY.prefs)

	local cwd = tostring(cx.active.current.cwd)
	local eq_paths = equivalent_paths_for(cwd)

	for _, pref in ipairs(prefs) do
		local raw_loc = unescape_pattern_to_literal(pref.location or "")
		local raw_loc_norm = normalize_path(raw_loc)

		for _, ppath in ipairs(eq_paths) do
			if ppath:sub(- #raw_loc_norm) == raw_loc_norm then
				update_ui_pref(pref)

				local show_hidden_pref = pref.show_hidden
				if show_hidden_pref ~= nil then
					local last_hovered_folder = get_state(
						STATE_KEY.last_hovered_folder
						.. tostring(
							(type(cx.active.id) == "number" or type(cx.active.id) == "string") and cx.active.id
							or cx.active.id.value
						)
					)

					if last_hovered_folder then
						if
							(last_hovered_folder.preview_cwd == cwd)
							and last_hovered_folder.preview_hovered_folder
							~= (cx.active.current.hovered and tostring(cx.active.current.hovered.url))
						then
							ya.emit("reveal", {
								last_hovered_folder.preview_hovered_folder,
								no_dummy = true,
								raw = true,
								tab = (type(cx.active.id) == "number" or type(cx.active.id) == "string") and cx.active
									.id
									or cx.active.id.value,
							})
						elseif
							(last_hovered_folder.parent_cwd == cwd or not last_hovered_folder.parent_cwd)
							and last_hovered_folder.hovered_folder
							~= (cx.active.current.hovered and tostring(cx.active.current.hovered.url))
						then
							ya.emit("reveal", {
								last_hovered_folder.hovered_folder,
								no_dummy = true,
								raw = true,
								tab = (type(cx.active.id) == "number" or type(cx.active.id) == "string") and cx.active
									.id
									or cx.active.id.value,
							})
						end
					end

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
	end
end)

local reset_pref_cwd = function()
	local cwd = current_dir()
	local prefs = get_state(STATE_KEY.prefs)

	local eq = equivalent_paths_for(cwd)
	local eq_escaped = {}
	for _, p in ipairs(eq) do
		table.insert(eq_escaped, normalize_path(p))
	end

	for idx = #prefs, 1, -1 do
		if not prefs[idx].is_predefined then
			local raw_loc = unescape_pattern_to_literal(prefs[idx].location or "")
			local raw_loc_norm = normalize_path(raw_loc)
			for _, esc in ipairs(eq_escaped) do
				if raw_loc_norm == esc then
					table.remove(prefs, idx)
					break
				end
			end
		end
	end
	set_state(STATE_KEY.prefs, prefs)
	if get_state(STATE_KEY.disable_fallback_preference) then
		update_ui_pref(get_state(STATE_KEY.default_pref))
	else
		change_pref()
	end
	enqueue_task(STATE_KEY.tasks_write_prefs, { exclude_cwd = true })
	save_prefs()
end

local reload_prefs_from_file = function()
	local saved_prefs = read_prefs_from_saved_file(get_state(STATE_KEY.save_path))
	local old_prefs = get_state(STATE_KEY.prefs)
	local prefs = {}
	for idx = #saved_prefs, 1, -1 do
		table.insert(prefs, 1, saved_prefs[idx])
	end
	for _, pref in ipairs(old_prefs) do
		if pref.is_predefined then
			table.insert(prefs, pref)
		end
	end
	set_state(STATE_KEY.prefs, prefs)
	broadcast(PUBSUB_KIND.prefs_changed, hex_encode_table(prefs))
end

function M:is_literal_string(str)
	return str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

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
	for _, pref in ipairs(prefs) do
		pref.is_predefined = true
	end
	local saved_prefs = read_prefs_from_saved_file(get_state(STATE_KEY.save_path))
	for idx = #saved_prefs, 1, -1 do
		table.insert(prefs, 1, saved_prefs[idx])
	end

	local default_pref = {
		location = ".*",
		sort = {
			rt.mgr.sort_by,
			reverse = rt.mgr.sort_reverse,
			dir_first = rt.mgr.sort_dir_first,
			translit = rt.mgr.sort_translit,
			sensitive = rt.mgr.sort_sensitive,
		},
		linemode = rt.mgr.linemode,
		show_hidden = rt.mgr.show_hidden,
		is_predefined = true,
	}

	if opts and opts.disable_fallback_preference == true then
		set_state(STATE_KEY.default_pref, default_pref)
		set_state(STATE_KEY.disable_fallback_preference, true)
	else
		table.insert(prefs, deepClone(default_pref))
	end
	set_state(STATE_KEY.prefs, prefs)
	set_state(STATE_KEY.loaded, true)

	ps.sub("cd", function(_)
		if get_state(STATE_KEY.disabled) then
			return
		end
		if cx.active.current.stage then
			change_pref()
		end
	end)

	ps.sub_remote("project-loaded", function(_)
		change_pref()
	end)

	ps.sub("load", function(body)
		if get_state(STATE_KEY.disabled) then
			return
		end
		if body.stage and current_dir() == tostring(body.url) then
			change_pref()
		end
	end)

	ps.sub_remote(PUBSUB_KIND.prefs_changed, function(new_prefs)
		new_prefs = hex_decode_table(new_prefs)
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
		broadcast(PUBSUB_KIND.disabled, disabled)
		success(NOTIFY_MSG.TOGGLE, disabled and "Disabled" or "Enabled")
		if not disabled then
			reload_prefs_from_file()
			change_pref()
		end
	elseif action == "disable" then
		set_state(STATE_KEY.disabled, true)
		broadcast(PUBSUB_KIND.disabled, true)
		success(NOTIFY_MSG.TOGGLE, "Disabled")
	elseif action == "save" then
		enqueue_task(STATE_KEY.tasks_write_prefs, {})
		save_prefs()
	elseif action == "reset" then
		reset_pref_cwd()
	end
end

return M
