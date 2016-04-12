local osmapi = require("osmapi")
local inspect = require("inspect")

local s = [[<osm>
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
	</osm>]]
local objs = osmapi.parse(s)
print("")
print("objects = " .. inspect(objs))
