local isStudio = game:GetService("RunService"):IsStudio()
local isPrivateServer = game.PrivateServerId ~= '' and game.PrivateServerOwnerId ~= 0
local isReservedServer = game.PrivateServerId ~= '' and game.PrivateServerOwnerId == 0

local serverShare = script.Parent:FindFirstChild("ServerShare")

local prefix = "["..script:GetFullName().." | ServerShare.Runner]:"

if not serverShare then
	error(prefix.." ServerShare is not found.")
end

return function()
	local jobId = (isStudio and 'StudioServer' or game.JobId)
	local players = game:GetService('Players')

	local client = serverShare.connect('LINK', 'SERVERNAME', 'CONNECTIONKEY')

	client:setSyncFunction(function(data)
		local action = data.action

		if action == 'kick' then
			local playerTab = {}
			
			for _,child in pairs(players:GetPlayers()) do
				if child.Name ~= child.DisplayName then
					table.insert(playerTab, child.DisplayName.." ("..child.Name..")")
				else
					table.insert(playerTab, child.Name)
				end
			end
			
			for _,child in pairs(players:GetPlayers()) do
				if child.UserId == data.playerId then
					child:Kick(data.reason)
					
					return {
						kicked = true,
						jobId = jobId,
						players = playerTab
					}
				end
			end
			
			return {
				kicked = false
			}
		elseif action == 'getPlayers' then
			local playerTab = {}
			local serverType = 0
			
			for _,child in pairs(players:GetPlayers()) do
				if child.Name ~= child.DisplayName then
					table.insert(playerTab, child.DisplayName.." ("..child.Name..")")
				else
					table.insert(playerTab, child.Name)
				end
			end
			
			if isPrivateServer then
				serverType = 1
			elseif isReservedServer then
				serverType = 2
			end
			
			return {
				players = playerTab,
				jobId = jobId,
				serverType = serverType
			}
		elseif action == 'shutdown' then
			if data.jobId == jobId then
				local playerTab = {}
				
				for _,child in pairs(players:GetPlayers()) do
					if child.Name ~= child.DisplayName then
						table.insert(playerTab, child.DisplayName.." ("..child.Name..")")
					else
						table.insert(playerTab, child.Name)
					end
				end

				task.delay(5, function()
					for _,child in pairs(game:GetService("Players"):GetPlayers()) do
						child:Kick("This server has been shutdowned with reason: "..data.reason)
					end
				end)

				return {
					shutdown = true,
					players = playerTab
				}
			else
				return {
					shutdown = false
				}
			end
		elseif action == 'hint' then
			if data.jobId == jobId or data.jobId == 'all' then
				coroutine.resume(coroutine.create(function()
					local v = Instance.new("Hint", workspace)
					v.Name = game:GetService("HttpService"):GenerateGUID(false)
					v.Text = tostring(data.text) or "Failed to load message."
					game:GetService("Debris"):AddItem(v, data.timeOut)
				end))

				return {
					sended = true,
					jobId = jobId
				}
			else
				return {
					sended = false
				}
			end
		end
	end)

	client:startListen()

	return client
end