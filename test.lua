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
				parent_element = cur_obj
			end
		end

		-- parse tags
		if tagname == "tag" then
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
		end
	end,

	EndElement = function (parser, tagname)
		if tagname == "node" or tagname == "way" or tagname == "relation" then
			parent_element = nil
		end
	end
}

parser = lxp.new(callbacks)
parser:parse([[<osm>
<node id="24423" lat="53.1" lon = "10.4">
<tag k="position" v="estimated"/>
<tag k="fixme" v="hello world" />
<!--<way>-->
</node>
</osm>]])

print(inspect.inspect(NODES))
