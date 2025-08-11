# pref-by-location

- [pref-by-location](#pref-by-location)
  - [Requirements](#requirements)
  - [Preferences priority](#preferences-priority)
  - [Installation](#installation)
    - [Add setup function in `yazi/init.lua`.](#add-setup-function-in-yaziinitlua)
    - [Add `keymap.toml`](#add-keymaptoml)
  - [Behavior notes](#behavior-notes)
    - [Symbolic links and canonical paths](#symbolic-links-and-canonical-paths)
    - [Tilde (`~`) shorthand for home directory](#tilde--shorthand-for-home-directory)
    - [Path normalization and matching](#path-normalization-and-matching)
  - [For developers](#for-developers)
    - [Notes for adding preferences:](#notes-for-adding-preferences)

This is a Yazi plugin that save these preferences by location:

* [linemode](https://yazi-rs.github.io/docs/configuration/yazi#mgr.linemode)
* [sort](https://yazi-rs.github.io/docs/configuration/yazi#mgr.sort_by)
* [show\_hidden](https://yazi-rs.github.io/docs/configuration/yazi#mgr.show_hidden)

> [!IMPORTANT] Minimum version: yazi v25.5.31.
>
> This plugin will conflict with folder-rules. You should remove it. [https://yazi-rs.github.io/docs/tips#folder-rules](https://yazi-rs.github.io/docs/tips#folder-rules)

## Requirements

* [yazi >= 25.5.31](https://github.com/sxyazi/yazi)
* Tested on Linux; compatible with Windows.

## Preferences priority

This plugin will pick the first matching preference. The order of preferences is:

* Manually saved preferences (using `plugin pref-by-location -- save`).
* Predefined preferences (in `setup` function).
* Default preferences (in `yazi.toml`)

## Installation

Install the plugin:

```sh
ya pkg add boydaihungst/pref-by-location
```

### Add setup function in `yazi/init.lua`.

Prefs is optional but the setup function is required.

```lua
local pref_by_location = require("pref-by-location")
pref_by_location:setup({
  -- Disable this plugin completely.
  -- disabled = false -- true|false (Optional)

  -- Hide "enable" and "disable" notifications.
  -- no_notify = false -- true|false (Optional)

  -- Disable the fallback/default preference (values in `yazi.toml`).
  -- disable_fallback_preference = false -- true|false|nil (Optional)

  -- You can backup/restore this file. But don't use same file in the different OS.
  -- save_path =  -- full path to save file (Optional)
  --       - Linux/MacOS: os.getenv("HOME") .. "/.config/yazi/pref-by-location"
  --       - Windows: os.getenv("APPDATA") .. "\\yazi\\config\\pref-by-location"

  -- This is predefined preferences.
  prefs = { -- (Optional)
    -- location: String | Lua pattern (Required)
    --   - Support literals full path, lua pattern (string.match pattern): https://www.lua.org/pil/20.2.html
    --   - Use pref_by_location.is_literal_string(...) to escape special characters when needed

		{ location = "~\\Downloads", sort = { "mtime", reverse = true, dir_first = false } },
    { location = "^/mnt/remote/.*", sort = { "extension", reverse = false, dir_first = true, sensitive = false} },
    { location = ".*/Downloads", sort = { "btime", reverse = true, dir_first = true }, linemode = "btime" },
    { location = pref_by_location.is_literal_string("/home/test/Videos"), sort = { "btime", reverse = true, dir_first = true }, linemode = "btime" },

    {
	    location = ".*/secret",
	    sort = { "natural", reverse = false, dir_first = true },
	    linemode = "size",
	    show_hidden = true,
    },

    {
	    location = ".*/abc",
	    linemode = "size_and_mtime",
    },
  },
})
```

### Add `keymap.toml`

> [!IMPORTANT] Always run `"plugin pref-by-location -- save"` after changed hidden, linemode, sort

Since Yazi selects the first matching key to run, `prepend_keymap` always has a higher priority than default. Or you can use `keymap` to replace all other keys

More information about these commands and their arguments:

* [linemode](https://yazi-rs.github.io/docs/configuration/keymap#mgr.linemode)
* [sort](https://yazi-rs.github.io/docs/configuration/keymap#mgr.sort)
* [hidden](https://yazi-rs.github.io/docs/configuration/keymap#mgr.hidden)

> [!IMPORTANT] NOTE 1 disable and toggle functions behavior:
>
> * Toggle and disable sync across instances.
> * Enabled/disabled state will be persistently stored.
> * Any changes during disabled state won't be saved to save file.
> * Switching from disabled to enabled state will reload all preferences from the save file for all instances, preventing conflicts when more than one instance changed the preferences of the same folder. This also affect to current working directory (cwd).

> [!IMPORTANT] NOTE 2 Sort = size and Linemode = size behavior: If Sort = size and Linemode = size. You will notice a delay if cwd folder is large. It has to wait for all child folders to fully load (calculate size) before applying the preferences.

```toml
[mgr]
  prepend_keymap = [
    { on = ".", run = [ "hidden toggle", "plugin pref-by-location -- save" ], desc = "Toggle the visibility of hidden files" },

    { on = [ "m", "s" ], run = [ "linemode size", "plugin pref-by-location -- save" ],        desc = "Linemode: size" },
    { on = [ "m", "p" ], run = [ "linemode permissions", "plugin pref-by-location -- save" ], desc = "Linemode: permissions" },
    { on = [ "m", "b" ], run = [ "linemode btime", "plugin pref-by-location -- save" ],       desc = "Linemode: btime" },
    { on = [ "m", "m" ], run = [ "linemode mtime", "plugin pref-by-location -- save" ],       desc = "Linemode: mtime" },
    { on = [ "m", "o" ], run = [ "linemode owner", "plugin pref-by-location -- save" ],       desc = "Linemode: owner" },
    { on = [ "m", "n" ], run = [ "linemode none", "plugin pref-by-location -- save" ],        desc = "Linemode: none" },

    { on = [ ",", "t" ], run = "plugin pref-by-location -- toggle",                                                desc = "Toggle auto-save preferences" },
    { on = [ ",", "d" ], run = "plugin pref-by-location -- disable",                                               desc = "Disable auto-save preferences" },
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
    { on = [ ",", "s" ], run = [ "sort size --reverse=no", "linemode size", "plugin pref-by-location -- save" ],   desc = "Sort by size" },
    { on = [ ",", "S" ], run = [ "sort size --reverse", "linemode size", "plugin pref-by-location -- save" ],      desc = "Sort by size (reverse)" },
    { on = [ ",", "r" ], run = [ "sort random --reverse=no", "plugin pref-by-location -- save" ],                  desc = "Sort randomly" },
]
```

## Behavior notes

### Symbolic links and canonical paths

The plugin resolves symbolic links and treats symlink locations and their target (canonical) paths as equivalent when matching and saving preferences. Matching is performed against all equivalent forms of the current working directory (for example, the symlink path and the link's target path). Preference save/reset logic also takes these equivalents into account to avoid duplicate entries for the same logical folder.

When the parent folder is loaded, the plugin first attempts to read the symlink target from the file entry metadata. If that metadata is not available, the plugin falls back to file-system metadata queries. This makes matching robust across common filesystem layouts and link types (junctions, symlinks, reparse points).

### Tilde (`~`) shorthand for home directory

The plugin accepts `~` as shorthand for the current user's home directory in `location` patterns. Both `~/folder` (Unix-style) and `~\folder` (Windows-style) patterns are recognized and resolved to the actual home path when matching preferences.

Examples:

* `~\Downloads` will match `C:\Users\<you>\Downloads` on Windows (when the home folder resolves to `C:\Users\<you>`).
* `~/Downloads` will match `/home/<you>/Downloads` on Unix-like systems.

### Path normalization and matching

Paths and preference locations are normalized before comparison:

* Path separators are normalized (both `/` and `\` are handled).
* Extra/trailing separators are removed.
* On Windows, comparisons are case-insensitive (paths are normalized to a canonical case for matching).
* Preferences use suffix matching against normalized paths (so patterns like `.*/Downloads` will match both `~/Downloads` and the canonical absolute path).

These normalization rules reduce false negatives caused by different path notations or case differences.

## For developers

Trigger this plugin programmatically:

```lua
local pref_by_location = require("pref-by-location")
local action = "save" -- available actions: save, reset, toggle, disable
local args = ya.quote(action)
ya.emit("plugin", {
  pref_by_location._id,
  args,
})
```

### Notes for adding preferences:

* Use `pref_by_location.is_literal_string(path)` to escape special Lua pattern characters when you want an exact literal match.
* Preferences defined with `~` or that target a path referenced by symlink will match equivalent folders and will not be duplicated when saved/reset.
* Always run `"plugin pref-by-location -- save"` after changing linemode, sort or show\_hidden via keymap so the plugin persists the current preference for the current working directory.
