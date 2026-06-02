--- @since 25.4.8
-- stylua: ignore
local SUPPORTED_KEYS = {
	{ on = "h", desc = "Free" }, { on = "j", desc = "Free" }, { on = "k", desc = "Free" }, { on = "l", desc = "Free" },
	{ on = ";", desc = "Free" }, { on = "n", desc = "Free" }, { on = "m", desc = "Free" }, { on = ",", desc = "Free" }, { on = ".", desc = "Free" },
	{ on = "1", desc = "Free" }, { on = "2", desc = "Free" }, { on = "3", desc = "Free" }, { on = "4", desc = "Free" }, { on = "5", desc = "Free" },
	{ on = "6", desc = "Free" }, { on = "7", desc = "Free" }, { on = "8", desc = "Free" }, { on = "9", desc = "Free" }, { on = "0", desc = "Free" },
}

local KEY_ORDER = {}
for i, k in ipairs(SUPPORTED_KEYS) do KEY_ORDER[k.on] = i end

local NOTIFY_DEFAULTS = {
	enable = true,
	timeout = 1,
	message = {
		new = "Bookmark '<key>' -> '<folder>'",
		delete = "Deleted bookmark in '<key>'",
		delete_all = "Deleted all bookmarks",
	},
}

local _send_notification = ya.sync(
	function(state, message)
		local notify = state.notify or NOTIFY_DEFAULTS
		ya.notify {
			title = "Bookmarks",
			content = message,
			timeout = notify.timeout,
		}
	end
)

local _get_real_index = ya.sync(function(state, idx)
	for key, value in pairs(state.bookmarks) do
		if value.on == SUPPORTED_KEYS[idx].on then
			return key
		end
	end
	return nil
end)

local _get_bookmark_file = ya.sync(function(state)
	local folder = cx.active.current

	if state.file_pick_mode == "parent" or not folder.hovered then
		return { url = folder.cwd, is_parent = true }
	end
	return { url = folder.hovered.url, is_parent = false }
end)

local _generate_description = ya.sync(function(state, file)
	-- if this is true, we don't have information about the folder, so just return the folder url
	if file.is_parent then
		return tostring(file.url)
	end

	if state.desc_format == "parent" then
		return tostring(file.url.parent)
	end
	-- full description
	return tostring(file.url)
end)

local _load_state = ya.sync(function(state)
	ps.sub_remote("@bookmarks", function(body)
		if not state.bookmarks and body then
			state.bookmarks = {}
			for _, value in pairs(body) do
				table.insert(state.bookmarks, value)
			end
		end
	end)
end)

local _save_state = ya.sync(function(state, bookmarks)
	if not bookmarks then
		ps.pub_to(0, "@bookmarks", nil)
		return
	end

	local save_state = {}
	if state.persist == "all" then
		save_state = bookmarks
	else -- VIM mode
		local idx = 1
		for _, value in pairs(bookmarks) do
			-- Only save bookmarks in upper case keys
			if string.match(value.on, "%u") then
				save_state[idx] = value
				idx = idx + 1
			end
		end
	end

	ps.pub_to(0, "@bookmarks", save_state)
end)

local _load_last = ya.sync(function(state)
	ps.sub_remote("@bookmarks-last", function(body)
		state.last_dir = body

		if state.last_mode ~= "dir" then
			ps.unsub_remote("@bookmarks-last")
		end
	end)
end)

local _save_last = ya.sync(function(state, persist, immediate)
	local file = _get_bookmark_file()

	local curr = {
		on = "'",
		desc = _generate_description(file),
		path = tostring(file.url),
		is_parent = file.is_parent,
	}

	if immediate then
		state.curr_dir = nil
		state.last_dir = curr
	else
		state.last_dir = state.curr_dir
		state.curr_dir = curr
	end

	if persist and state.last_dir then
		ps.pub_to(0, "@bookmarks-last", state.last_dir)
	end
end)

local get_last_mode = ya.sync(function(state) return state.last_mode end)

local save_last_dir = ya.sync(function(state)
	ps.sub("cd", function() _save_last(state.last_persist, false) end)

	ps.sub("hover", function()
		if not state.curr_dir then
			return
		end
		local file = _get_bookmark_file()
		state.curr_dir.desc = _generate_description(file)
		state.curr_dir.path = tostring(file.url)
	end)
end)

local save_last_jump = ya.sync(function(state) _save_last(state.last_persist, true) end)

local save_last_mark = ya.sync(function(state) _save_last(state.last_persist, true) end)

local _is_show_keys_enabled = ya.sync(function(state) return state.show_keys end)

local _is_custom_desc_input_enabled = ya.sync(function(state) return state.custom_desc_input end)

-- ***********************************************
-- **============= C O M M A N D S =============**
-- ***********************************************

local get_updated_keys = ya.sync(function(state, keys)
	if state.bookmarks then
		for _, bookmarks_value in pairs(state.bookmarks) do
			for _, keys_value in pairs(keys) do
				if keys_value.on == bookmarks_value.on then
					keys_value.desc = bookmarks_value.desc
				end
			end
		end
	end
	return keys
end)

local save_bookmark = ya.sync(function(state, idx, custom_desc)
	local file = _get_bookmark_file()

	state.bookmarks = state.bookmarks or {}

	local _idx = _get_real_index(idx)
	if not _idx then
		_idx = #state.bookmarks + 1
	end

	local bookmark_desc = tostring(_generate_description(file))
	if custom_desc then
		bookmark_desc = tostring(custom_desc)
	end

	local new_bookmark = {
		on = SUPPORTED_KEYS[idx].on,
		desc = bookmark_desc,
		path = tostring(file.url),
		is_parent = file.is_parent,
	}
	state.bookmarks[_idx] = new_bookmark

	table.sort(state.bookmarks, function(a, b)
		return (KEY_ORDER[a.on] or 999) < (KEY_ORDER[b.on] or 999)
	end)

	if state.persist then
		_save_state(state.bookmarks)
	end

	local notify = state.notify or NOTIFY_DEFAULTS
	if notify.enable then
		local message = notify.message.new
		message, _ = message:gsub("<key>", new_bookmark.on)
		message, _ = message:gsub("<folder>", new_bookmark.desc)
		_send_notification(message)
	end

	if get_last_mode() == "mark" then
		save_last_mark()
	end
end)

local all_bookmarks = ya.sync(function(state, append_last_dir)
	local bookmarks = {}

	if state.bookmarks then
		for _, value in pairs(state.bookmarks) do
			table.insert(bookmarks, value)
		end
	end

	if append_last_dir and state.last_dir then
		table.insert(bookmarks, state.last_dir)
	end

	return bookmarks
end)

local delete_bookmark = ya.sync(function(state, idx)
	local notify = state.notify or NOTIFY_DEFAULTS
	if notify.enable then
		local message = notify.message.delete
		message, _ = message:gsub("<key>", state.bookmarks[idx].on)
		message, _ = message:gsub("<folder>", state.bookmarks[idx].desc)
		_send_notification(message)
	end

	table.remove(state.bookmarks, idx)

	if state.persist then
		_save_state(state.bookmarks)
	end
end)

local delete_all_bookmarks = ya.sync(function(state)
	state.bookmarks = nil

	if state.persist then
		_save_state(nil)
	end

	local notify = state.notify or NOTIFY_DEFAULTS
	if notify.enable then
		_send_notification(notify.message.delete_all)
	end
end)

return {
	entry = function(_, job)
		local action = job.args[1]
		if not action then
			return
		end

		if action == "save" then
			if _is_show_keys_enabled() then
				SUPPORTED_KEYS = get_updated_keys(SUPPORTED_KEYS)
			end
			local key = ya.which { cands = SUPPORTED_KEYS, silent = not _is_show_keys_enabled() }
			if key then
				if _is_custom_desc_input_enabled() then
					local value, event = ya.input {
						title = "Save with custom description:",
						pos = { "top-center", y = 3, w = 60 },
						value = tostring(_get_bookmark_file().url),
					}
					if event ~= 1 then
						return
					end

					save_bookmark(key, value)
					return
				end
				save_bookmark(key)
			end
			return
		end

		if action == "delete_all" then
			return delete_all_bookmarks()
		end

		local bookmarks = all_bookmarks(action == "jump")
		local selected = #bookmarks > 0 and ya.which { cands = bookmarks }
		if not selected then
			return
		end

		if action == "jump" then
			if get_last_mode() == "jump" then
				save_last_jump()
			end

			if bookmarks[selected].is_parent then
				ya.emit("cd", { bookmarks[selected].path })
			else
				ya.emit("reveal", { bookmarks[selected].path })
			end
		elseif action == "delete" then
			delete_bookmark(selected)
		end
	end,
	setup = function(state, args)
		if not args then
			return
		end

		if type(args.last_directory) == "table" then
			if args.last_directory.enable then
				if args.last_directory.mode == "mark" then
					state.last_persist = args.last_directory.persist
					state.last_mode = "mark"
				elseif args.last_directory.mode == "jump" then
					state.last_persist = args.last_directory.persist
					state.last_mode = "jump"
				elseif args.last_directory.mode == "dir" then
					state.last_persist = args.last_directory.persist
					state.last_mode = "dir"
					save_last_dir()
				else
					-- default
					state.last_persist = args.last_directory.persist
					state.last_mode = "dir"
					save_last_dir()
				end

				if args.last_directory.persist then
					_load_last()
				end
			end
		end

		if args.persist == "all" or args.persist == "vim" then
			state.persist = args.persist
			_load_state()
		end

		if args.desc_format == "parent" then
			state.desc_format = "parent"
		else
			state.desc_format = "full"
		end

		if args.file_pick_mode == "parent" then
			state.file_pick_mode = "parent"
		else
			state.file_pick_mode = "hover"
		end

		if type(args.custom_desc_input) == "boolean" then
			state.custom_desc_input = args.custom_desc_input
		end

		if type(args.show_keys) == "boolean" then
			state.show_keys = args.show_keys
		end

		state.notify = {
			enable = true,
			timeout = NOTIFY_DEFAULTS.timeout,
			message = {
				new = NOTIFY_DEFAULTS.message.new,
				delete = NOTIFY_DEFAULTS.message.delete,
				delete_all = NOTIFY_DEFAULTS.message.delete_all,
			},
		}
		if type(args.notify) == "table" then
			if type(args.notify.enable) == "boolean" then
				state.notify.enable = args.notify.enable
			end
			if type(args.notify.timeout) == "number" then
				state.notify.timeout = args.notify.timeout
			end
			if type(args.notify.message) == "table" then
				if type(args.notify.message.new) == "string" then
					state.notify.message.new = args.notify.message.new
				end
				if type(args.notify.message.delete) == "string" then
					state.notify.message.delete = args.notify.message.delete
				end
				if type(args.notify.message.delete_all) == "string" then
					state.notify.message.delete_all = args.notify.message.delete_all
				end
			end
		end
	end,
}
