local lxp = require ("lxp")

local objects = {
	nodes = {},
	ways = {},
	relations = {},
}

local file = "input"
local parent_element = nil
local in_osm_tag = false

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
			print(("Error: %s %d:%d: <%s> inside of node|way|relation!")
				:format(file, line, pos, tagname))
			parser:stop()
		end
		if not attrs.id then
			print(("Error: %s %d:%d: <%s> without id attribute!")
				:format(file, line, pos, tagname))
			parser:stop()
			return
		end

		local cur_obj = { id = attrs.id }

		-- nodes
		if tagname == "node" then
			if not attrs.lat or not attrs.lon then
				print(("Error: %s %d:%d: <node> without lat/lon attribute!")
					:format(file, line, pos))
				parser:stop()
				return
			end

			cur_obj.type = "node"
			cur_obj.lat = attrs.lat
			cur_obj.lon = attrs.lon
			objects.nodes[attrs.id] = cur_obj
		end

		-- ways
		if tagname == "way" then
			cur_obj.type = "way"
			objects.ways[attrs.id] = cur_obj
		end

		-- relations
		if tagname == "relation" then
			cur_obj.type = "relation"
			objects.relations[attrs.id] = cur_obj
		end

		parent_element = cur_obj

	-- parse tags
	elseif tagname == "tag" then
		if not parent_element then
			print(("Error: %s %d:%d: <tag> outside of node|way|relation!")
				:format(file, line, pos))
			parser:stop()
			return
		end
		if not attrs.k then
			print(("Error: %s %d:%d: <tag> without k attribute!")
				:format(file, line, pos))
			parser:stop()
			return
		end
		if not attrs.v then
			print(("Error: %s %d:%d: <tag> without v attribute!")
				:format(file, line, pos))
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
			print(("Error: %s %d:%d: <nd> outside of way!")
				:format(file, line, pos))
			parser:stop()
			return
		end
		if not attrs.ref then
			print(("Error: %s %d:%d: <nd> without ref attribute!")
				:format(file, line, pos))
			parser:stop()
			return
		end
		if not objects.nodes[attrs.ref] then
			print(("Warning: %s %d:%d: node %d referenced but no data provided!")
				:format(file, line, pos, attrs.ref))
		end

		if parent_element.nodes == nil then
			parent_element.nodes = { }
		end
		table.insert(parent_element.nodes, attrs.ref)

	-- parse relation members
	elseif tagname == "member" then
		if not parent_element or parent_element.type ~= "relation" then
			print(("Error: %s %d:%d: <member> outside of relation!")
				:format(file, line, pos))
			parser:stop()
			return
		end
		if not attrs.ref then
			print(("Error: %s %d:%d: <member> without ref attribute!")
				:format(file, line, pos))
			parser:stop()
			return
		end
		if not attrs.type then
			print(("Error: %s %d:%d: <member> without type attribute!")
				:format(file, line, pos))
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
		print(("Warning: %s %d:%d: unknown tag <%s>, ignoring it.")
			:format(file, line, pos, tagname))
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
-- @return object dictionary
local function parse(s)
	parser = lxp.new({ StartElement = StartElement, EndElement = EndElement })
	parser:parse(s)
	return objects
end

--- Load objects from OSM XML file
-- @return object dictionary
local function load_file(filename)
	local f = io.open(filename, "r")
	s = f:read("*all")
	return parse(s)
end

-- build the module table
osmapi = {
	parse = parse,
	load_file = load_file,
	objects = objects,
}

return osmapi
