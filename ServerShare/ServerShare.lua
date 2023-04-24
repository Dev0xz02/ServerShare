local json = require('json')
local timer = require('timer')
local corohttp = require('coro-http')

local functions = {}
local servers = {}

function functions.count(table)
    local count = 0

    for _ in pairs(table) do
        count = count + 1
    end

    return count
end

function functions.deepCopy(table)
    local new = {}

    for index, value in pairs(table) do
        if type(index) == 'table' then
            index = functions.deepCopy(index)
        end
        if type(value) == 'table' then
            value = functions.deepCopy(value)
        end

        new[index] = value
    end

    return new
end

function functions.generateAuthkey()
    local str = ''

    for i = 1, math.random(2, 100) * 2 do
        local final
        local numb = math.random(1, 2)

        if numb == 1 then
            final = math.random(1, 9)                 -- 1, 9
        elseif numb == 2 then
            final = string.char(math.random(97, 122)) -- A, Z
        end

        str = str .. final
    end

    return str
end

function functions.runAll(funcs, ...)
    local args = { ... }

    for func in pairs(funcs) do
        coroutine.wrap(function()
            func(unpack(args))
        end)()
    end
end

local defaultOptions = {
    clientAllowSend = true,
    clientAllowGet = true,
}

function functions.createServer(serverName, connectionKey, options)
    if servers[serverName] then
        error('already exist')
    end

    if options then
        for n in pairs(options) do
            if defaultOptions[n] == nil then
                options[n] = defaultOptions[n]
            end
        end
    else
        options = defaultOptions
    end

    local data = {}

    data.authKey = functions.generateAuthkey()
    data.connectionKey = connectionKey

    data.onData = {}
    data.onDisconnect = {}
    data.onNewConnection = {}
    data.clients = {}

    data.onDataSys = {}
    data.onDataSync = {}

    data.currentData = {}

    data.started = false
    data.options = options

    function data.on(onName, func)
        if type(func) ~= 'function' then
            error('invalid func')
        end

        local currentTable

        if onName == 'data' then
            currentTable = data.onData
        elseif onName == 'disconnect' then
            currentTable = data.onDisconnect
        elseif onName == 'connect' then
            currentTable = data.onNewConnection
        elseif onName == 'data_system' then
            currentTable = data.onDataSys
        elseif onName == 'data_sync' then
            currentTable = data.onDataSync
        else
            error('invalid onName')
        end

        currentTable[func] = true

        return {
            disconnect = function()
                currentTable[func] = nil
            end,
        }
    end

    function data.addClient()
        local d = {}

        d.id = functions.generateAuthkey()
        d.isNew = true
        d.removed = false

        function d.remove(r, dontNotifyClient, noInfo, closedByClient)
            if not r then
                r = 'Disconnected'
            end
            if closedByClient == nil then
                closedByClient = false
            end

            d.removed = true

            if not dontNotifyClient then
                data.clients[d.id] = {
                    connectionClosed = true,
                    reason = r,
                }
            else
                data.clients[d.id] = nil
            end

            data.currentData[d.id] = nil

            if not noInfo then
                functions.runAll(data.onDisconnect, d, r, closedByClient)
            end
        end

        coroutine.wrap(function()
            while true do
                if d.removed or data.shutdown then
                    break
                end

                if not d.isNew then
                    print('Checking client...')

                    local checked
                    local now = 0

                    local funcs = data.on('data_system', function(clientid, data)
                        if clientid.id == d.id then
                            if data.checked == 1 then
                                checked = true
                            end
                        end
                    end)
                    data.sendDataToClient({
                        action = 'checkClient',
                        systemData = true,
                    }, d.id)

                    repeat
                        timer.sleep(1000)
                        now = now + 1
                        if d.removed or data.shutdown then
                            funcs.disconnect()

                            print('connection is closed')

                            return
                        end
                    until checked ~= nil or now > 10

                    funcs.disconnect()

                    if checked then
                        print('Client checked!')
                    else
                        print('Failed to check the client...')

                        d.remove('Failed to check the client', true)

                        break
                    end
                else
                    d.isNew = false

                    print('Client is new...')
                end

                timer.sleep(60000)
            end
        end)()

        data.currentData[d.id] = {}
        data.clients[d.id] = d

        functions.runAll(data.onNewConnection, d)

        return d
    end

    function data.startServer()
        data.started = true

        pcall(function()
          print('Server with name "' .. serverName .. '" started')
        end)
    end

    function data.shutdownServer()
        for ind, val in pairs(data) do
            if type(val) == 'function' then
                data[ind] = function()
                    error('server is closed')
                end
            end
        end

        data.shutdown = true

        for _, client in pairs(data.clients) do
            client.remove(nil, true, true)
        end

        servers[serverName] = nil

        print('Server with name "' .. serverName .. '" closed')
    end

    function data.sendData(tableData)
        for clientId in pairs(data.clients) do
            data.sendDataToClient(tableData, clientId)
        end
    end

    function data.sendDataToClient(tableData, clientId)
        if type(tableData) ~= 'table' then
            error('invalid tableData')
        end
        if type(clientId) ~= 'string' then
            error('invalid clientId')
        end
        if not data.clients[clientId] then
            error('client not found')
        end
        if not tableData.systemData and not data.options.clientAllowGet then
            error('only systemData allowed')
        end

        table.insert(data.currentData[clientId], tableData)
    end

    function data.sendDataToClientSync(tableData, clientId, maxAttempts)
        if type(tableData) ~= 'table' then
            error('invalid tableData')
        end
        if type(clientId) ~= 'string' then
            error('invalid clientId')
        end
        if not data.clients[clientId] then
            error('client not found')
        end

        if not maxAttempts then
            maxAttempts = 10
        end

        local received
        local receivedData
        local receiveId = functions.generateAuthkey()

        local f = data.on('data_sync', function(client, data)
            if client.id == clientId and data.receiveId == receiveId then
                received = true
                receivedData = data
            end
        end)

        tableData.syncData = true
        tableData.receiveId = receiveId

        data.sendDataToClient(tableData, clientId)

        local now = 0

        repeat
            timer.sleep(1000)
            now = now + 1
        until now > maxAttempts or received

        f.disconnect()

        if not received then
            error('no data received')
        else
            return receivedData
        end
    end

    function data.sendDataSync(tableData, maxAttempts, ignoreClientLoss, onTick)
        if type(tableData) ~= 'table' then
            error('invalid tableData')
        end

        if not maxAttempts then
            maxAttempts = 10
        end

        -- ['clientid'] = {data}
        local received = {}
        local receivedCount = 0
        local receiveId = functions.generateAuthkey()
        local clients = functions.deepCopy(data.clients)
        local clientCount = functions.count(clients)

        local f = data.on('data_sync', function(client, data)
            if data.receiveId == receiveId and clients[client.id] then
                received[client.id] = data
                receivedCount = receivedCount + 1
            end
        end)

        tableData.syncData = true
        tableData.receiveId = receiveId

        for id in pairs(clients) do
            data.sendDataToClient(tableData, id)
        end

        local now = 0

        repeat
            if onTick then
                onTick(now)
            end

            timer.sleep(1000)
            now = now + 1
        until now > maxAttempts or receivedCount == clientCount

        f.disconnect()

        if receivedCount ~= clientCount and not ignoreClientLoss then
            error('invalid data received')
        else
            return received, (receivedCount ~= clientCount)
        end
    end

    function data.setSyncFunction(func)
        data.syncFunc = func
    end

    pcall(function()
      servers[serverName] = data
      print('Server with name "' .. serverName .. '" added')
    end)

    return data
end

corohttp.createServer('0.0.0.0', 1337, function(req, body)
    if req.method == 'POST' then
        if req.path == '/server' then
            local data = json.parse(body)
            local server = servers[data.serverName]
            local client

            if server then
                if not server.started then
                    print('Server is not started. Waiting for start...')

                    repeat
                        timer.sleep(1000)
                    until server.started

                    print('Server started!')
                end
                if data.authKey ~= server.authKey and data.action ~= 'connect' then
                    return {
                        code = 401,
                    }, 'Invalid auth key'
                end

                client = server.clients[data.clientId]

                if not client and data.action ~= 'connect' then
                    return {
                        code = 401,
                    }, 'Client is not registered'
                end
                if client and client.connectionClosed then
                    server.clients[data.clientId] = nil

                    return {
                        code = 400,
                    }, client.reason
                end

                if data.action == 'connect' then
                    if server.connectionKey and data.connectKey ~= server.connectionKey then
                        print('Someone tried to connect to the server without a connection key')

                        return {
                            code = 401,
                        }, 'Invalid connectionKey'
                    else
                        local d = server.addClient()

                        return {
                            code = 200,
                        }, json.encode({
                            authKey = server.authKey,
                            clientId = d.id,
                        })
                    end
                elseif data.action == 'getData' then
                    local dd = server.currentData[data.clientId]

                    for index, dat in ipairs(dd) do
                        table.remove(dd, index)

                        return {
                            code = 200,
                        }, json.encode(dat)
                    end

                    return {
                        code = 200
                    }, 'No data'
                elseif data.action == 'setData' then
                    local d = data.data

                    if d.systemData then
                        functions.runAll(server.onDataSys, client, d)
                    elseif d.syncData then
                        functions.runAll(server.onDataSync, client, d)
                    elseif d.userSyncData then
                        if server.syncFunc then
                            return { code = 200 }, json.encode(server.syncFunc(client, d))
                        else
                            return { code = 200 }, 'Sync function is not set'
                        end
                    else
                        if not server.options.clientAllowSend then
                            return {
                                code = 403,
                            }, 'Only systemData allowed'
                        end

                        functions.runAll(server.onData, client, d)
                    end

                    return {
                        code = 200,
                    }, 'Set data'
                elseif data.action == 'disconnect' then
                    client.remove(data.reason or 'Client disconnected', true, false, true)

                    return {
                        code = 200,
                    }, 'Disconnected'
                end
            end
        end
    end

    return {
        code = 404,
    }, 'Not found'
end)

return functions
