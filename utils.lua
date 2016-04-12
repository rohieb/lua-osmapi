local utils = {}

--- Call fn(k,v) for every k,v in values and replace values[k] with the return
-- value from fn(k,v). If values is scalar, simply return fn(0, values).
function utils.map(values, fn)
	if type(values) == "table" then
		local res = {}
		for k,v in ipairs(values) do
			res[k] = fn(k,v)
		end
		return res
	else
		return fn(0, values)
	end
end

--- Build prefixed IDs for each numerical ID
function utils.prefix_id(prefix_char, ids)
	return utils.map(ids, function(k,v) return (prefix_char .. tonumber(v)) end)
end

return utils
