local lxp = require ("lxp")

------------------ DEBUGGING --------------
local inspect = require("inspect")
------------------ /DEBUGGING -------------

local NODES = { }
local WAYS = { }
local RELATIONS = { }

local file = "input"
local parent_element = nil
local in_osm_tag = false

callbacks = {
	StartElement = function (parser, tagname, attrs)
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
				NODES[attrs.id] = cur_obj
			end

			-- ways
			if tagname == "way" then
				cur_obj.type = "way"
				WAYS[attrs.id] = cur_obj
			end

			-- relations
			if tagname == "relation" then
				cur_obj.type = "relation"
				RELATIONS[attrs.id] = cur_obj
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
			if not NODES[attrs.ref] then
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
	end,

	EndElement = function (parser, tagname)
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
}

parser = lxp.new(callbacks)
parser:parse([[<osm>
<node id="24423" lat="53.1" lon = "10.4">
	<tag k="position" v="estimated"/>
	<tag k="fixme" v="hello world" />
</node>
<way id="14412">
	<tag k="highway" v="path" />
	<nd ref="24423" />
	<nd ref="24723" />
</way>
<relation id="565">
	<member type="node" role="stop_position" ref="24423" />
	<member type="node" role="platform" ref="14415" />
	<member type="way" ref="14412" />
</relation>
<foobar />
</osm>]])

print("")
print("NODES = " .. inspect(NODES))
print("WAYS = " .. inspect(WAYS))
print("RELATIONS = " .. inspect(RELATIONS))
