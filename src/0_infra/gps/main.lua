-- Standard Entrypoint for CC-GPS (src/0_infra/gps/main.lua)
local args = { ... }
local mode = args[1] or "server"

if mode == "node" then
    local nodeArgs = {}
    for i = 2, #args do nodeArgs[#nodeArgs + 1] = args[i] end
    shell.run("node.lua", table.unpack(nodeArgs))
elseif mode == "client" then
    local clientArgs = {}
    for i = 2, #args do clientArgs[#clientArgs + 1] = args[i] end
    shell.run("client_entry.lua", table.unpack(clientArgs))
else
    -- Default to Server Daemon
    shell.run("server.lua", table.unpack(args))
end
