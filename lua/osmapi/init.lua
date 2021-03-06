local lxp = require ("lxp")
local moses = require ("moses")
local utils = require("osmapi.utils")

local http = require("socket.http")
http.TIMEOUT = 3
http.USERAGENT = "lua-osmapi/0.0"

-- module table
local _M = {}

local APIURL = "http://api.openstreetmap.org/api"

local objects = {}
local obj_count = { node = 0, way = 0, relation = 0, refs = 0, tags = 0 }

local xml_parser = nil
local file = "input"
local parent_element = nil
local in_osm_tag = false

local function file_pos_format(file, line, pos)
	return ("%s:%d:%d"):format(file, line, pos)
end

--- Build node ID(s) for index access in objects()
function _M.node_id(ids) return utils.prefix_id("n", ids) end
--- Build way ID(s) for index access in objects()
function _M.way_id(ids) return utils.prefix_id("w", ids) end
--- Build relation ID(s) for index access in objects()
function _M.relation_id(ids) return utils.prefix_id("r", ids) end
--- Split (single) ID into object type part and ID part
-- @returns type, id
function _M.split_id(id)
	return string.sub(id, 1, 1), tonumber(string.sub(id, 2))
end
local function build_id(tagname, id)
	if     tagname == "node"     or tagname == "n" then return _M.node_id(id)
	elseif tagname == "way"      or tagname == "w" then return _M.way_id(id)
	elseif tagname == "relation" or tagname == "r" then return _M.relation_id(id)
	end
end

--
-- Expat callbacks
--
local function StartElement(parser, tagname, attrs)
	local line, pos = parser:pos()

	if not in_osm_tag and tagname ~= "osm" then
		print("Error: No <osm> root element!")
		parser:stop()
		return
	elseif tagname == "osm" then
		in_osm_tag = true
		return
	end

	-- parse node, way, relation
	if (tagname == "node" or tagname == "way" or tagname == "relation") then
		if parent_element then
			print(("Error: %s: <%s> inside of node|way|relation!")
				:format(file_pos_format(file_pos_format(file, line, pos)), tagname))
			parser:stop()
		end
		if not attrs.id then
			print(("Error: %s: <%s> without id attribute!")
				:format(file_pos_format(file, line, pos), tagname))
			parser:stop()
			return
		end

		local cur_obj = {}

		-- nodes
		if tagname == "node" then
			if not attrs.lat or not attrs.lon then
				print(("Error: %s: <node> without lat/lon attribute!")
					:format(file_pos_format(file, line, pos)))
				parser:stop()
				return
			end

			cur_obj.id = _M.node_id(attrs.id)
			cur_obj.lat = attrs.lat
			cur_obj.lon = attrs.lon
		end

		-- ways
		if tagname == "way" then
			cur_obj.id = _M.way_id(attrs.id)
		end

		-- relations
		if tagname == "relation" then
			cur_obj.id = _M.relation_id(attrs.id)
		end

		objects[cur_obj.id] = cur_obj
		parent_element = cur_obj

	-- parse tags
	elseif tagname == "tag" then
		if not parent_element then
			print(("Error: %s: <tag> outside of node|way|relation!")
				:format(file_pos_format(file, line, pos)))
			parser:stop()
			return
		end
		if not attrs.k then
			print(("Error: %s: <tag> without k attribute!")
				:format(file_pos_format(file, line, pos)))
			parser:stop()
			return
		end
		if not attrs.v then
			print(("Error: %s: <tag> without v attribute!")
				:format(file_pos_format(file, line, pos)))
			parser:stop()
			return
		end

		if parent_element.tags == nil then
			parent_element.tags = { }
		end
		parent_element.tags[attrs.k] = attrs.v

	-- parse way members
	elseif tagname == "nd" then
		if not parent_element or _M.split_id(parent_element.id) ~= "w" then
			print(("Error: %s: <nd> outside of way!")
				:format(file_pos_format(file, line, pos)))
			parser:stop()
			return
		end
		if not attrs.ref then
			print(("Error: %s: <nd> without ref attribute!")
				:format(file_pos_format(file, line, pos)))
			parser:stop()
			return
		end

		if parent_element.nodes == nil then
			parent_element.nodes = { }
		end
		table.insert(parent_element.nodes, _M.node_id(attrs.ref))

	-- parse relation members
	elseif tagname == "member" then
		if not parent_element or _M.split_id(parent_element.id) ~= "r" then
			print(("Error: %s: <member> outside of relation!")
				:format(file_pos_format(file, line, pos)))
			parser:stop()
			return
		end
		if not attrs.ref then
			print(("Error: %s: <member> without ref attribute!")
				:format(file_pos_format(file, line, pos)))
			parser:stop()
			return
		end
		if not attrs.type then
			print(("Error: %s: <member> without type attribute!")
				:format(file_pos_format(file, line, pos)))
			parser:stop()
			return
		end
		-- note: referencing unknown objects is allowed in relation, so we're not
		-- checking them here.

		local member = { ref = build_id(attrs.type, attrs.ref) }
		if attrs.role then
			member.role = attrs.role
		end

		if parent_element.members == nil then
			parent_element.members = { }
		end
		table.insert(parent_element.members, member)

	-- ignore bounds, but don't warn for unknown tag
	elseif tagname == "bounds" then

	else
		print(("Warning: %s: unknown tag <%s>, ignoring it.")
			:format(file_pos_format(file, line, pos), tagname))
	end
end

local function EndElement(parser, tagname)
	if tagname == "node" or tagname == "way" or tagname == "relation" then
		obj_count[tagname] = obj_count[tagname] + 1
		parent_element = nil
	elseif tagname == "tag" then
		obj_count.tags = obj_count.tags + 1
	elseif tagname == "nd" or tagname == "member" then
		obj_count.refs = obj_count.refs + 1
	elseif tagname == osm then
		in_osm_tag = false
	end
end

function _M.print_statistics()
	print(("Object cache consists of %d nodes, %d ways, %d relations")
		:format(obj_count.node, obj_count.way, obj_count.relation))
	print(("  carrying %d tags, %d object references in total.")
		:format(obj_count.tags, obj_count.refs))
end

--- Parse OSM XML from string
-- @return (res, msg, line, col, pos):
--	* res: non-nil if parsing successful, nil in case of errors
--	* msg: optional error message
--	* line, col, pos: line, column and absolute position where the error happened
function _M.parse(s)
	if not xml_parser then
		xml_parser = lxp.new({
			StartElement = StartElement,
			EndElement = EndElement,
		})
	end
	return xml_parser:parse(s)
end

--- Load objects from OSM XML file
-- @return see return values from parse()
function _M.load_file(filename)
	local f, msg = io.open(filename, "r")

	if not f then
		return nil, msg, 0, 0, 0
	end

	-- read chunks of 1 KiB and feed them to the parser
	local loop = 0
	while true do
		local s = f:read(1024)
		if s == nil then         -- eof
			break
		end

		loop = loop + 1
		if loop % 1024 == 0 then
			print(("Read %d MiB" ):format(loop / 1024))
		end

		file = filename          -- for the error output
		local res, msg, line, col, pos = _M.parse(s)
		file = "input"           -- in case parse() is afterwards called directly

		if res == nil then
			return res, msg, line, pol, pos
		end
	end

	_M.print_statistics()

	return true
end

--- Delete entries from the object cache
-- @param ids array of IDs or single ID, prefixed with object type (n|w|r). See
--  node_id(), way_id(), relation_id().
function _M.forget(ids)
	utils.map(ids, function (_,v) objects[v] = nil end)
end

--- Empty the object cache
function _M.forget_all()
	objects = {}
end

-- helper for http -> parse
local function do_fetch(url)
	print(url)

	local d, c, h = http.request(url)
	print(("HTTP %d, %d bytes"):format(c, #d))

	if c == 200 and #d > 0 then
		local res, msg, line, pol, pos = _M.parse(d)
		if res == nil then
			print("XML error:", res, msg, line, pol, pos)
		else
			-- close the parser, otherwise it complains about junk after the </osm> tag
			xml_parser:close()
			xml_parser = nil
		end
	else
		print(("API returned HTTP %d: %s"):format(c, d))
		return c, h
	end

	return true
end

--- Fetch objects from the API.
-- @param ids ID or array of IDs, prefixed with object type (n|w|r), see
-- node_id(), way_id(), relation_id().
-- @return true in case of success, http error code and response headers in case
-- of failure
function _M.fetch(objs)
	local url
	local nodes, ways, relations = {}, {}, {}
	local c, h

	if type(objs) ~= "table" then
		return _M.fetch({ objs })

	else
		moses.each(objs, function (_,v)
			local type_part, id_part = _M.split_id(v)
			if type_part == "n" then
				table.insert(nodes, id_part)
			elseif type_part == "w" then
				table.insert(ways, id_part)
			elseif type_part == "r" then
				table.insert(relations, id_part)
			end
		end)

		local do_fetch_url_helper = function(objname, ids)
			local list = moses.reduce(ids, function (m,v) return m .. "," .. v end)
			return do_fetch(("%s/0.6/%s?%s=%s"):format(APIURL, objname, objname, list))
		end

		if #nodes > 0 then
			c, h = do_fetch_url_helper("nodes", nodes)
			if c ~= true then
				return c, h
			end
		end
		if #ways > 0 then
			c, h = do_fetch_url_helper("ways", ways)
			if c ~= true then
				return c, h
			end
		end
		if #relations > 0 then
			c, h = do_fetch_url_helper("relations", relations)
			if c ~= true then
				return c, h
			end
		end
	end
end


--- Fetch a single object and all its referenced members (non-recursively).
-- @param ids ID or array of IDs, prefixed with object type (n|w|r), see
-- node_id(), way_id(), relation_id().
-- @return true in case of success, HTTP error code and response headers in case
-- of failure
function _M.fetch_full(obj)
	local type_part, id_part = _M.split_id(obj)

	if type_part == "n" then
		return _M.fetch({ obj })
	elseif type_part == "w" then
		return do_fetch(("%s/0.6/way/%d/null"):format(APIURL, tonumber(id_part)))
	elseif type_part == "r" then
		return do_fetch(("%s/0.6/relation/%d/full"):format(APIURL,
			tonumber(id_part)))
	end
end

--- Fetch objects that are referenced as members but not loaded yet.
-- Resolving is not done recursively. If relations in the object cache refer to
-- relations which are not loaded yet, these relations are loadedi by this
-- function, but their members are not. This can be done by calling resolve()
-- again with the respective object IDs.
--
-- @param ids (boolean, string or array) object IDs whose members should be
--   resolved. If one of those objects is already in the cache, it is not
--   fetched again.
--   If this parameter is true, all current objects in the objects cache are
--   resolved. Use with care! This could lead to very big amounts of data being
--   downloaded!
--   If unknown object IDs are specified, they are silently ignored.
-- @return true in case of success, HTTP error code and response headers in case
--   of HTTP failure.
function _M.resolve(resolve_ids)
	if type(resolve_ids) ~= "table" then
		-- called with a single object id
		return _M.resolve({ resolve_ids })

	else
		-- otherwise, called with array of object ids
		local fetch_list = {}
		local probably_add_to_fetch_list = function(_, member_id)
			if objects[member_id] == nil then
				table.insert(fetch_list, member_id)
			end
		end

		-- iterate over members
		moses.each(resolve_ids, function (_, object_id)
			if not objects[object_id] then
				return
			end

			local obj_type = _M.split_id(object_id)

			if obj_type == "w" then
				-- iterate over way nodes
				moses.each(objects[object_id].nodes, probably_add_to_fetch_list)

			elseif obj_type == "r" then
				-- iterate over relation members
				moses.each(objects[object_id].members, function (_, member)
					probably_add_to_fetch_list(_, member.ref)
				end)
			end
		end)

		return _M.fetch(fetch_list)
	end
end

--- Return the object cache
function _M.objects() return objects end

return _M
