local lxp = require ("lxp")
local moses = require ("moses")
local utils = require("./utils")

local http = require("socket.http")
http.TIMEOUT = 3
http.USERAGENT = "lua-osmapi/0.0"

local APIURL = "http://api.openstreetmap.org/api"

local objects = {}

local xml_parser = nil
local file = "input"
local parent_element = nil
local in_osm_tag = false

local function file_pos_format(file, line, pos)
	return ("%s:%d:%d"):format(file, line, pos)
end

--- Build node ID(s) for index access in objects()
local function node_id(ids) return utils.prefix_id("n", ids) end
--- Build way ID(s) for index access in objects()
local function way_id(ids) return utils.prefix_id("w", ids) end
--- Build relation ID(s) for index access in objects()
local function relation_id(ids) return utils.prefix_id("r", ids) end

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

		local cur_obj = { id = attrs.id }

		-- nodes
		if tagname == "node" then
			if not attrs.lat or not attrs.lon then
				print(("Error: %s: <node> without lat/lon attribute!")
					:format(file_pos_format(file, line, pos)))
				parser:stop()
				return
			end

			cur_obj.type = "node"
			cur_obj.lat = attrs.lat
			cur_obj.lon = attrs.lon
			objects["n" .. attrs.id] = cur_obj
		end

		-- ways
		if tagname == "way" then
			cur_obj.type = "way"
			objects["w" .. attrs.id] = cur_obj
		end

		-- relations
		if tagname == "relation" then
			cur_obj.type = "relation"
			objects["r"..attrs.id] = cur_obj
		end

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
		if not parent_element or parent_element.type ~= "way" then
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
		table.insert(parent_element.nodes, attrs.ref)

	-- parse relation members
	elseif tagname == "member" then
		if not parent_element or parent_element.type ~= "relation" then
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

		member = { type = attrs.type, ref = attrs.ref }
		if attrs.role then
			member.role = attrs.role
		end

		if parent_element.members == nil then
			parent_element.members = { }
		end
		table.insert(parent_element.members, member)

	else
		print(("Warning: %s: unknown tag <%s>, ignoring it.")
			:format(file_pos_format(file, line, pos), tagname))
	end
end

local function EndElement(parser, tagname)
	if tagname == "node" or tagname == "way" or tagname == "relation" then
		parent_element = nil
	elseif tagname == osm then
		in_osm_tag = false
	end
end

--- Parse OSM XML from string
-- @return (res, msg, line, col, pos):
--	* res: non-nil if parsing successful, nil in case of errors
--	* msg: optional error message
--	* line, col, pos: line, column and absolute position where the error happened
local function parse(s)
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
local function load_file(filename)
	local f, msg = io.open(filename, "r")

	if not f then
		return nil, msg, 0, 0, 0
	end

	-- read chunks of 1 KiB and feed them to the parser
	while true do
		local s = f:read(1024)
		if s == nil then         -- eof
			break
		end

		file = filename          -- for the error output
		local res, msg, line, col, pos = parse(s)
		file = "input"           -- in case parse() is afterwards called directly

		if res == nil then
			return res, msg, line, pol, pos
		end
	end

	return true
end

--- Delete entries from the object cache
-- @param ids array of IDs or single ID, prefixed with object type (n|w|r). See
--  node_id(), way_id(), relation_id().
local function forget(ids)
	utils.map(ids, function (_,v) objects[v] = nil end)
end

--- Empty the object cache
local function forget_all()
	objects = {}
end

-- helper for http -> parse
local function do_fetch(url)
	print(url)

	local d, c, h = http.request(url)
	print(("HTTP %d, %d bytes"):format(c, #d))

	if c == 200 and #d > 0 then
		local res, msg, line, pol, pos = parse(d)
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

--- Fetch objects from the API. In case of ways and relations, also fetch all
-- referenced members.
-- @param ids ID or array of IDs, prefixed with object type (n|w|r), see
-- node_id(), way_id(), relation_id().
-- @return true in case of success, http error code and response headers in case
-- of failure
local function fetch(objs)
	local url
	local nodes, ways, relations = {}, {}, {}
	local c, h

	if type(objs) ~= "table" then
		return fetch({ objs })

	else
		moses.each(objs, function (_,v)
			local type_part = string.sub(v, 1, 1)
			local id_part   = tonumber(string.sub(v, 2))
			if type_part == "n" then
				table.insert(nodes, id_part)
			elseif type_part == "w" then
				table.insert(ways, id_part)
			elseif type_part == "r" then
				table.insert(relations, id_part)
			end
		end)

		if #nodes > 0 then
			local list = moses.reduce(nodes, function (m,v) return m .. "," .. v end)
			c, h = do_fetch(("%s/0.6/nodes?nodes=%s"):format(APIURL, list))
			if c ~= true then
				return c, h
			end
		end

		moses.each(ways, function (_,w)
			c, h = do_fetch(("%s/0.6/way/%d/full"):format(APIURL, tonumber(w)))
			if c ~= true then
				return c, h
			end
		end)

		moses.each(relations, function (_,r)
			c, h = do_fetch(("%s/0.6/relation/%d/full"):format(APIURL, tonumber(r)))
			if c ~= true then
				return c, h
			end
		end)
	end
end

-- build the module table
osmapi = {
	parse = parse,
	load_file = load_file,
	fetch = fetch,

	forget = forget,
	forget_all = forget_all,

	node_id = node_id,
	way_id = way_id,
	relation_id = relation_id,

	objects = function () return objects end,
}

return osmapi
