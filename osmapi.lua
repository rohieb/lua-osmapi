local lxp = require ("lxp")
local utils = require("./utils")

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
		if not objects["n" .. attrs.ref] then
			print(("Warning: %s: node %d referenced but no data provided!")
				:format(file_pos_format(file, line, pos), attrs.ref))
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
		if not parent_element.tags then
			print(("Warning: %s %d has no tags.")
				:format(parent_element.type, parent_element.id))
		end

		if parent_element.type == "way" and not parent_element.nodes then
			print(("Warning: way %d has no nodes."):format(parent_element.id))
		end

		if parent_element.type == "relation" and not parent_element.members then
			print(("Warning: relation %d has no members.")
				:format(parent_element.id))
		end

		parent_element = nil
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
	file = filename
	local f = io.open(filename, "r")
	s = f:read("*all")
	local res, msg, line, col, pos = parse(s)
	file = "input"
	return res, msg, line, pol, pos
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

--- Fetch one or more objects from the API
-- @param ids array of IDs or single ID, prefixed with object type (n|w|r)


-- build the module table
osmapi = {
	parse = parse,
	load_file = load_file,
	forget = forget,
	forget_all = forget_all,

	node_id = node_id,
	way_id = way_id,
	relation_id = relation_id,

	objects = function () return objects end,
}

return osmapi
