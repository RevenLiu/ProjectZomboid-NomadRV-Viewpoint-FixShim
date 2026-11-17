-- Nomad RV Viewpoint Shim
--
-- Why this exists:
--   On Viewpoint 0.1.7 the Java hook deadworks.vehicles.Hooks$DriveCamera fails to
--   attach (Viewpoint changed viewpoint.camera.CameraView.place to take a CameraShot
--   instead of two floats), so DWVView.vehicle() returns nil and DWVView.fixture()
--   returns -1 for every van, in every state. DeadWorks Vehicle Framework builds the
--   "Sit in driver seat", door and steps options on top of those two calls, so they
--   all disappear, and the E key does nothing.
--
--   This addon may only ever fail softly: DWVF's menu fills run inside Viewpoint's
--   interaction gathering, so an error here would blank Viewpoint's whole menu.
--   Every entry point below is wrapped in pcall for that reason.
--
-- Aim: none, and no guessing either.
--   A test session proved Viewpoint.Mouse never returns worldX/Y/Z (the crosshair
--   pick is only refreshed for things Viewpoint itself targets), and Viewpoint
--   exposes no camera yaw/pitch to Lua, so a mod cannot read the crosshair today.
--   Position alone cannot read intent either - the stairs and the door share the same
--   spot, so any distance rule retracts the stairs when you meant to open the door.
--   So each action gets its own key. Nothing is printed on screen.
--
-- Keys:
--   E          inside: sit on the seat you stand at, else work the door you stand at
--              outside: the entry door
--   Shift + E  the entry steps, inside the cabin as well as outside
--
-- Install: drop GridRVShim next to your other mods and enable it.

local DEBUG = true

-- a held key repeats; do not let one press flap a door open and shut
local REPEAT_MS = 220

local REACH_INSIDE = 1.6

local function log(...)
    if not DEBUG then return end
    local t = {}
    for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
    print("[GridRVShim] " .. table.concat(t, " "))
end

local function call(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, r = pcall(f, ...)
    if ok then return r end
    return nil
end

local function ready()
    return DWVF and DWVF.ready and call(DWVF.ready) == true
end

-- shortest XZ distance from a point to a profile box {x1,y1,z1,x2,y2,z2}
local function boxDistance(box, x, z)
    if type(box) ~= "table" or #box < 6 then return math.huge end
    local x1, x2 = math.min(box[1], box[4]), math.max(box[1], box[4])
    local z1, z2 = math.min(box[3], box[6]), math.max(box[3], box[6])
    local dx = (x < x1) and (x1 - x) or ((x > x2) and (x - x2) or 0)
    local dz = (z < z1) and (z1 - z) or ((z > z2) and (z - z2) or 0)
    return math.sqrt(dx * dx + dz * dz)
end

-- the van the player belongs to, its raw profile, and whether they are inside it
local function vanOf(p)
    if not ready() then return nil end
    local inside = call(DWVCabin.inside, p) == true
    local v = inside and call(DWVCabin.active, p) or call(DWVCabin.nearest, p)
    if not v then return nil end
    local prof = call(DWVF.profile, v)
    if type(prof) ~= "table" then return nil end
    return v, prof, inside
end

local function entryDoor(prof)
    for _, a in ipairs(prof.anims or {}) do
        if a.door and a.id == "entry" and a.index then return a end
    end
    return nil
end

local warnedPosition = false

-- the player's position in van metres (works outside the van as well)
local function cabinPosition(p)
    local x, z = call(DWVCabin.x, p), call(DWVCabin.z, p)
    if type(x) ~= "number" or type(z) ~= "number" then
        if not warnedPosition then
            warnedPosition = true
            log("DWVCabin.x/z gave no number - E and the menu options stay off")
        end
        return nil
    end
    warnedPosition = false
    return x, z
end

-- inside: the seat or door you stand at
local function pickInside(x, z, prof)
    local kind, entry, best = nil, nil, REACH_INSIDE
    for _, a in ipairs(prof.anims or {}) do
        if a.door and a.index then
            local d = boxDistance(a.target, x, z)
            if d < best then kind, entry, best = "door", a, d end
        end
    end
    for _, s in ipairs(prof.seats or {}) do
        if s.seat then
            local d = boxDistance(s.target, x, z)
            if d < best then kind, entry, best = "seat", s, d end
        end
    end
    return kind, entry, best
end

local function act(p, v, kind, entry)
    if kind == "seat" then
        if v:isSeatOccupied(entry.seat) then
            log("seat", entry.seat, "is taken")
            return
        end
        log("board seat", entry.seat, entry.title or "")
        DWVFNetwork.board(p, v, entry.seat)
    elseif kind == "door" then
        log("toggle door", entry.index, entry.id or "")
        DWVF.tell(p, DWVDoors.toggle(p, v, entry.index))
    else
        log("toggle steps")
        DWVF.tell(p, DWVSteps.toggle(p, v))
    end
end

local lastBuild = ""

-- one option in both the right-click menu and the Viewpoint lens menu
-- (Viewpoint collects the same list for the van you are standing in)
local function build(playerNum, menu)
    local p = getSpecificPlayer(playerNum)
    if not p or p:getVehicle() then return end
    local v, prof, inside = vanOf(p)
    if not v or not inside then return end -- outside, DWVF's radial options already cover it
    local fx = call(DWVView.fixture, p)
    if type(fx) == "number" and fx >= 0 then return end -- DWVF works again, leave it alone

    local x, z = cabinPosition(p)
    if not x then return end
    local kind, entry = pickInside(x, z, prof)
    local state = (entry and kind) or "none"
    if state ~= lastBuild then
        lastBuild = state
        log("lens build", state, "fixture", tostring(fx), "at", string.format("%.2f %.2f", x, z))
    end
    if not entry then return end

    if kind == "seat" then
        local option = menu:addOption(getText("ContextMenu_DWVF_Sit", entry.title or ""), p,
            function(player) act(player, v, "seat", entry) end)
        if option and v:isSeatOccupied(entry.seat) then option.notAvailable = true end
    else
        local open = call(DWVDoors.target, v, entry.index)
        menu:addOption(getText(open and "ContextMenu_DWVF_Close" or "ContextMenu_DWVF_Open", entry.title or ""), p,
            function(player) act(player, v, "door", entry) end)
    end
end

-- never let an error escape into DWVF's fills / Viewpoint's menu gathering
local function fill(playerNum, menu, objects, test)
    if test then return end
    local ok, err = pcall(build, playerNum, menu)
    if not ok then log("menu skipped:", tostring(err)) end
end

local lastInteract = 0
local lastWhere = ""

local function interact()
    local p = getSpecificPlayer(0)
    if not p or p:getVehicle() then return end
    if not ready() then return end
    local fx = call(DWVView.fixture, p)
    if type(fx) == "number" and fx >= 0 then return end -- DWVF handles it again

    local v, prof, inside = vanOf(p)
    if not v then return end
    local x, z = cabinPosition(p)
    if not x then return end

    local where = string.format("%.2f %.2f", x, z)
    if where ~= lastWhere then
        lastWhere = where
        log("e: at", where, inside and "inside" or "outside")
    end

    -- shift always means the entry steps, inside the cabin as well as outside
    if call(function() return isShiftKeyDown() end) == true then
        act(p, v, "steps")
        return
    end

    if inside then
        local kind, entry = pickInside(x, z, prof)
        if entry then act(p, v, kind, entry) end
        return
    end

    -- outside: DWVCabin.nearest already decided we are standing at the van
    local door = entryDoor(prof)
    if door then act(p, v, "door", door) end
end

Events.OnKeyPressed.Add(function(key)
    if not call(function() return getCore():isKey(KeybindId.INTERACT, key) end) then return end
    local now = call(getTimestampMs) or 0
    if now - lastInteract < REPEAT_MS then return end
    lastInteract = now
    local ok, err = pcall(interact)
    if not ok then log("E skipped:", tostring(err)) end
end)

local installed = false
local function install()
    if installed or not (DWVF and DWVF.menu) then return end
    installed = true
    DWVF.menu(fill)
    log("installed")
end
Events.OnGameStart.Add(install)
Events.OnTick.Add(install)
