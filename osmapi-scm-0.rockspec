package = "osmapi"
version = "scm-0"
source = {
	url = "git://github.com/rohieb/lua-osmapi",
	tag = "test/v0.0",
}

description = {
	summary = "OpenStreetMap API encapsulation",
	homepage = "https://github.com/rohieb/lua-osmapi",
	license = "MIT",
}

dependencies = {
	"lua >= 5.1",
	"luasocket",
	"moses",
	"luaexpat",
}

build = {
	type = "builtin",
	modules = {
		osmapi = "lua/osmapi/init.lua",
		["osmapi.utils"] = "lua/osmapi/utils.lua"
	},
}

