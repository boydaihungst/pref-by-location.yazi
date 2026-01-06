# pref-by-location

<!--toc:start-->

- [pref-by-location](#pref-by-location)
  - [Requirements](#requirements)
  - [Preferences priority](#preferences-priority)
  - [Installation](#installation)
    - [Add setup function in `yazi/init.lua`.](#add-setup-function-in-yaziinitlua)
    - [Add `keymap.toml`](#add-keymaptoml)
  - [For developers](#for-developers)
  <!--toc:end-->

This is a Yazi plugin that save these preferences by location:

- [linemode](https://yazi-rs.github.io/docs/configuration/yazi#mgr.linemode)
- [sort](https://yazi-rs.github.io/docs/configuration/yazi#mgr.sort_by)
- [show_hidden](https://yazi-rs.github.io/docs/configuration/yazi#mgr.show_hidden)

> [!IMPORTANT]
> Minimum version: yazi v25.5.31.
>
> This plugin will conflict with folder-rules. You should remove it.
> https://yazi-rs.github.io/docs/tips#folder-rules

## Requirements

- [yazi >= 25.5.31](https://github.com/sxyazi/yazi)
- Tested on Linux.

## Preferences priority

This plugin will pick the first matching preference. The order of preferences is:

- Manually saved preferences (using `plugin pref-by-location -- save`).
- Predefined preferences (in `setup` function).
- Default preferences (in `yazi.toml`)

## Installation

Install the plugin:

```sh
ya pkg add boydaihungst/pref-by-location
```

### Add setup function in `yazi/init.lua`.

All the options inside setup function are optional, but the setup function itself is required.

```lua
local pref_by_location = require("pref-by-location")
pref_by_location:setup({
  -- Disable this plugin completely.
  -- disabled = false -- true|false (Optional)

  -- Hide "enable" and "disable" notifications.
  -- no_notify = false -- true|false (Optional)

  -- Disable the fallback/default preference (values in `yazi.toml`).
  -- This mean if none of the saved or predifined perferences is matched,
  -- then it won't reset preference to default values in yazi.toml.
  -- For example, go from folder A to folder B (folder B matchs saved preference to show hidden files) -> show hidden.
  -- Then move back to folder A -> keep showing hidden files, because the folder A doesn't match any saved or predefined preference.
  -- disable_fallback_preference = false -- true|false|nil (Optional)

  -- You can backup/restore this file. But don't use same file in the different OS.
  -- save_path =  -- full path to save file (Optional)
  --       - Linux/MacOS: os.getenv("HOME") .. "/.config/yazi/pref-by-location"
  --       - Windows: os.getenv("APPDATA") .. "\\yazi\\config\\pref-by-location"

  -- https://github.com/MasouShizuka/projects.yazi compatibility
  -- If you use projects.yazi plugin and changed it's default yazi_load_event config, you have to set this value to equal projects.yazi > setup function > save > yazi_load_event. Default is "@projects-load"
  -- project_plugin_load_event = "@projects-load" -- string (Optional)

  -- This is predefined preferences.
  prefs = { -- (Optional)
    -- location: String | Lua pattern (Required)
    --   - Support literals full path, lua pattern (string.match pattern): https://www.lua.org/pil/20.2.html
    --     And don't put ($) sign at the end of the location. %$ is ok.
    --   - If you want to use special characters (such as . * ? + [ ] ( ) ^ $ %) in "location"
    --     you need to escape them with a percent sign (%) or use a helper funtion `pref_by_location.is_literal_string`
    --     Example: "/home/test/Hello (Lua) [world]" => { location = "/home/test/Hello %(Lua%) %[world%]", ....}
    --     or { location = pref_by_location.is_literal_string("/home/test/Hello (Lua) [world]"), .....}

    -- sort: {} (Optional) https://yazi-rs.github.io/docs/configuration/yazi#mgr.sort_by
    --   - extension: "none"|"mtime"|"btime"|"extension"|"alphabetical"|"natural"|"size"|"random", (Optional)
    --   - reverse: true|false (Optional)
    --   - dir_first: true|false (Optional)
    --   - translit: true|false (Optional)
    --   - sensitive: true|false (Optional)

    -- linemode: "none" |"size" |"btime" |"mtime" |"permissions" |"owner" (Optional) https://yazi-rs.github.io/docs/configuration/yazi#mgr.linemode
    --   - Custom linemode also work. See the example below

    -- show_hidden: true|false (Optional) https://yazi-rs.github.io/docs/configuration/yazi#mgr.show_hidden

    -- Some examples:
    -- Match any folder which has path start with "/mnt/remote/". Example: /mnt/remote/child/child2
    { location = "^/mnt/remote/.*", sort = { "extension", reverse = false, dir_first = true, sensitive = false} },
    -- Match any folder with name "Downloads"
    { location = ".*/Downloads", sort = { "btime", reverse = true, dir_first = true }, linemode = "btime" },
    -- Match exact folder with absolute path "/home/test/Videos".
    -- Use helper function `pref_by_location.is_literal_string` to prevent the case where the path contains special characters
    { location = pref_by_location.is_literal_string("/home/test/Videos"), sort = { "btime", reverse = true, dir_first = true }, linemode = "btime" },

    -- show_hidden for any folder with name "secret"
    {
	    location = ".*/secret",
	    sort = { "natural", reverse = false, dir_first = true },
	    linemode = "size",
	    show_hidden = true,
    },

    -- Custom linemode also work
    {
	    location = ".*/abc",
	    linemode = "size_and_mtime",
    },
    -- DO NOT ADD location = ".*". Which currently use your yazi.toml config as fallback.
    -- That mean if none of the saved perferences is matched, then it will use your config from yazi.toml.
    -- So change linemode, show_hidden, sort_xyz in yazi.toml instead.
  },
})
```

### Add `keymap.toml`

> [!IMPORTANT]
> Always run `"plugin pref-by-location -- save"` after changed hidden, linemode, sort

Since Yazi selects the first matching key to run, `prepend_keymap` always has a higher priority than default.
Or you can use `keymap` to replace all other keys

More information about these commands and their arguments:

- [linemode](https://yazi-rs.github.io/docs/configuration/keymap#mgr.linemode)
- [sort](https://yazi-rs.github.io/docs/configuration/keymap#mgr.sort)
- [hidden](https://yazi-rs.github.io/docs/configuration/keymap#mgr.hidden)

> [!IMPORTANT]
> NOTE 1 disable and toggle functions behavior:
>
> - Toggle and disable sync across instances.
> - Enabled/disabled state will be persistently stored.
> - Any changes during disabled state won't be saved to save file.
> - Switching from disabled to enabled state will reload all preferences
>   from the save file for all instances, preventing conflicts
>   when more than one instance changed the preferences of the same folder.
>   This also affect to current working directory (cwd).

> [!IMPORTANT]
> NOTE 2 Sort = size and Linemode = size behavior:
> If Sort = size and Linemode = size.
> You will notice a delay if cwd folder is large.
> It has to wait for all child folders to fully load (calculate size) before applying
> the preferences.

```toml
[mgr]
  prepend_keymap = [
    # Toggle Hidden
    { on = ".", run = [ "hidden toggle", "plugin pref-by-location -- save" ], desc = "Toggle the visibility of hidden files" },

    # Linemode
    { on = [ "m", "s" ], run = [ "linemode size", "plugin pref-by-location -- save" ],        desc = "Linemode: size" },
    { on = [ "m", "p" ], run = [ "linemode permissions", "plugin pref-by-location -- save" ], desc = "Linemode: permissions" },
    { on = [ "m", "b" ], run = [ "linemode btime", "plugin pref-by-location -- save" ],       desc = "Linemode: btime" },
    { on = [ "m", "m" ], run = [ "linemode mtime", "plugin pref-by-location -- save" ],       desc = "Linemode: mtime" },
    { on = [ "m", "o" ], run = [ "linemode owner", "plugin pref-by-location -- save" ],       desc = "Linemode: owner" },
    { on = [ "m", "n" ], run = [ "linemode none", "plugin pref-by-location -- save" ],        desc = "Linemode: none" },
    # Custom size_and_mtime linemode
    # { on = [ "u", "S" ], run = [ "linemode size_and_mtime", "plugin pref-by-location -- save" ], desc = "Show Size and Modified time" },

    # Sorting
    # Any changes during disabled state won't be saved to save file.
    { on = [ ",", "t" ], run = "plugin pref-by-location -- toggle",                                                desc = "Toggle auto-save preferences" },
    { on = [ ",", "d" ], run = "plugin pref-by-location -- disable",                                               desc = "Disable auto-save preferences" },
    # This will reset any preference changes for the current working directory (CWD),
    # then fall back to the predefined preferences in init.lua or yazi.toml.
    { on = [ ",", "R" ], run = [ "plugin pref-by-location -- reset" ],                                             desc = "Reset preference of cwd" },
    { on = [ ",", "m" ], run = [ "sort mtime --reverse=no", "linemode mtime", "plugin pref-by-location -- save" ], desc = "Sort by modified time" },
    { on = [ ",", "M" ], run = [ "sort mtime --reverse", "linemode mtime", "plugin pref-by-location -- save" ],    desc = "Sort by modified time (reverse)" },
    { on = [ ",", "b" ], run = [ "sort btime --reverse=no", "linemode btime", "plugin pref-by-location -- save" ], desc = "Sort by birth time" },
    { on = [ ",", "B" ], run = [ "sort btime --reverse", "linemode btime", "plugin pref-by-location -- save" ],    desc = "Sort by birth time (reverse)" },
    { on = [ ",", "e" ], run = [ "sort extension --reverse=no", "plugin pref-by-location -- save" ],               desc = "Sort by extension" },
    { on = [ ",", "E" ], run = [ "sort extension --reverse", "plugin pref-by-location -- save" ],                  desc = "Sort by extension (reverse)" },
    { on = [ ",", "a" ], run = [ "sort alphabetical --reverse=no", "plugin pref-by-location -- save" ],            desc = "Sort alphabetically" },
    { on = [ ",", "A" ], run = [ "sort alphabetical --reverse", "plugin pref-by-location -- save" ],               desc = "Sort alphabetically (reverse)" },
    { on = [ ",", "n" ], run = [ "sort natural --reverse=no", "plugin pref-by-location -- save" ],                 desc = "Sort naturally" },
    { on = [ ",", "N" ], run = [ "sort natural --reverse", "plugin pref-by-location -- save" ],                    desc = "Sort naturally (reverse)" },
    # --sensitive=no or --sensitive
    # { on = [ ",", "N" ], run = [ "sort natural --reverse=no --sensitive", "plugin pref-by-location -- save" ],                    desc = "Sort naturally" },
    { on = [ ",", "s" ], run = [ "sort size --reverse=no", "linemode size", "plugin pref-by-location -- save" ],   desc = "Sort by size" },
    { on = [ ",", "S" ], run = [ "sort size --reverse", "linemode size", "plugin pref-by-location -- save" ],      desc = "Sort by size (reverse)" },
    { on = [ ",", "r" ], run = [ "sort random --reverse=no", "plugin pref-by-location -- save" ],                  desc = "Sort randomly" },
]
```

## For developers

Trigger this plugin programmatically:

```lua
-- In your plugin:
local pref_by_location = require("pref-by-location")
-- Available actions: save, reset, toggle, disable
  local action = "save"
	local args = ya.quote(action)
	ya.emit("plugin", {
		pref_by_location._id,
		args,
	})
```
