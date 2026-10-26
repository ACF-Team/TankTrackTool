
local fake = include( "tests/tanktracktool/helpers/fake_render.lua" )
local probe = include( "tests/tanktracktool/helpers/probe.lua" )

local fixtures = {}

fixtures.files = {
    "tanktracktool/client/render/autotracks.lua",
}

fixtures.side_y = 50

fixtures.values = {
    trackColor = "255 255 255 255",
    trackMaterial = "generic",
    trackWidth = 24,
    trackHeight = 3,
    trackGuideY = 0,
    trackGuideZ = 1.5,
    trackGrouser = 0,
    trackTension = 0.5,
    trackRes = 2,
    trackFlip = 0,
}

-- { x, z, radius } in the order the track wraps them, same as the auto entity's defaults
local roadwheels = {}
for i = 1, 5 do
    roadwheels[i] = { 100 - ( 200 / 6 ) * i, -22, 15 }
end

local function layout( rollers )
    local wheels = { { 100, 0, 10 } }
    for i = 1, #roadwheels do wheels[#wheels + 1] = roadwheels[i] end
    wheels[#wheels + 1] = { -100, 0, 10 }
    for i = 1, #rollers do wheels[#wheels + 1] = rollers[i] end
    return wheels
end

fixtures.layouts = {
    default = layout( { { -50, 0, 7.5 }, { 50, 0, 7.5 } } ),
    norollers = layout( {} ),
    rollers3 = layout( { { -66, 0, 7.5 }, { 0, 0, 7.5 }, { 66, 0, 7.5 } } ),
}

fixtures.roadwheels = { 2, 3, 4, 5, 6 }
fixtures.ground = -40


function fixtures.load()
    local backend = fake.new()
    local tanktracktool = backend:loadTankTrackTool( fixtures.files )
    return backend, tanktracktool.autotracks
end


local track_meta = {}
track_meta.__index = track_meta

function fixtures.track( backend, autotracks, opts )
    opts = opts or {}

    local values = table.Copy( fixtures.values )
    for k, v in pairs( opts.values or {} ) do values[k] = v end

    local mirror = opts.mirror ~= false
    local parts = {}
    for i, w in ipairs( opts.wheels or fixtures.layouts[opts.layout or "default"] ) do
        local part = { radius = w[3], [1] = Vector( w[1], fixtures.side_y, w[2] ) }
        if mirror then part[2] = Vector( w[1], -fixtures.side_y, w[2] ) end
        parts[i] = { index = i, part }
    end

    local ent = {
        autotracks_trackvalues = values,
        autotracks_isdouble = mirror,
        autotracks_le_lastvel = 0,
        autotracks_le_lastrot = 0,
        autotracks_ri_lastvel = 0,
        autotracks_ri_lastrot = 0,
        tanktracktool_modeData = { parts = parts, data = {} },
    }
    local matrix = opts.matrix or Matrix()
    function ent:GetWorldTransformMatrix() return Matrix( matrix ) end

    return setmetatable( { backend = backend, autotracks = autotracks, ent = ent, values = values, mirror = mirror, matrix = matrix }, track_meta )
end

function track_meta:setup()
    self.autotracks.setup( self.ent )
    return self
end

function track_meta:think()
    self.autotracks.think( self.ent )
    return self
end

function track_meta:render( matrix )
    self.autotracks.render( self.ent, matrix or self.matrix )
end

function track_meta:frame( matrix )
    return self.backend:capture( function() self:render( matrix ) end )
end

function track_meta:build()
    return self:setup():think()
end

function track_meta:setVelocity( left, right )
    self.ent.autotracks_le_lastvel = left or 0
    self.ent.autotracks_ri_lastvel = right or 0
end

function track_meta:count()
    return #self.ent.tanktracktool_modeData.parts
end

function track_meta:wheel( i, side )
    local part = self.ent.tanktracktool_modeData.parts[i][1]
    return Vector( part[side or 1] ), part.radius
end

function track_meta:moveWheel( i, offset, side )
    local part = self.ent.tanktracktool_modeData.parts[i][1]
    if side ~= 2 then part[1] = part[1] + offset end
    if side ~= 1 and part[2] then part[2] = part[2] + offset end
end

function track_meta:groundHeight( i )
    return self.ent.tanktracktool_modeData.parts[i][1].trackHeight
end

function track_meta:sides()
    return self.mirror and { 1, 2 } or { 1 }
end

function track_meta:contactFailures( frame, tolerance )
    local fails = {}
    local width = self.values.trackWidth
    for _, side in ipairs( self:sides() ) do
        for i = 1, self:count() do
            local center, radius = self:wheel( i, side )
            for _, offset in ipairs( { 0.3, -0.3 } ) do
                local d = probe.clearance( frame, center, offset * width )
                if not d or math.abs( d - radius ) > tolerance then
                    fails[#fails + 1] = string.format( "side %d wheel %d y offset %+.1f: track is %s from the center, radius is %.2f",
                        side, i, offset, d and string.format( "%.3f", d ) or "nowhere", radius )
                end
            end
        end
    end
    return table.concat( fails, "\n" )
end

return fixtures
