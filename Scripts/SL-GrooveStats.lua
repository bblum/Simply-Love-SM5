-- Returns an actor that can write a request, wait for its response, and then
-- perform some action. This actor will only wait for one response at a time.
-- If we make a new request while we are already waiting on a response, we
-- will ignore the response received from the previous request and wait for the
-- new response. 
--
-- Usage:
-- af[#af+1] = RequestResponseActor(
--     "GetScores", 10, {..}, function(data, args)
--         SCREENMAN:SystemMessage(tostring(data)..tostring(args))
--     end)
--
-- Which can then be triggered by:
--    MESSAGEMAN:Broadcast("GetScores", { data={..} })

-- mame: A name that will trigger the request for this actor.
--       It should generally be unique for each actor of this type.
-- timeout: A positive number in seconds between [1.0, 59.0] inclusive. It must
--          be less than 60 seconds as responses are expected to be cleaned up
--          by the launcher by then.
-- args: A table containing other variables/actors that will be made accesible
--       to the callback function.
-- callback: A function that processes the response. It must take at least two
--           parameters:
--              data: which will be a table consisting of the parsed JSON.
--              args: a table which will contain other variables accessible to
--                    the callback.
function RequestResponseActor(name, timeout, args, callback)
	-- Sanitize the timeout value.
	local timeout = clamp(timeout, 1.0, 59.0)

	local path_prefix = "/Save/GrooveStats/"

	return Def.Actor{
		InitCommand=function(self)
			self.request_id = nil
			self.request_time = nil
		end,
		WaitCommand=function(self)
			-- We're waiting on a response.
			if self.request_id ~= nil then
				local now = GetTimeSinceStart()

				-- Check to see if the response file was written.
				local f = RageFileUtil.CreateRageFile()
				if f:Open(path_prefix.."responses/"..self.request_id..".json", 1) then
					local data = json.decode(f:Read())
					callback(data, args)
					f:Close()
				-- Have we timed out?
				elseif now - self.request_time > timeout then
					self.request_id = nil
					self.request_time = nil
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
				f:Close()
			end
			f:destroy()
		end
	}
end