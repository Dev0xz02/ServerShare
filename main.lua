local discordia = require('discordia')
local json = require('json')
local corohttp = require('coro-http')
local fs = require('fs')
local timer = require('timer')
local servershare = require('./ServerShare/ServerShare')

local settings

local function loadSettings()
    local function parseValue(value)
        if value:sub(1, 7) == 'Secret:' then
            local name = value:sub(8)
            local envValue = os.getenv(name)

            if envValue == nil then
                error('Value for "' .. name .. '" not found', 0)
            else
                return envValue
            end
        else
            return value
        end
    end

    local tt = json.parse(fs.readFileSync('./settings.json'))

    local function parseSettings(tab)
        for index, value in pairs(tab) do
            if type(value) == 'table' then
                parseSettings(value)
            end
            if type(index) == 'table' then
                parseSettings(index)
            end

            if type(value) == 'string' then
                value = parseValue(value)
            end

            tab[index] = value
        end
    end

    parseSettings(tt)

    return tt
end

settings = loadSettings()

local commands = {}
local server

local ownerId = settings.ownerId or nil
local appOnlyRoleId = settings.appOnlyRoleId or nil
local gameModRoleId = settings.gameModRoleId or nil
local gameDevId = settings.gameDevId or nil

local botClient = discordia.Client()
discordia.extensions()

local function formatTable(tab, func)
    local str = ''

    for _, value in pairs(tab) do
        str = str .. func(str)
    end

    return str
end

local function openAndParse(fileName)
    return json.parse(fs.readFileSync('./' .. fileName))
end

local function stringifyAndSave(fileName, data)
    return fs.writeFileSync('./' .. fileName, json.stringify(data))
end

local function addCommand(tab)
    commands[tab.name] = tab
end

local function runCommand(message, command, ignoreChecks, arguments)
    if not message.guild then
        message:reply('Commands in private messages are disabled')

        return
    end

    local author = message.guild:getMember(message.author.id)
    local cmdName = settings.prefix .. command.name

    if not ignoreChecks then
        if command.allowedOnly then
            local allowedUsers = openAndParse('allowedusers.json')

            if not allowedUsers[message.author.id] and message.author.id ~= ownerId then
                return
            end
        end
        if command.ownerOnly then
            if message.author.id ~= ownerId then
                return
            end
        end
        if command.appOnly and message.author.id ~= ownerId and not author:hasRole(appOnlyRoleId) then
            return
        end
    end

    local success, result = pcall(command.func, message, author, arguments)

    if not success then
        local errorText = cmdName ..
            '\n' .. table.concat(arguments, '; ') .. '\n' .. message.author.tag .. '\n' .. tostring(result)

        do
            local content = fs.readFileSync('./errors.txt')

            content = content .. errorText .. '\n\n\n'

            fs.writeFileSync('./errors.txt', content)
        end

        print(errorText)

        message:reply({
            embeds = {
                {
                    title = cmdName .. ' - Command Error!',
                    color = 13575718,
                    description = tostring(result):gsub('F8sVQRNmUaLbu4t', '(Secret)'),
                },
            },
        })
    else
        if result then
            local title = 'Command results.'
            local description
            local customembeds
            local color = 4378406

            if type(result) == 'table' then
                if result.use then
                    description = result.description

                    if result.title then
                        title = result.title
                    end
                    if result.color then
                        color = result.color
                    end
                elseif result.usecustom then
                    result.usecustom = nil

                    customembeds = result
                end
            end

            if not description then
                description = tostring(result)
            end

            if customembeds then
                message:reply(customembeds)
            else
                message:reply({
                    embeds = {
                        {
                            title = cmdName .. ' - ' .. title,
                            color = color,
                            description = description,
                        },
                    },
                })
            end
        end
    end
end

local function parseMessage(message, ignoreChecks)
    local text = message.content

    if string.match(text, '@') or string.match(text, '#') then
        message:reply({
            embeds = {
                {
                    title = 'Invalid characters',
                    color = 13575718,
                    description = 'These symbols are forbidden: @, #',
                },
            },
        })

        return
    end

    local arguments = text:sub(2):split(settings.splitkey)
    local commandName = string.lower(arguments[1])
    local command = commands[commandName]

    if command then
        table.remove(arguments, 1)

        runCommand(message, command, ignoreChecks, arguments)
    end
end

local function getPlayerName(displayname, name, userid)
    local final
    local usedDisplay = false

    if name == nil then
        name = 'Unknown'
    end

    if displayname ~= nil and displayname ~= name then
        usedDisplay = true
        final = '@' .. displayname .. ' (' .. name .. ')'
    else
        final = name
    end

    if userid then
        if usedDisplay then
            final = final:sub(1, #final - 1) .. ', ' .. userid .. ')'
        else
            final = final .. ' (' .. userid .. ')'
        end
    end

    return final
end

local function createPages(pageTab, maxItems, chunk)
    if maxItems == nil then
        maxItems = 20
    end
    if chunk == nil then
        chunk = 1
    end

    local chunks = {}

    do
        local function deepCopy(table)
            local new = {}

            for index, value in pairs(table) do
                if type(index) == 'table' then
                    index = deepCopy(index)
                end
                if type(value) == 'table' then
                    value = deepCopy(value)
                end

                new[index] = value
            end

            return new
        end
        local function count(tab)
            local count = 0

            for a in pairs(tab) do
                count = count + 1
            end

            return count
        end

        local newPageTab = deepCopy(pageTab)

        local function addChunk()
            local tt = {}
            local now = 0

            for index, value in pairs(newPageTab) do
                if now < maxItems then
                    now = now + 1
                    newPageTab[index] = nil
                    table.insert(tt, { index, value })
                else
                    break
                end
            end

            return tt
        end

        repeat
            table.insert(chunks, addChunk())
        until count(newPageTab) == 0
    end

    local ck = chunks[chunk]
    local index = 0

    if #chunks < 1 then
        error('Pages is empty', 0)
    end
    if ck == nil then
        error('Page not found', 0)
    end

    return ck, chunks, function()
        index = index + 1

        local data = ck[index]

        if data ~= nil then
            return data[1], data[2]
        else
            return nil
        end
    end
end

local function showBans(index, findValue)
    local str = ''
    local bans = openAndParse('bans.json')

    local function getBanInfo(banData, i)
        local new = ''

        if i then
            new = i .. '. '
        end

        new = new ..
            '`' ..
            getPlayerName(banData.display, banData.name, banData.id) ..
            '` - `' .. banData.reason .. '`\nBanned By: `' .. banData.bannedby .. '`'

        return new
    end

    if findValue then
        local _, chunks = createPages(bans, 15)

        for _, banData in pairs(bans) do
            if tonumber(findValue) == banData.id or string.lower(findValue) == banData.name:lower() then
                for index, value in pairs(chunks) do
                    for index2, value2 in pairs(value) do
                        if banData.name == value2[2].name then
                            str = 'Finded in page `' .. index .. '/' .. #chunks .. '`\n\n\n'
                        end
                    end
                end

                str = str .. getBanInfo(banData)

                return str
            end
        end

        return 'Not found'
    end

    local _, chunks, func = createPages(bans, 15, index)

    str = 'Page `' .. index .. '/' .. #chunks .. '`\n\n\n' .. str

    --[[
        ["Index"] = {
            ["name"] = "Roblox",
            ["display"] = "Roblox",
            ["id"] = "1",
            ["reason"] = "reason",
            ["bannedby"] = "NoName123 2.0#12345"
        }
    ]]
    for index, banData in func do
        str = str .. getBanInfo(banData, index) .. '\n\n'
    end

    return str
end

local function getPlayer(player)
    if type(player) == 'number' or tonumber(player) then
        local success, result, body = pcall(corohttp.request, 'GET', 'http://users.roblox.com/v1/users/' .. player)

        if success then
            if result.code == 200 then
                return true, json.parse(body)
            else
                if result.code == 404 then
                    return false, 'This user does not exist'
                else
                    return false, 'Roblox returned: ' .. result.code
                end
            end
        else
            return false, 'Error: ' .. tostring(result):sub(1, 40)
        end
    else
        local success, result, body = pcall(corohttp.request, 'POST', 'https://users.roblox.com/v1/usernames/users',
            { { 'Content-Type', 'application/json' } },
            json.stringify({ usernames = { player }, excludeBannedUsers = true }))

        if success then
            if result.code == 200 then
                local ud = json.parse(body).data

                if not ud[1] then
                    return false, 'This user does not exist'
                else
                    ud = ud[1]
                end

                return true, ud
            else
                return false, 'Roblox returned: ' .. result.code
            end
        else
            return false, 'Error: ' .. tostring(result):sub(1, 40)
        end
    end
end

addCommand({
    name = 'find',
    description = 'Finds a player in bans',
    argumentsExample = { 'Userid or Username' },
    allowedOnly = true,
    func = function(message, author, arguments)
        return showBans(nil, arguments[1])
    end,
})

addCommand({
    name = 'commands',
    description = 'Shows the commands',
    argumentsExample = { '(Optional) Page' },
    func = function(message, author, arguments)
        local cmds = {}
        local pageIndex

        if arguments[1] then
            pageIndex = tonumber(arguments[1])

            if not pageIndex then
                return {
                    use = true,
                    title = 'Arguments Error',
                    color = 13831445,
                    description = '`Page` - Invalid argument'
                }
            end
        else
            pageIndex = 1
        end

        for commandName, data in pairs(commands) do
            local str = '**' .. settings.prefix .. commandName

            if data.argumentsExample then
                str = str .. settings.splitkey .. table.concat(data.argumentsExample, settings.splitkey)
            end

            str = str .. '**\n`' .. (data.description or '(No description)') .. '`'

            table.insert(cmds, str)
        end

        local _, chunks, list = createPages(cmds, 8, pageIndex)
        local str = ''

        for _, text in list do
            str = str .. text .. '\n\n\n'
        end

        message:reply({
            embeds = {
                {
                    title = '(' .. pageIndex .. '/' .. #chunks .. ') Commands',
                    description = str,
                    color = 902099,
                },
            }
        })
    end,
})

addCommand({
    name = 'bans',
    allowedOnly = true,
    description = 'Shows the bans',
    argumentsExample = { '(Optional) Page' },
    func = function(message, author, arguments)
        return showBans(tonumber(arguments[1]) or 1)
    end,
})

addCommand({
    name = 'unban',
    description = 'Unbans a player',
    argumentsExample = { 'Userid or Username' },
    allowedOnly = true,
    func = function(message, author, arguments)
        local bans = openAndParse('bans.json')
        local appeals = openAndParse('appeals.json')
        local user = arguments[1]
        local playerName

        if not user then
            return {
                use = true,
                title = 'Arguments Error',
                color = 13831445,
                description = '`Userid or Username` - Invalid argument'
            }
        else
            if tonumber(user) then
                user = tonumber(user)
            else
                user = user:lower()
            end

            local success, playerData = getPlayer(user)

            if success then
                playerName = getPlayerName(playerData.displayName, playerData.name, playerData.id)
            else
                error(playerData, 0)
            end
        end

        for index, banData in pairs(bans) do
            local val

            if type(user) == 'number' then
                val = tonumber(banData.id)
            else
                val = banData.name:lower()
            end

            if val == user then
                appeals[tostring(banData.id)] = nil

                table.remove(bans, index)

                stringifyAndSave('bans.json', bans)
                stringifyAndSave('appeals.json', appeals)

                server.sendData({
                    action = 'removeBan',
                    banTable = banData,
                })

                return {
                    use = true,
                    title = 'Unbanned',
                    description = '`' ..
                        playerName ..
                        '` With reason `' .. banData.reason .. '` Unbanned.',
                }
            end
        end

        return {
            use = true,
            title = 'Not found!',
            color = 13831445,
            description = 'Player `' .. playerName .. '` not found'
        }
    end,
})

addCommand({
    name = 'ban',
    description = 'Bans a player',
    argumentsExample = { 'Userid or Username', '(Optional) Reason' },
    allowedOnly = true,
    func = function(message, author, arguments)
        local bans = openAndParse('bans.json')
        local user = arguments[1]
        local reason = arguments[2]
        local playerName
        local player

        if not user then
            return {
                use = true,
                title = 'Arguments Error',
                color = 13831445,
                description = '`Userid or Username` - Invalid argument'
            }
        else
            if tonumber(user) then
                user = tonumber(user)
            else
                user = user:lower()
            end

            local success, playerData = getPlayer(user)

            if success then
                player = playerData
                playerName = getPlayerName(playerData.displayName, playerData.name, playerData.id)
            else
                error(playerData, 0)
            end
        end
        if not reason then
            reason = '(No reason)'
        else
            table.remove(arguments, 1)

            reason = table.concat(arguments, ' ')
        end

        for index, banData in pairs(bans) do
            local val

            if type(user) == 'number' then
                val = tonumber(banData.id)
            else
                val = banData.name:lower()
            end

            if val == user then
                return {
                    use = true,
                    title = 'Already banned',
                    color = 13831445,
                    description = '`' ..
                        playerName ..
                        '` With reason `' .. banData.reason .. '` Is already banned.',
                }
            end
        end

        local ban = {
            ['name'] = player.name,
            ['display'] = (player.name ~= player.displayName and player.displayName or nil),
            ['id'] = player.id,
            ['reason'] = reason,
            ['bannedby'] = message.author.tag,
        }

        table.insert(bans, ban)

        stringifyAndSave('bans.json', bans)

        server.sendData({
            action = 'addBan',
            banTable = ban,
        })

        return {
            use = true,
            title = 'Banned',
            description = '`' ..
                playerName ..
                '` With reason `' .. reason .. '` Banned.',
        }
    end,
})

addCommand({
    name = 'kick',
    description = 'Kicks a player',
    argumentsExample = { 'Userid or Username', '(Optional) Reason' },
    allowedOnly = true,
    func = function(message, author, arguments)
        local user = arguments[1]
        local reason = arguments[2]
        local playerName
        local player

        if not user then
            return {
                use = true,
                title = 'Arguments Error',
                color = 13831445,
                description = '`Userid or username` - Invalid argument'
            }
        else
            if tonumber(user) then
                user = tonumber(user)
            else
                user = user:lower()
            end

            local success, playerData = getPlayer(user)

            if success then
                player = playerData
                playerName = getPlayerName(playerData.displayName, playerData.name, playerData.id)
            else
                error(playerData, 0)
            end
        end
        if not reason then
            reason = '(No reason)'
        else
            table.remove(arguments, 1)

            reason = table.concat(arguments, ' ')
        end

        local text = '%sSearching for ' .. playerName .. '...'
        local messageCount = message:reply(text:format(''))

        local success, result, dataloss = pcall(function()
            return server.sendDataSync({
                action = 'kick',
                playerId = player.id,
                reason = reason,
            }, 25, true, function(now)
                messageCount:setContent(text:format('(' .. now .. ') - '))
            end)
        end)

        messageCount:delete()

        if success then
            if dataloss then
                message:reply('Some servers did not send a response!')
            end

            for _, data in pairs(result) do
                if data.kicked then
                    local players = formatTable(data.players, function(str)
                        if str:sub(1, #player.name) == #player.name then
                            return str .. ' (Kicked)'
                        else
                            return str
                        end
                    end)

                    if players == '' then
                        players = '(No players)'
                    end

                    return '`' .. playerName .. '` Kicked!\n\nJobid: `' ..
                        data.jobId .. '`\n\nPlayers: `' .. players .. '`'
                end
            end

            return {
                use = true,
                title = 'Not found!',
                color = 13831445,
                description = '`' .. playerName .. '` Not found.'
            }
        end
    end,
})

addCommand({
    name = 'shutdown',
    description = 'Closes the server by Jobid',
    argumentsExample = { 'JobId', '(Optional) Reason' },
    allowedOnly = true,
    func = function(message, author, arguments)
        local jobid = arguments[1]
        local reason = arguments[2]

        if not jobid then
            return {
                use = true,
                title = 'Arguments Error',
                color = 13831445,
                description = '`JobId` - Invalid argument'
            }
        end
        if not reason then
            reason = '(No reason)'
        else
            table.remove(arguments, 1)

            reason = table.concat(arguments, ' ')
        end

        local text = '%sSearching for a server...'
        local messageCount = message:reply(text:format(''))

        local success, result, dataloss = pcall(function()
            return server.sendDataSync({
                action = 'shutdown',
                jobId = jobid,
                reason = reason,
            }, 25, true, function(now)
                messageCount:setContent(text:format('(' .. now .. ') - '))
            end)
        end)

        messageCount:delete()

        if success then
            if dataloss then
                message:reply('Some servers did not send a response!')
            end

            for _, data in pairs(result) do
                if data.shutdown then
                    local players = data.players

                    if not players or #players < 1 then
                        players = '(No players)'
                    else
                        players = table.concat(players, '; ')
                    end

                    return 'Server with Jobid `' ..
                        jobid .. '` closed.\n\n\nPlayers: `' .. players .. '`'
                end
            end

            return {
                use = true,
                title = 'Server not found!',
                color = 13831445,
                description = 'Server with Jobid `' .. jobid .. '` Not found.'
            }
        else
            error(result, 0)
        end
    end,
})

addCommand({
    name = 'hint',
    description = 'Sends a message to the server',
    argumentsExample = { 'JobId or all', 'Text', '(Optional) Timeout' },
    allowedOnly = true,
    func = function(message, author, arguments)
        local jobid = arguments[1]
        local msg = arguments[2]
        local timeout = tonumber(arguments[3])

        if not jobid then
            return {
                use = true,
                title = 'Arguments Error',
                color = 13831445,
                description = '`JobId` - Invalid argument'
            }
        end
        if not msg then
            return {
                use = true,
                title = 'Arguments Error',
                color = 13831445,
                description = '`Text` - Invalid argument'
            }
        end
        if not timeout then
            timeout = nil
        end

        local text = '%sSearching for a server...'
        local messageCount = message:reply(text:format(''))

        local success, result, dataloss = pcall(function()
            return server.sendDataSync({
                action = 'hint',
                jobId = jobid,
                text = msg,
                timeOut = timeout,
            }, 25, true, function(now)
                messageCount:setContent(text:format('(' .. now .. ') - '))
            end)
        end)

        messageCount:delete()

        if success then
            if dataloss then
                message:reply('Some servers did not send a response!')
            end

            local final = {}

            for _, data in pairs(result) do
                if data.sended then
                    table.insert(final, 'Server "' .. (data.jobId or '(Unknown)') .. '" received a message')
                end
            end

            if #final < 1 then
                return {
                    use = true,
                    title = 'Server not found!',
                    color = 13831445,
                    description = 'Server with Jobid `' .. jobid .. '` Not found.'
                }
            else
                return table.concat(final, ';\n\n')
            end
        else
            error(result, 0)
        end
    end,
})

addCommand({
    name = 'players',
    description = 'Shows a list of players',
    argumentsExample = nil,
    allowedOnly = true,
    func = function(message, author, arguments)
        local text = '%sGetting a list of players...'
        local messageCount = message:reply(text:format(''))

        local success, result, dataloss = pcall(function()
            return server.sendDataSync({
                action = 'getPlayers',
            }, 25, true, function(now)
                messageCount:setContent(text:format('(' .. now .. ') - '))
            end)
        end)

        messageCount:delete()

        if success then
            if dataloss then
                message:reply('Some servers did not send a response!')
            end

            local final = ''
            local finalCount = 0

            for _, data in pairs(result) do
                local serverType = 'Public'
                local players = data.players
                local playersCount = 0

                if data.serverType == 1 then
                    serverType = 'Private'
                elseif data.serverType == 2 then
                    serverType = 'Reserved'
                end
                if not players or #players < 1 then
                    players = '(No players)'
                else
                    playersCount = #players
                    players = table.concat(players, '; ')
                end

                final = final ..
                    '`' ..
                    (data.jobId or '(Unknown)') ..
                    '`\nPlayers: `' .. players .. '`\nServer type: `' .. serverType .. '`\n\n\n'

                finalCount = finalCount + playersCount
            end

            final = final .. 'Total number of players: ' .. finalCount

            return final
        else
            error(result, 0)
        end
    end,
})

addCommand({
    name = 'addmod',
    appOnly = true,
    description = 'Adds a user to moderators',
    argumentsExample = { 'Discord Userid' },
    func = function(message, author, arguments)
        local id = arguments[1] or error('No Userid', 0)
        local user = botClient:getUser(id)
        local users = openAndParse('allowedusers.json')

        if not user then
            return 'This user does not exist'
        end
        if user.id == message.author.id then
            return 'You cant add yourself'
        end

        local name = user.tag .. ' (' .. id .. ')'

        if users[id] then
            return '`' .. name .. '` Is already added'
        else
            users[id] = true

            local member = message.guild:getMember(id)

            if member then
                member:addRole(gameModRoleId)
            end
        end

        stringifyAndSave('allowedusers.json', users)

        return '`' .. name .. '` Added'
    end,
})

addCommand({
    name = 'unmod',
    appOnly = true,
    description = 'Removes a user from the moderators',
    argumentsExample = { 'Discord Userid' },
    func = function(message, author, arguments)
        local id = arguments[1] or error('No Userid', 0)
        local user = botClient:getUser(id)
        local users = openAndParse('allowedusers.json')

        if not user then
            return 'This user does not exist'
        end

        local name = user.tag .. ' (' .. id .. ')'

        if users[id] then
            users[id] = nil

            local member = message.guild:getMember(id)

            if member then
                if member:hasRole(gameDevId) then
                    return 'He is a developer'
                end

                member:removeRole(gameModRoleId)
            end
        else
            return '`' .. name .. '` Not found in the moderator list'
        end

        stringifyAndSave('allowedusers.json', users)

        return '`' .. name .. '` Removed'
    end,
})

addCommand({
    name = 'mods',
    description = 'Shows a list of moderators',
    func = function(message, author, arguments)
        local users = openAndParse('allowedusers.json')
        local str = ''

        for id in pairs(users) do
            local user = botClient:getUser(id)
            local tt = ''

            if not user then
                tt = 'Unknown'
            else
                tt = user.tag .. ' (' .. id .. ')'
            end

            str = str .. tt .. '\n'
        end

        return str
    end,
})

addCommand({
    name = 'reply',
    allowedOnly = true,
    description = 'Responds to a players answer',
    argumentsExample = { 'Userid or Username', 'Block (true or false)', '(Optional) Reason' },
    func = function(message, author, arguments)
        local user = arguments[1]
        local block = arguments[2]
        local reason = arguments[3]

        local player
        local playerName

        if not user then
            return {
                use = true,
                title = 'Arguments Error',
                color = 13831445,
                description = '`Userid or Username` - Invalid argument'
            }
        else
            local success, result = getPlayer(user)

            if success then
                player = result
                playerName = getPlayerName(result.displayName, result.name, result.id)
            else
                error(result, 0)
            end
        end
        if block == 'true' then
            block = true
        elseif block == 'false' then
            block = false
        else
            return {
                use = true,
                title = 'Arguments Error',
                color = 13831445,
                description = '`Block (true or false)` - Invalid argument'
            }
        end
        if not reason then
            reason = '(No reason)'
        else
            table.remove(arguments, 1)
            table.remove(arguments, 1)

            reason = table.concat(arguments, ' ')
        end

        local appeals = openAndParse('appeals.json')
        local appeal = appeals[tostring(player.id)]

        if appeal then
            local edited = (appeal.blocked or appeal.reply)
            local t

            if block then
                appeal.blocked = true
                appeal.reply = nil

                if edited then
                    t = 'You changed a blocked appeal'
                else
                    t = 'You blocked the appeal'
                end
            else
                appeal.reply = true
                appeal.blocked = nil

                if edited then
                    t = 'You changed your answer to the appeal'
                else
                    t = 'You responded to the appeal'
                end
            end

            appeal.reason = reason
            appeal.text = '(Removed)'

            stringifyAndSave('appeals.json', appeals)

            return t
        else
            return 'No appeal for player `' .. playerName .. '` found'
        end
    end,
})

addCommand({
    name = 'delete',
    allowedOnly = true,
    description = 'Removes player appeal',
    argumentsExample = { 'Userid or Username' },
    func = function(message, author, arguments)
        local user = arguments[1]

        local player
        local playerName

        if not user then
            return {
                use = true,
                title = 'Arguments Error',
                color = 13831445,
                description = '`Userid or Username` - Invalid argument'
            }
        else
            local success, result = getPlayer(user)

            if success then
                player = result
                playerName = getPlayerName(result.displayName, result.name, result.id)
            else
                error(result, 0)
            end
        end

        local appeals = openAndParse('appeals.json')
        local strid = tostring(player.id)
        local appeal = appeals[strid]

        if appeal then
            appeals[strid] = nil

            stringifyAndSave('appeals.json', appeals)

            return 'Appeal deleted'
        else
            return 'No appeal for player `' .. playerName .. '` found'
        end
    end,
})

addCommand({
    name = 'appeals',
    allowedOnly = true,
    description = 'Shows appeals',
    argumentsExample = { '(Optional) Page' },
    func = function(message, author, arguments)
        local appeals = openAndParse('appeals.json')
        local text
        local index = tonumber(arguments[1]) or 1
        local chunk, chunks, func = createPages(appeals, 5, index)

        text = 'Page ' .. index .. '/' .. #chunks .. '\n\n\n'

        for userid, appeal in func do
            text = text ..
                (appeal.blocked and '(Blocked) ' or '') ..
                (appeal.reply and '(Reply) ' or '') .. userid .. ' - `' .. appeal.text .. '`\n\n\n'
        end

        return text
    end,
})

addCommand({
    name = 'loadstring',
    description = 'Loads the code',
    func = function(message, author, arguments)
        --local success, result = loadstring('return function(bot) ' .. table.concat(arguments, ' ') .. ' end', 'Bot')

        --if not success then
        --    error(result, 0)
        --else
        --    message:reply('Loading code...')
        --    return tostring(success()(botClient))
        --end

        message:reply('I\'m sorry, but this command is disabled. Check code in main.lua, line 1227-1234 and uncomment that.')
    end,
})

botClient:on('messageCreate', function(message)
    if message.author.bot then return end

    if message.content:sub(1, 1) == settings.prefix then
        parseMessage(message, false)
    end
end)

botClient:on('ready', function()
    botClient:setStatus('dnd')
    botClient:setActivity(settings.prefix .. 'commands')

    print('Bot logged in into '..client.user.username..".")
end)

botClient:run('Bot ' .. settings.token)

if settings.server and settings.server.name then
    server = servershare.createServer(settings.server.name, settings.server.connectionkey)

    server.setSyncFunction(function(client, data)
        if data.action == 'getbans' then
            local bans = openAndParse('bans.json')

            return bans
        elseif data.action == 'isbanned_appeal' then
            local bans = openAndParse('bans.json')
            local appeals = openAndParse('appeals.json')
            local appeal = appeals[data.userid]

            local function removeAndSave(id)
                appeals[id] = nil

                stringifyAndSave('appeals.json', appeals)
            end

            for _, ban in pairs(bans) do
                if tostring(ban.id) == data.userid then
                    if not appeal then
                        return {
                            status = 'banned',
                            reason = ban.reason,
                            bannedby = ban.bannedby,
                        }
                    else
                        if appeal.blocked then
                            return {
                                status = 'blocked',
                                reason = appeal.reason,
                            }
                        elseif appeal.reply then
                            removeAndSave(data.userid)

                            return {
                                status = 'reply',
                                reason = appeal.reason
                            }
                        else
                            return {
                                status = 'banned',
                                sended = true,
                                reason = ban.reason,
                                bannedby = ban.bannedby,
                                whytext = appeal.text,
                            }
                        end
                    end
                end
            end

            if appeal then
                removeAndSave(data.userid)
            end

            return {
                status = 'notbanned',
            }
        elseif data.action == 'sendappeal' then
            local appeals = openAndParse('appeals.json')

            if appeals[data.userid] then
                return {
                    sended = false,
                }
            else
                local text = data.text:sub(1, 1000)

                appeals[data.userid] = {
                    text = text,
                }

                stringifyAndSave('appeals.json', appeals)

                local channel = botClient:getChannel('1086313054834282506')

                if channel then
                    channel:send('**New appeal**\n\n\nPlayer name: `' ..
                        data.playername .. '`\n\nAppeal text: `' .. text .. '`')
                end

                return {
                    sended = true,
                }
            end
        end
    end)

    server.startServer()
end