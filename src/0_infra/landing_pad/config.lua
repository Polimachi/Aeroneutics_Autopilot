-- src/0_infra/landing_pad/config.lua
-- Default configuration specification for Landing Pad Controller

local config_store = require("modules.config_store")
return config_store.get_default_config()
