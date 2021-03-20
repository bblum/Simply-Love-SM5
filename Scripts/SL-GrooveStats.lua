-- Returns an actor that can write a request, wait for its response, and then
-- perform some action. This actor will only wait for one response at a time.
-- If we make a new request while we are already waiting on a response, we
-- will ignore the response received from the previous request and wait for the
-- new response. 
--
-- Usage:
-- af[#af+1] = RequestResponseActor("GetScores", 10)
--
-- Which can then be triggered by:
--
-- af[#af+1] = Def.Actor{
--   OnCommand=function(self)
--     MESSAGEMAN:Broadcast("GetScores", {
--       data={..},
--       args={..},
--       callback=function(data, args)
--         SCREENMAN:SystemMessage(tostring(data)..tostring(args))
--       end
--     })
--   end
--  }

-- The params in the MESSAGEMAN:Broadcast() call must have the following:
-- data: A table that can be converted to JSON that will contains the
--       information for the request
-- args: Arguments that will be made accesible to the callback function. This
--       can of any type as long as the callback knows what to do with it.
-- callback: A function that processes the response. It must take at least two
--           parameters:
--              data: The JSON response which has been converted back to a lua table
--              args: The same args as listed above above.

-- name: A name that will trigger the request for this actor.
--       It should generally be unique for each actor of this type.
-- timeout: A positive number in seconds between [1.0, 59.0] inclusive. It must
--          be less than 60 seconds as responses are expected to be cleaned up
--          by the launcher by then.
function RequestResponseActor(name, timeout)
	-- If on startup we notice that the theme is not using the launcher then this
	-- function will have no effect. Otherwise this might spawn too many files that
	-- may not get cleaned up.
	-- NOTE(teejusb): We can't use "IsUsingLauncher" as that's defined in SL-Helpers.lua
	-- which gets loaded after SL-Groovestats.lua
	if GAMESTATE:Env()["GsLauncher"] == nil or GAMESTATE:Env()["GsLauncher"] == false then
		return nil
	end

	-- Sanitize the timeout value.
	local timeout = clamp(timeout, 1.0, 59.0)

	local path_prefix = "/Save/GrooveStats/"

	return Def.Actor{
		InitCommand=function(self)
			self.request_id = nil
			self.request_time = nil
			self.args = nil
			self.callback = nil
		end,
		WaitCommand=function(self)
			local Reset = function(self)
				self.request_id = nil
				self.request_time = nil
				self.args = nil
				self.callback = nil
			end
			-- We're waiting on a response.
			if self.request_id ~= nil then
				local now = GetTimeSinceStart()

				local f = RageFileUtil.CreateRageFile()
				-- Check to see if the response file was written.
				if f:Open(path_prefix.."responses/"..self.request_id..".json", 1) then
					local data = json.decode(f:Read())
					self.callback(data, self.args)
					f:Close()
					Reset(self)
				-- Have we timed out?
				elseif now - self.request_time > timeout then
					Reset(self)
				end
				f:destroy()
			end

			-- If the id wasn't reset, then we're still waiting. Loop again.
			if self.request_id ~= nil then
				self:sleep(0.5):queuecommand('Wait')
			end
		end,
		[name .. "MessageCommand"]=function(self, params) 
			local id = CRYPTMAN:GenerateRandomUUID()

			local f = RageFileUtil:CreateRageFile()
			if f:Open(path_prefix .. "requests/".. id .. ".json", 2) then
				f:Write(json.encode(params.data))
				self.request_id = id
				self.request_time = GetTimeSinceStart()
				self.args = params.args
				self.callback = params.callback
				f:Close()
			end
			f:destroy()

			if self.request_id ~= nil then
				self:queuecommand('Wait')
			end
		end
	}
end