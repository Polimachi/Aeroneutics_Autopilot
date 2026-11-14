-- src/3_planning/amm/modules/waypoint_queue.lua
-- AMM Waypoint FIFO Queue & JSON Persistence
local waypoint_queue = {}
waypoint_queue.__index = waypoint_queue

function waypoint_queue.new(config)
    local cfg = config or {}
    local self = setmetatable({
        items = {},
        active_index = 1,
        state = "IDLE",
        defaultAlt = cfg.defaultAlt or 150.0,
        defaultSpeed = cfg.defaultSpeed or 18.0,
        arrivalRadius = cfg.arrivalRadius or 15.0,
    }, waypoint_queue)
    return self
end

function waypoint_queue:count()
    return #self.items
end

function waypoint_queue:get_all()
    return self.items
end

function waypoint_queue:get_active()
    if #self.items == 0 or self.active_index > #self.items then
        return nil
    end
    return self.items[self.active_index]
end

function waypoint_queue:add(x, z, alt, speed, facilityId)
    local item = {
        id = #self.items + 1,
        x = tonumber(x) or 0.0,
        z = tonumber(z) or 0.0,
        alt = tonumber(alt) or self.defaultAlt,
        speed = tonumber(speed) or self.defaultSpeed,
        facilityId = facilityId,
        completed = false,
    }
    table.insert(self.items, item)
    if self.state == "IDLE" then
        self.state = "EN_ROUTE"
    end
    return item
end

function waypoint_queue:del(index)
    local idx = tonumber(index)
    if not idx or idx < 1 or idx > #self.items then
        return false, "INVALID_INDEX"
    end
    table.remove(self.items, idx)
    for i, item in ipairs(self.items) do
        item.id = i
    end
    if self.active_index > #self.items then
        self.active_index = math.max(1, #self.items)
    end
    if #self.items == 0 then
        self.state = "IDLE"
    end
    return true
end

function waypoint_queue:clear()
    self.items = {}
    self.active_index = 1
    self.state = "IDLE"
end

function waypoint_queue:set_active_index(index)
    local idx = tonumber(index)
    if not idx or idx < 1 or idx > #self.items then
        return false, "INVALID_INDEX"
    end
    self.active_index = idx
    self.state = "EN_ROUTE"
    return true
end

function waypoint_queue:check_arrival(craft_pos, override_radius)
    if self.state ~= "EN_ROUTE" or #self.items == 0 or not craft_pos then
        return false, self.state, nil, 0.0
    end
    local target = self:get_active()
    if not target then
        return false, "EMPTY_QUEUE", nil, 0.0
    end
    local dx = target.x - (craft_pos.x or 0.0)
    local dz = target.z - (craft_pos.z or 0.0)
    local d2d = math.sqrt(dx * dx + dz * dz)
    local rad = override_radius or self.arrivalRadius

    if d2d <= rad then
        target.completed = true
        if self.active_index < #self.items then
            self.active_index = self.active_index + 1
            return true, "ADVANCED", self.items[self.active_index], d2d
        else
            self.state = "COMPLETED"
            return true, "COMPLETED", target, d2d
        end
    end
    return false, "EN_ROUTE", target, d2d
end

function waypoint_queue:save(filepath)
    if not filepath or filepath == "" then
        return false, "NIL_FILEPATH"
    end
    local checkpoints = {}
    for _, wp in ipairs(self.items) do
        table.insert(checkpoints, {
            checkpointId = wp.checkpointId or ("WP_" .. tostring(wp.id)),
            action = wp.facilityId and "ACT_TKL_LAND_PREC" or "ACT_NAV_GOTO_WP",
            params = {
                targetPos = { x = wp.x, z = wp.z },
                targetAlt = wp.alt,
                cruiseSpeed = wp.speed,
                facilityId = wp.facilityId,
            },
            completed = wp.completed == true,
        })
    end
    local data = {
        version = "2.0.0",
        missionId = "ROUTE",
        executionMode = "SINGLE",
        checkpoints = checkpoints,
        active_index = self.active_index,
    }
    local raw = textutils.serializeJSON(data)
    local f, err = fs.open(filepath, "w")
    if not f then
        return false, err or "FS_WRITE_ERROR"
    end
    f.write(raw)
    f.close()
    return true
end

function waypoint_queue:load(filepath)
    if not filepath or not fs.exists(filepath) then
        return false, "FILE_NOT_FOUND"
    end
    local f = fs.open(filepath, "r")
    if not f then
        return false, "FS_OPEN_ERROR"
    end
    local raw = f.readAll()
    f.close()
    local data = textutils.unserializeJSON(raw)
    if type(data) ~= "table" then
        return false, "PARSE_ERROR"
    end
    if data.items ~= nil or data.version == "1.0.0" or type(data.checkpoints) ~= "table" then
        return false, "SCHEMA_INVALID"
    end
    local loaded = {}
    for i, cp in ipairs(data.checkpoints) do
        local p = type(cp.params) == "table" and cp.params or {}
        local pos = type(p.targetPos) == "table" and p.targetPos or p
        table.insert(loaded, {
            id = i,
            checkpointId = cp.checkpointId,
            x = pos.x or 0,
            z = pos.z or 0,
            alt = p.targetAlt or self.defaultAlt,
            speed = p.cruiseSpeed or self.defaultSpeed,
            facilityId = p.facilityId or p.designatedFacilityId,
            completed = cp.completed == true,
        })
    end
    self.items = loaded
    self.active_index = tonumber(data.active_index) or 1
    self.state = (#self.items > 0) and "EN_ROUTE" or "IDLE"
    return true
end

return waypoint_queue
