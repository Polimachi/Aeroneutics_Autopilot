-- Fixed-capacity O(1) circular ring buffer for FDR RING_BUFFER mode.
local ring_buffer = {}

--- Initialize a bounded ring buffer.
-- @param cap number Maximum retained entries (default 1500).
-- @return table
function ring_buffer.init(cap)
    local capacity = math.max(1, math.floor(tonumber(cap) or 1500))
    return {
        capacity = capacity,
        items = {},
        head = 1,
        tail = 0,
        count = 0,
        droppedCount = 0,
    }
end

--- Append an entry, overwriting oldest when full.
-- @param buf table
-- @param entry table
-- @return boolean
function ring_buffer.push(buf, entry)
    if type(buf) ~= "table" or entry == nil then
        return false
    end
    buf.tail = (buf.tail % buf.capacity) + 1
    if buf.count >= buf.capacity then
        buf.items[buf.tail] = entry
        buf.head = (buf.head % buf.capacity) + 1
        buf.droppedCount = buf.droppedCount + 1
    else
        buf.items[buf.tail] = entry
        buf.count = buf.count + 1
    end
    return true
end

function ring_buffer.len(buf)
    return (buf and buf.count) or 0
end

function ring_buffer.capacity(buf)
    return (buf and buf.capacity) or 0
end

function ring_buffer.dropped(buf)
    return (buf and buf.droppedCount) or 0
end

--- Return chronological (oldest-to-newest) shallow copy of buffered items.
-- @param buf table
-- @return table
function ring_buffer.snapshot(buf)
    local out = {}
    if not buf or buf.count == 0 then
        return out
    end
    local idx = buf.head
    for i = 1, buf.count do
        out[i] = buf.items[idx]
        idx = (idx % buf.capacity) + 1
    end
    return out
end

--- Reset buffer contents and drop counter.
-- @param buf table
function ring_buffer.clear(buf)
    if not buf then return end
    buf.items = {}
    buf.head = 1
    buf.tail = 0
    buf.count = 0
    buf.droppedCount = 0
end

return ring_buffer
