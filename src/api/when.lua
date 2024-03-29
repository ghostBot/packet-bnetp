
do
	local template = {
		protofield_type = "none",
	}

	function template:dissect(state)
		for _, v in ipairs(self.tests) do
			if v.condition(self, state) then
				dissect_packet(state, v.block)
				break
			end
		end
	end

	--[[
	--  casewhen
	--
	--  Selects a block of fields from a list when it's associated condition
	--  is true.
	--
	--  Walks though the list of pairs received as argument sequentially evaluating
	--  the first element and if it was true executing the second element of the
	--  pair as a block of fields.
	--
	--  Only one block is executed.
	--
	--  This function actually emulates if (..) .. elseif (..) sequence. Use Cond.always()
	--  as condition if you want to use final else.
	--
	--  Table call: { {condition, block}, ... }
	--    @par condition Function that returns true if the block should be
	--                   used given the current state.
	--    @par block     Block of fields that will be executed when condition
	--                   is true.
	--
	--]]
	function casewhen (...)
#if LUA_VERSION >= 510
		local arg = {...}
#endif
		local tmp = create_proto_field(template, {})
		if (#arg == 1) and arg[1].tests then
			tmp.tests = arg[1].tests
		else
			tmp.tests = {}
			-- XXX: little hack to allow both syntax for calling a function
			--      ( f() and f {} )
			if #arg == 1 and type(arg[1][1])=="table" then arg = arg[1] end
			for k, v in ipairs(arg) do
				local test = make_args_table_with_positional_map(
					{"condition", "block"}, v)
				tmp.tests[k] = test
			end
		end
		return tmp
	end

	--[[
	--  when
	--
	--  Selects a block of fields from two alternatives acording to a condition
	--  function result.
	--
	--  Emulates if(..) then .. else .. sequence
	--
	--  Only one block is executed.
	--
	--  Quick call: ( condition, block, otherwise )
	--  Table call: { condition=..., block=..., otherwise=... }
	--    @par condition Function that returns true if the block should be
	--                   used given the current state.
	--    @par block     Block of fields that will be executed when condition
	--                   is true.
	--    @par otherwise Block of fields used when condition is false.
	--
	--]]
	function when (...)
		local args = make_args_table_with_positional_map(
				{"condition", "block", "otherwise"},
#if LUA_VERSION >= 510
				...
#else
				unpack(arg)
#endif
		)
		if args.params then
			error(package.loaded.debug.traceback())
		end
		local par = { { args.condition, args.block } }
		-- call casewhen, use true function as condition for otherwise block
		if args.otherwise then
			par[2] = { function() return true end, args.otherwise }
		end
		return casewhen (
#if LUA_VERSION >= 520
			table.unpack(par)
#else
			unpack(par)
#endif
		)
	end
end

