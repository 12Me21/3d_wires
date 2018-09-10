local wire_radius = 2/16
local diode_radius = 4/16

local function check_bit(x, bit)
	return math.floor(x / 2^bit) % 2 == 1
	-- return (x >> bit & 1) == 1
end

local function rotate_rule(rule, axis, rotation)
	for i = 1, rotation do
		rule.x, rule.z = rule.z, -rule.x
	end
	
	-- Y+ (no change)
	if axis == 0 then 
	-- Z+
	elseif axis == 1 then
		rule.y, rule.z = -rule.z, rule.y
	-- z-
	elseif axis == 2 then
		rule.y, rule.z = rule.z, -rule.y
	-- X+
	elseif axis == 3 then 
		rule.y, rule.x = -rule.x, rule.y
	-- x-
	elseif axis == 4 then
		rule.y, rule.x = rule.x, -rule.y
	-- y-
	elseif axis == 5 then
		-- Note: I checked, and the game rotates the node 180 degrees around the Z axis here.
		rule.y, rule.x = -rule.y, -rule.x
	end
	return rule
end

-- Generates a function that outputs the rules, rotated to match the node
local function make_rule_rotator(rules)
	return function(node)
		local rotation = node.param2 % 4
		local axis = (node.param2 - rotation) / 4
		local new_rules = {}
		for i, rule in ipairs(rules) do
			new_rules[i] = rotate_rule(table.copy(rule),axis,rotation)
		end
		return new_rules
	end
end

local gates = {
	["and_gate"]     = {name = "And Gate"             , operation = function(a,b) return a and b end     , inputs = 2},
	["and_not_gate"] = {name = "Comparator"           , operation = function(a,b) return a and not b end , inputs = 2}, -- A > B
	["xor_gate"]     = {name = "Not Equal (Xor) Gate" , operation = function(a,b) return a ~= b end      , inputs = 2}, -- A != B
	["or_gate"]      = {name = "Or Gate"              , operation = function(a,b) return a or b end      , inputs = 2},
	["nor_gate"]     = {name = "Nor Gate"             , operation = function(a,b) return not(a or b) end , inputs = 2},
	["nxor_gate"]    = {name = "Equal (Xnor) Gate"    , operation = function(a,b) return a == b end      , inputs = 2}, -- A == B
	["or_not_gate"]  = {name = "Inverted Comparator"  , operation = function(a,b) return a or not b end  , inputs = 2}, -- A >= B
	["nand_gate"]    = {name = "Nand Gate"            , operation = function(a,b) return not(a and b) end, inputs = 2},
	
	["diode"]        = {name = "Diode"                , operation = function(a) return a end             , inputs = 1},
	["not_gate"]     = {name = "Not Gate"             , operation = function(a) return not a end         , inputs = 1},
}

local gate_output_rules = make_rule_rotator({
	{x=0, y=-1, z=0},
})

local gate_input_rules = {
	[1] = make_rule_rotator({
		{x=0, y=1, z=0},
	}),
	[2] = make_rule_rotator({
		{x=-1, y=0, z=0, name="1"},
		{x= 1, y=0, z=0, name="2"},
	}),
}

local function make_gate_updater(gate_function, basename, inputs)
	if inputs == 1 then
		return function(pos, node, link, newstate)
			if mesecon.do_overheat(pos) then
				minetest.remove_node(pos)
				mesecon.receptor_off(pos, gate_output_rules(node))
				local def = minetest.registered_nodes[node.name]
				minetest.add_item(pos, def.drop)
			else
				local name = basename.."_"..(newstate == "on" and "1" or "0")
				if gate_function(newstate == "on") then
					minetest.swap_node(pos, {name = name.."_on", param2 = node.param2})
					mesecon.receptor_on(pos, gate_output_rules(node))
				else
					minetest.swap_node(pos, {name = name.."_off", param2 = node.param2})
					mesecon.receptor_off(pos, gate_output_rules(node))
				end
			end
		end
	else
		return function(pos, node, link, newstate)
			local meta = minetest.get_meta(pos)
			meta:set_int(link.name, newstate == "on" and 1 or 0)
			if mesecon.do_overheat(pos) then
				minetest.remove_node(pos)
				mesecon.receptor_off(pos, gate_output_rules(node))
				local def = minetest.registered_nodes[node.name]
				minetest.add_item(pos, def.drop)			
			else
				local a = meta:get_int("1")
				local b = meta:get_int("2")
				local name = basename.."_"..(a + b*2)
				if gate_function(a == 1, b == 1) then
					minetest.swap_node(pos, {name = name.."_on", param2 = node.param2})
					mesecon.receptor_on(pos, gate_output_rules(node))			
				else
					minetest.swap_node(pos, {name = name.."_off", param2 = node.param2})
					mesecon.receptor_off(pos, gate_output_rules(node))
				end
			end
		end
	end
end

local gate_side_texture_off = "mesecons_wire_off.png^3dwires_gate_center.png^(mesecons_wire_off.png^[mask:3dwires_wire_end_mask.png)"

local gate_nodeboxes = {
	[1] = {
		type = "fixed",
		fixed = {
			{-diode_radius, -diode_radius, -diode_radius, diode_radius, diode_radius, diode_radius},
			{-wire_radius, -0.5, -wire_radius, wire_radius, 0.5, wire_radius},
		}
	},
	[2] = {
		type = "fixed",
		fixed = {
			{-diode_radius, -diode_radius, -diode_radius, diode_radius, diode_radius, diode_radius},
			{-0.5, -wire_radius, -wire_radius, 0.5, wire_radius, wire_radius},
			{-wire_radius, -0.5, -wire_radius, wire_radius, 0, wire_radius},
		}
	},
}

local function make_wire_side_texture(state, side)
	return "^(mesecons_wire_"..state..".png^[mask:3dwires_wire_"..side.."_mask.png)"
end

local function make_gate_tiles(filename, inputs, state, i)
	if inputs==1 then
		local input_state = check_bit(i, 0) and "on" or "off"
		return {
			--top
			"3dwires_gate_center.png"..
			make_wire_side_texture(input_state,"end"),
			--bottom
			"3dwires_gate_center.png^3dwires_diode_paint_bottom.png"..
			make_wire_side_texture(state,"end"),
			--sides
			"3dwires_gate_center.png^3dwires_diode_paint_side.png^3dwires_"..filename.."_symbol.png"..
			make_wire_side_texture(state,"bottom")..
			make_wire_side_texture(input_state,"top"),
		}
	else
		local a_state = check_bit(i, 0) and "on" or "off"
		local b_state = check_bit(i, 1) and "on" or "off"
		return {
			--top
			"3dwires_gate_center.png^3dwires_"..filename.."_symbol.png"..
			make_wire_side_texture(a_state,"left")..
			make_wire_side_texture(b_state,"right"),
			--bottom
			"3dwires_gate_center.png^3dwires_diode_paint_bottom.png"..
			make_wire_side_texture(a_state,"left")..
			make_wire_side_texture(b_state,"right")..
			make_wire_side_texture(state,"end"),
			--right
			"3dwires_gate_center.png^3dwires_diode_paint_side.png"..
			make_wire_side_texture(b_state,"end")..
			make_wire_side_texture(state,"bottom"),
			--left
			"3dwires_gate_center.png^3dwires_diode_paint_side.png"..
			make_wire_side_texture(a_state,"end")..
			make_wire_side_texture(state,"bottom"),
			--back (+)
			"3dwires_gate_center.png^3dwires_diode_paint_side.png^(3dwires_"..filename.."_symbol.png^[transformR180)"..
			make_wire_side_texture(a_state,"right")..
			make_wire_side_texture(b_state,"left")..
			make_wire_side_texture(state,"bottom"),
			--front
			"3dwires_gate_center.png^3dwires_diode_paint_side.png^3dwires_"..filename.."_symbol.png"..
			make_wire_side_texture(a_state,"left")..
			make_wire_side_texture(b_state,"right")..
			make_wire_side_texture(state,"bottom"),
		}
	end
end

-- Sets "not_in_creative_inventory" if variant is not 0
local function make_groups(groups, variant)
	if variant ~= 0 then
		local new_groups = table.copy(groups)
		new_groups.not_in_creative_inventory = 1
		return new_groups
	else
		return groups
	end
end

local gate_groups = {snappy = 2, choppy = 2, oddly_breakable_by_hand = 2, overheat = 1}

-- Register on/off forms of a 2-input gate called <name> using <gate_function>
local function define_gate(name, description, gate_function, inputs)
	local basename = "3d_wires:"..name
	local updater = make_gate_updater(gate_function, basename, inputs)
	for i = 0, 2^inputs-1 do
		mesecon.register_node(basename.."_"..i, {
			description = "3D " .. description,
			paramtype = "light",
			paramtype2 = "facedir",
			on_place = place_rotated.log,
			drawtype = "nodebox",
			on_rotate = wires.on_rotate,
			node_box = gate_nodeboxes[inputs],
			walkable = false,
			climbable = true,
			node_placement_prediction = "",
		},{
			groups = make_groups(gate_groups, i),
			tiles = make_gate_tiles(name, inputs, "off", i),
			mesecons = {receptor = {
				state = "off",
				rules = gate_output_rules,
			}, effector = {
				rules = gate_input_rules[inputs],
				action_change = updater
			}}
		},{
			groups = make_groups(gate_groups, -1),
			tiles = make_gate_tiles(name, inputs, "on", i),
			mesecons = {receptor = {
				state = "on",
				rules = gate_output_rules,
			}, effector = {
				rules = gate_input_rules[inputs],
				action_change = updater
			}}
		})
	end
end

for name, gate in pairs(gates) do
	define_gate(name, gate.name, gate.operation, gate.inputs)
end

-- idea: make gate inputs texture independant from output
-- this means 8 nodes/gate rather than 2...