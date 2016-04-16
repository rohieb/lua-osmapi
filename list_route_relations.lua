local o = require("osmapi")
local m = require("moses")

o.load_file("braunschweig.osm")
o.print_statistics()

m.each(o.objects(), function (_,v)
	if o.split_id(v.id) == 'r' and v.tags and v.tags.type == "route_master" then
		print(v.id, "route_master", v.tags.name or v.tags.ref or "<unnamed>")
	end
end)
