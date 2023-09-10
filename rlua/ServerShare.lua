-- Type: ModuleScript

local module = {}
local httpService = game:GetService('HttpService')
local servers = {}

-- Settings
local debug = true -- always use the debug server
local autoReconnect = true -- reconnect when error
local showServerNames = false -- show server name

local checkDataWait = 5
--

local oldPrint = print;
local print = function(...)
	if debug == true then
        oldPrint('ServerShare:', ...)
    end
end

module.__index = module

function module.isVaildUrl(url:string)
	if url:match('https://.+/server') then
		return true
	else
		return false
	end
end

function module.connect(url:string, serverName:string, connectionKey:string)
	assert(type(url) == 'string' and module.isVaildUrl(url), 'Invalid URL')
	assert(type(serverName) == 'string', 'Invalid ServerName')

	if servers[serverName] then
		return servers[serverName]
	end

	local self = setmetatable({},module)

	self.info = function(...)
		print((showServerNames and serverName or 'Client') .. ':',...)
	end

	self.serverName = serverName
	self.url = url
	self.connectionKey = connectionKey

	self.isListening = false

	self.onNewData = Instance.new('BindableEvent')
	self.onNewSystemData = Instance.new('BindableEvent')
	self.onDisconnect = Instance.new('BindableEvent')
	self.onNewSyncData = Instance.new('BindableEvent')
	self.onConnected = Instance.new('BindableEvent')

	self.onNewSystemData.Event:Connect(function(data)
		if data.action == 'checkClient' then
			self:sendData({
				checked = 1,
				systemData = true,
			})
		end
	end)

	self.onNewSyncData.Event:Connect(function(data)
		if self.syncFunction then
			local funcData = self.syncFunction(data)

			assert(type(funcData) == 'table','syncFunction should return the table')

			funcData.syncData = true
			funcData.receiveId = data.receiveId

			self:sendData(funcData)
		else
			self:sendData(data)
		end
	end)

	self.info('Client created')

	servers[serverName] = self

	return self
end
function module:setSyncFunction(func)
	if func == nil then
		self.syncFunction = nil

		return
	end	

	if type(func) == 'function' then
		self.syncFunction = func
	else
		error('Invalid SyncFunction')
	end
end
function module:startListen()
	assert(not self.isListening, 'Already listening')

	self.closed = false

	self:_connect()
	task.spawn(function()
		self:_dataCheck()
	end)

	self.isListening = true

	self.onConnected:Fire(true)

	self.info('Client started')
end
function module:disconnect(reason,notifyServer)
	assert(self.isListening, 'Not Listening')
	assert(not self.closed, 'Already closed')

	if type(reason) ~= 'string' then
		reason = 'Client disconnected'
	end
	if type(notifyServer) ~= 'boolean' then
		notifyServer = true
	end

	self.closed = true

	self.onDisconnect:Fire(reason)
	if notifyServer then
		self:sendData({
			_action = 'disconnect',
			reason = reason,
		})
	end

	self.authKey = nil
	self.clientId = nil
	self.isListening = false

	self.info('Client disconnected')
end
function module:reconnect(disconnectReason:string)
	self:disconnect(disconnectReason)

	self:_connect()
	task.spawn(function()
		self:_dataCheck()
	end)

	self.isListening = true
	self.closed = false

	self.onConnected:Fire(true)

	self.info('Client reconnected')
end
function module:sendData(data,waitForListen)
	if waitForListen then
		if not self.isListening then
			local function waitForEvent()
				local success = self.onConnected.Event:Wait()

				if not success then
					return waitForEvent()
				end
			end

			waitForEvent()
		end
	else
		assert(self.isListening,'Not Listening')
	end
	assert(self.clientId,'ClientId is missing')
	assert(type(data) == 'table','Invalid Data')

	local data = httpService:JSONEncode({
		['serverName'] = self.serverName,
		['authKey'] = self.authKey,
		['action'] = data._action or 'setData',
		['clientId'] = self.clientId,
		['data'] = data,
	})
	local result = httpService:RequestAsync({
		['Url'] = self.url,
		['Method'] = 'POST',
		['Body'] = data
	})

	return result.Success,result.Body
end

function module:sendSyncData(data,waitForListen)
	assert(type(data) == 'table','Invalid data')

	data.userSyncData = true

	return self:sendData(data,waitForListen)
end

function module:_dataCheck()
	while task.wait(checkDataWait) do
		if self.closed then
			break
		end

		local data = httpService:JSONEncode({
			['serverName'] = self.serverName,
			['authKey'] = self.authKey,
			['action'] = 'getData',
			['clientId'] = self.clientId,
		})
		local result = httpService:RequestAsync({
			['Url'] = self.url,
			['Method'] = 'POST',
			['Body'] = data
		})

		if result.StatusCode == 400 then
			if result.Body == 'Only systemData allowed' then
				self.info('Server only accepts systemData')

				continue
			else
				self.info('Server error: ' .. result.Body)

				if autoReconnect then
					self:reconnect('Server error')
				end

				break
			end
		elseif result.StatusCode == 403 then
			local text = 'Server Disconnected: ' .. result.Body

			self.info(text)

			if autoReconnect then
				self:reconnect(text)
			end

			break
		end

		if result.Body ~= 'No data' then
			local success,d = pcall(httpService.JSONDecode,httpService,result.Body)

			if not success then
				self.info('Failed to check data:',d)

				continue
			end

			if d.systemData then
				self.onNewSystemData:Fire(d)
			elseif d.syncData then
				self.onNewSyncData:Fire(d)
			else
				self.onNewData:Fire(d)
			end
		end
	end
end
function module:_connect()
	local data = httpService:JSONEncode({
		['serverName'] = self.serverName,
		['connectKey'] = self.connectionKey,
		['action'] = 'connect',
	})
	local result = httpService:RequestAsync({
		['Url'] = self.url,
		['Method'] = 'POST',
		['Body'] = data
	})

	if result.Success then
		local r = httpService:JSONDecode(result.Body)

		self.clientId = r.clientId
		self.authKey = r.authKey

		return true
	else
		self.onConnected:Fire(false)

		if autoReconnect then
			self.info('Failed to connect')

			task.wait(5)

			return self:_connect()
		end
	end
end

return module