do
	-- Forward declarations
	local
		packet_names,
		noop_handler,
		handlers_by_type,
		pid_label,
		CPacketDescription,
		SPacketDescription,
		dissect_packet

	--local info = function(...) end

	-- Constants for TCP reassembly and packet rejecting
	local ENOUGH    = false
	local NEED_MORE = true
	local ACCEPTED  = true
	local REJECTED  = false

	local p_bnetp = Proto("bnetp","Battle.net Protocol");

	local f_type = ProtoField.uint8("bnetp.type","Header Type",base.HEX, {
		[0x1] = "Game protocol request",
		[0x2] = "FTP protocol request",
		[0x3] = "Chat protocol request",
		[0xF7] = "W3IGP",
		[0xFF] = "BNCS",
	})
	local f_pid  = ProtoField.uint8("bnetp.pid")
	local f_plen = ProtoField.uint16("bnetp.plen","Packet Length",base.DEC)
	local f_data = ProtoField.bytes("bnetp.plen","Unhandled Packet Data")
	
	p_bnetp.fields = {
		-- Header fields
		--     Type
		f_type,
		--     Packet Info
		f_pid,  -- Packet id field
		f_plen, -- Packet length field
		f_data, -- Generic packet data field
	}

	function State()
		return {
			["bnet_node"] = nil,
			["buf"] = nil,
			["pkt"] = nil,
			["used"] = 0,
			["packet"] = {},

			["peek"] = function(o, count)
				o:request(count)
				return o.buf(o.used, count)
			end,
			["read"] = function(o, count)
				local tmp = o:peek(count)
				o.used = o.used + count
				return tmp
			end,
			["request"] = function(o, count)
				local missing = count - (o.buf:len() - o.used)
				info ("request: "
					.. o.buf:len() .. " "
					.. o.used .. " "
					.. count .. " "
					.. missing)
				if (missing > 0) then
					coroutine.yield(NEED_MORE, missing)
				end
			end,
			["tvb"] = function(o) return o.buf(o.used):tvb() end,
			["error"] = function(o, str)
				o.bnet_node:add_expert_info(PI_DEBUG, PI_NOTE, str)
			end,
		}
	end

	function do_dissection(state)
		local handler = handlers_by_type[state:peek(1):uint()]
		if handler then
			state.bnet_node:add(f_type, state:read(1))
			handler(state)
			return ENOUGH, ACCEPTED
		else
			-- If no handler is found the packet is rejected.
			return ENOUGH, REJECTED
		end
	end

	function p_bnetp.dissector(buf,pkt,root)
		if pkt.columns.protocol then
			pkt.columns.protocol:set("BNETP")
		end

		if pkt.columns.info then
			pkt.columns.info:clear()
		end

		if root then
			local state = State()
			local available = buf:len()

			state.buf = buf
			state.pkt = pkt
			pkt.desegment_len = 0

			info ("dissector: start to process pdus")

			while state.used < available do
				state.bnet_node = root:add(p_bnetp, buf(state.used))

				local thread = coroutine.create(do_dissection)
				local r, need_more, missing = coroutine.resume(thread, state)
				if (r and (need_more == NEED_MORE)) then
					if missing then
						pkt.desegment_len = missing
					else
						pkt.desegment_len = DESEGMENT_ONE_MORE_SEGMENT
					end
					pkt.desegment_offset = 0
					info ("dissector: requesting data -" 
							.. " r: " .. tostring(r)
							.. " need_more: " .. tostring(need_more)
							.. " missing: " .. tostring(missing)
							.. " deseg_len: " .. tostring(pkt.desegment_len))
					return
				elseif r and (need_more==ENOUGH) and (missing==REJECTED) then
					-- Packet was rejected. Make the loop end.
					available = state.used
				elseif not r then
					error(need_more)
				end
			end
			if state.used > available then
				error("Used more data than available.")
			end
			info ("dissector: finished processing pdus")
			return state.used
		end
	end

	local udp_encap_table = DissectorTable.get("udp.port")
	local tcp_encap_table = DissectorTable.get("tcp.port")
	--udp_encap_table:add(6112,p_bnetp)
	tcp_encap_table:add(6112,p_bnetp)

	-- Protocol stuff

	noop_handler = function (state) return end

	pid_label = function (pid, name)
		return string.format("Packet ID: %s (0x%02x)", name, pid)
	end

	handlers_by_type = {
		[0x1] = noop_handler,
		[0x2] = noop_handler,
		[0x3] = noop_handler,
		[0xF7] = function (state)
			state.bnet_node:add(f_pid, state:read(1))
			local len = state:peek(2):le_uint()
			state.bnet_node:add_le(f_plen, state:read(2))
			state.bnet_node:add(f_data, state:read(len - 4))
		end,
		[0xFF] = function (state) 
			local pid = state:peek(1):uint()
			local type_pid = ((0xFF * 256) + pid)
			local pidnode = state.bnet_node:add(f_pid, state:read(1))
			pidnode:set_text(pid_label(pid,packet_names[type_pid]))
			-- The size found in the packet includes headers, so consumed bytes
			-- are substracted when requesting more data.
			local len = state:peek(2):le_uint() -2
			-- Record used bytes before dissecting.
			local start = state.used
			-- Request at least len extra bytes at once.
			state:request(len)

			state.bnet_node:add_le(f_plen, state:read(2))

			local pdesc
			if state.pkt.src_port == 6112 then
				-- process server packet
				pdesc = SPacketDescription[type_pid]
			else
				-- process client packet
				pdesc = CPacketDescription[type_pid]
			end

			if pdesc then
				dissect_packet(state, pdesc)
			else
				state:error("Unssuported packet: " .. packet_names[type_pid])
			end

			-- Check if any data remains unhandled.
			local remaining = len - (state.used - start)
			if remaining > 0 then
				state.bnet_node:add(f_data, state:read(remaining))
			end
		end,
	}

	-- Packet dissector
	function dissect_packet(state, pdesc)
		for k,v in pairs(pdesc) do
			if v.key and v.value then
				state.packet[v.key] = v:value(state)
			end
			if not v.dissect then
				local size = v:size(state)
				if v.big_endian then
					state.bnet_node:add(v.pf, state:read(size))
				else
					state.bnet_node:add_le(v.pf, state:read(size))
				end
			else
				v:dissect(state)
			end
		end
	end

	-- Supported data types
	local typemap = {
		["uint64"] = {
			["size"] = function(...) return 8 end,
		},
		["uint32"] = {
			size = function(...) return 4 end,
			value = function (self, state)
				local val = state:peek(self.size())
				return val:le_uint()
			end,
		},
		["uint16"] = {
			["size"] = function(...) return 2 end,
		},
		["uint8"]  = {
			["size"] = function(...) return 1 end,
		},
		["int64"]  = {
			["size"] = function(...) return 8 end,
		},
		["int32"]  = {
			["size"] = function(...) return 4 end,
		},
		["int16"]  = {
			["size"] = function(...) return 2 end,
		},
		["int8"]   = {
			["size"] = function(...) return 1 end,
		},
		["ipv4"]   = {
			["size"] = function(...) return 4 end,
			big_endian = true,
		},
		["stringz"] = {
			["alias"] = "string",
			["size"] = function(self, state)
				if (self.length == nil) or (self.length < 0) then
					local eos = self.eos or 0 -- end of string
					local buf = state:tvb()
					local n = 0
					while (buf:len() > 0) and (buf(n,1):uint() ~= eos) do
						n = n + 1
					end
					return n + 1
				else
					return self.length
				end
			end,
			["length"] = -1,
			dissect = function(self, state)
				local size = self:size(state)
				local buf = state:read(size):tvb()

				if self.reversed then
					local tmp = ByteArray.new()
					tmp:set_size(size)
					for i=size - 1, 0, -1 do
						tmp:set_index(size - i - 1,
							buf(i, 1):uint())
					end
					buf = tmp:tvb("Reversed String")
				end

				state.bnet_node:add(self.pf, buf())
			end,
		},
		["sockaddr"] = {
			["size"] = function(...) return 16 end,
			["alias"] = "bytes",
		},
		["filetime"] = {
			["size"] = function(...) return 8 end,
			["alias"] = "uint64",
			dissect = function(self, state)
				local size = self.size(state:tvb())
				local node = state.bnet_node:add(self.pf, state:peek(8))
				-- POSIX epoch filetime
				local epoch = 0xd53e8000 + (0x100000000 * 0x019db1de)
				-- Read filetime
				local filetime = state:read(4):le_uint()
					+ (0x100000000 * state:read(4):le_uint())
				-- Convert to POSIX time if possible
				if filetime > epoch then
					-- Append text form of date to the node label.
					node:append_text(os.date(" %c", (filetime - epoch) * 1E-7))
				end
			end,
		},
		["posixtime"] = {
			["size"] = function(...) return 4 end,
			["alias"] = "uint32",
			dissect = function(self, state)
				local node = state.bnet_node:add(self.pf, state:peek(4))
				local unixtime = os.date(" %c", state:read(4):le_uint())
				-- Append text form of date to the node label.
				node:append_text(unixtime)
			end,
		},
		iterator = {
			alias = "bytes",
			dissect = function(self, state)
				local count = state.packet[self.refkey]
				local bn = state.bnet_node
				while count > 0 do
					state.bnet_node = bn:add(self.pf)
					dissect_packet(state, self.repeated)
					count = count - 1
				end
				state.bnet_node = bn
			end,
		},
	}

	-- ProtoField wrapper
	local WProtoField = {}
	setmetatable(WProtoField, {
		__index = function(t,k)
				return function (args, ...)
					local typeinfo = typemap[k]
					local field = (typeinfo and (
						(typeinfo.alias and ProtoField[typeinfo.alias]) or	
						(ProtoField[k])))

					if typeinfo and field then
						--[[ TODO: remove after changing packets syntax ]]
						if type(args) ~= "table" then
							args = {}
							args.label = arg[1]
							args.display = arg[2]
							args.desc = arg[3]
						end
						-----------------
						local tmp = {
							-- TODO: some fields do not expect display
							-- and desc argument
							pf = field("",
								args.label,
								args.display,
								args.desc,
								unpack(args.params or {})),
						}
						-- Remove ProtoField arguments
						args.label = nil
						args.desc = nil
						args.display = nil
						args.params = nil
						-- Copy other fields to the returned value
						for k,v in pairs(args) do
							tmp[k] = v
						end
						-- Grant access to the type methods
						-- through the return value
						for k,v in pairs(typeinfo) do
							if tmp[k] == nil then
								tmp[k] = v
							end
						end
						-- Add the field to the protocol field list
						local n = table.getn(p_bnetp.fields) + 1
						p_bnetp.fields[n] = tmp.pf
						return tmp
					end
					error("unsupported field type: " .. k)
				end
		end,
		__newindex = function (t,k,v)
          error("attempt to update a read-only table", 2)
        end
	})

	%include "constants.lua"

	do
		local uint64 = WProtoField.uint64
		local uint32 = WProtoField.uint32
		local uint16 = WProtoField.uint16
		local uint8 = WProtoField.uint8
		local int64 = WProtoField.int64
		local int32 = WProtoField.int32
		local int16 = WProtoField.int16
		local int8 = WProtoField.int8
		local ipv4 = WProtoField.ipv4
		local stringz = WProtoField.stringz
		local sockaddr = WProtoField.sockaddr
		local filetime = WProtoField.filetime
		local posixtime = WProtoField.posixtime
		local iterator = WProtoField.iterator
		local version = function(arg)
			arg.big_endian = false
			return ipv4(arg)
		end
		local strdw = function(arg)
			arg.reversed = true
			arg.length = 4
			return stringz(arg)
		end

		%include "spackets.lua"
		%include "cpackets.lua"
	end
end