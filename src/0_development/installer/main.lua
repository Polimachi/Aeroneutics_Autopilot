-- src/0_development/installer/main.lua
-- Entry point delegating to bootstrapper

package.path = package.path .. ";?.lua;modules/?.lua;src/0_development/installer/?.lua;src/0_development/installer/modules/?.lua"
local bootstrapper = require("installer")
return bootstrapper.bootstrapAndRun({ cliArgs = { ... } })
