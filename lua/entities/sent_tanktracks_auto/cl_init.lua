
include( "shared.lua" )

DEFINE_BASECLASS( "base_tanktracktool" )

local tanktracktool = tanktracktool

local math, util, string, table, render =
      math, util, string, table, render

local next, pairs, FrameTime, Entity, IsValid, EyePos, EyeVector, Vector, Angle, Matrix, WorldToLocal, Lerp, LerpVector =
      next, pairs, FrameTime, Entity, IsValid, EyePos, EyeVector, Vector, Angle, Matrix, WorldToLocal, Lerp, LerpVector

local sin, atan, icos = tanktracktool.util.sin, tanktracktool.util.atan, tanktracktool.util.icos


--[[
    netvar hooks
]]
local hooks = {}

hooks.editor_open = function( self, editor )
    for k, cat in pairs( editor.Categories ) do
        cat:SetExpanded( true )
    end
end

hooks.netvar_set = function( self )
    self.tanktracktool_reset = true
end
local function sameValues( a, b )
    for k, v in pairs( a ) do
        local w = b[k]
        if istable( v ) then
            if not istable( w ) or not sameValues( v, w ) then return false end
        elseif v ~= w then
            return false
        end
    end
    for k in pairs( b ) do
        if a[k] == nil then return false end
    end
    return true
end

-- coming back into view resends everything, usually unchanged
hooks.netvar_syncData = function( self, values )
    local last = self.tanktracktool_values
    self.tanktracktool_values = values
    if last and sameValues( last, values ) then return end
    self.tanktracktool_reset = true
end

function ENT:netvar_callback( id, ... )
    if hooks[id] then hooks[id]( self, ... ) end
end


--[[
    base ent
]]
local math_sqrt, math_atan2, math_min, math_max, math_abs, math_exp = math.sqrt, math.atan2, math.min, math.max, math.abs, math.exp
local math_deg = 180 / math.pi

local util_TraceHull = util.TraceHull

local _tmat = Matrix()

-- the hull frame, unpacked once per think by loadFrame
local f11, f12, f13, f14, f21, f22, f23, f24, f31, f32, f33, f34

local function loadFrame( matrix )
    f11, f12, f13, f14, f21, f22, f23, f24, f31, f32, f33, f34 = matrix:Unpack()
end

local function frameToWorld( x, y, z )
    return f14 + f11 * x + f12 * y + f13 * z, f24 + f21 * x + f22 * y + f23 * z, f34 + f31 * x + f32 * y + f33 * z
end

-- world direction to hull local
local function frameToLocal( x, y, z )
    return x * f11 + y * f21 + z * f31, x * f12 + y * f22 + z * f32, x * f13 + y * f23 + z * f33
end

-- same angles as VMatrix:GetAngles, written into ang
local function setMatrixAngles( ang, m11, m21, m31, m12, m22, m32, m33 )
    local xy = math_sqrt( m11 * m11 + m21 * m21 )
    if xy > 0.001 then
        ang:SetUnpacked( math_deg * math_atan2( -m31, xy ), math_deg * math_atan2( m21, m11 ), math_deg * math_atan2( m32, m33 ) )
    else
        ang:SetUnpacked( math_deg * math_atan2( -m31, xy ), math_deg * math_atan2( -m12, m22 ), 0 )
    end
end

local function readTMat( pos, ang )
    local m11, m12, m13, m14, m21, m22, m23, m24, m31, m32, m33, m34 = _tmat:Unpack()
    if pos then pos:SetUnpacked( m14, m24, m34 ) end
    if ang then setMatrixAngles( ang, m11, m21, m31, m12, m22, m32, m33 ) end
end

-- LocalToWorld into existing objects
local function toWorld( matrix, lpos, lang, pos, ang )
    _tmat:Set( matrix )
    if lpos then _tmat:Translate( lpos ) end
    if lang then _tmat:Rotate( lang ) end
    readTMat( pos, ang )
end

local function setupTrace( trace )
    if not trace.output then
        trace.output, trace.start, trace.endpos = {}, Vector(), Vector()
    end
    return trace
end

-- how far one side moved along the hull since last frame, y is its offset to the left
local function sideScroll( controller, key, brake, scroll, y )
    local px, py, pz = f14 + f12 * y, f24 + f22 * y, f34 + f32 * y

    -- not a Vector, float rounding made parked tanks scroll and kick up dust
    local last = controller[key]
    if not last then
        last = { px, py, pz }
        controller[key] = last
    end

    local vel = 0

    if not controller:GetNW2Bool( brake, false ) then
        local override = controller:GetNW2Float( scroll, 0 )
        if override ~= 0 then
            vel = -override
        else
            vel = f11 * ( last[1] - px ) + f21 * ( last[2] - py ) + f31 * ( last[3] - pz )
        end
    end

    last[1], last[2], last[3] = px, py, pz

    return vel
end

local function updateScroll( controller, values, isdouble )
    local vel_le = sideScroll( controller, "autotracks_le_last", "netwire_leftBrake", "netwire_leftScroll", values.suspensionY )
    controller.autotracks_le_lastvel = vel_le

    if not isdouble then return vel_le * 360, 0 end

    local vel_ri = sideScroll( controller, "autotracks_ri_last", "netwire_rightBrake", "netwire_rightScroll", -values.suspensionY )
    controller.autotracks_ri_lastvel = vel_ri

    return vel_le * 360, vel_ri * 360
end

-- the wheels trace again once the hull has moved this far, or this long after the last trace
local trace_move = 0.25
local trace_wait = 0.2

-- how far out from the hull origin a rotation is measured
local trace_reach = 128

-- torsion arms settle over a few traced frames
local trace_settle = 10

-- moving tanks trace this often, in between the wheels land on the ground the last trace found
local trace_rate = 1 / 30

-- slow or parked tanks trace less often, returns whether to trace and whether the hull moved at all
local function traceDue( data, id )
    local last = data.traced
    if not last then
        -- spread over the interval so tanks don't all trace on the same frame
        last = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, settle = 0, time = 0, due = 0, phase = ( id * 0.618034 ) % 1 }
        data.traced = last
    end

    local move = math_abs( f14 - last[4] ) + math_abs( f24 - last[8] ) + math_abs( f34 - last[12] )
        + trace_reach * ( math_abs( f11 - last[1] ) + math_abs( f21 - last[5] ) + math_abs( f31 - last[9] )
        + math_abs( f12 - last[2] ) + math_abs( f22 - last[6] ) + math_abs( f32 - last[10] )
        + math_abs( f13 - last[3] ) + math_abs( f23 - last[7] ) + math_abs( f33 - last[11] ) )

    local now = CurTime()
    if last.settle >= trace_settle then
        if move < trace_move then
            if now < last.time + trace_wait then return false, move > 0 end
        elseif now < last.due then
            return false, true
        end
    end

    last[1], last[2], last[3], last[4] = f11, f12, f13, f14
    last[5], last[6], last[7], last[8] = f21, f22, f23, f24
    last[9], last[10], last[11], last[12] = f31, f32, f33, f34
    last.time = now
    if last.settle == trace_settle - 1 then
        last.due = now + trace_rate * last.phase
    else
        last.due = math_max( last.due + trace_rate, now )
    end
    last.settle = last.settle + 1

    return true, true
end

local function setRenderBounds( self )
    self:autotracks_setMatrix()
    local rendermin, rendermax = Vector( 0, 0, -self.netvar.values.suspensionZ ), Vector( 0, 0, self.netvar.values.suspensionZ )
    local renderpos, renderang = self:autotracks_getMatrix()

    renderpos, renderang = WorldToLocal( self:GetPos(), self:GetAngles(), renderpos, renderang )
    tanktracktool.util.calcbounds( rendermin, rendermax, renderpos )

    for i = 1, #self.tanktracktool_modeData.parts do
        local wheel = self.tanktracktool_modeData.parts[i][1]
        tanktracktool.util.calcbounds( rendermin, rendermax, wheel[1] + wheel.maxs )
        if self.autotracks_isdouble then
            tanktracktool.util.calcbounds( rendermin, rendermax, wheel[2] + wheel.mins )
        end
    end

    self.rendermin = rendermin
    self.rendermax = rendermax
    self:SetRenderBounds( self.rendermin, self.rendermax )
end

local modes = { classic = tanktracktool.render.mode( true ), torsion = tanktracktool.render.mode( true ), bogie = tanktracktool.render.mode( true ) }

function ENT:autotracks_setMatrix()
    local parent1 = self:GetParent()
    if parent1 and parent1:IsValid() then
        local parent2 = parent1:GetParent()
        if parent2 and parent2:IsValid() then
            parent1 = parent2
        end
    else
        parent1 = self
    end

    local base = parent1
    local axis = self:GetNW2Entity( "netwire_axisEntity" )

    if base == NULL then base = self end
    if axis == NULL then axis = self end

    local matrix = self.autotracks_matrix
    if not matrix then
        self.autotracks_matrix = Matrix()
        matrix = self.autotracks_matrix
    end

    -- SetAngles keeps the old scale, which drifts a bit every frame
    matrix:Identity()
    matrix:SetTranslation( base:GetPos() )
    matrix:SetAngles( axis:GetAngles() )
end

function ENT:autotracks_getMatrix()
    if not self.autotracks_matrix then
        return self:GetPos(), self:GetAngles()
    end
    return self.autotracks_matrix:GetTranslation(), self.autotracks_matrix:GetAngles()
end

--[[
    ground dust, one particle system per side moved through its control points
]]
local _dustpos = Vector()
local _dustvalue = Vector()

-- where each side touched the ground on the last traced frame
local function getContact( data )
    local contact = data.contact
    if not contact then
        contact = { { traces = 0, hits = 0 }, { traces = 0, hits = 0 } }
        data.contact = contact
    end
    return contact
end

local function contactReset( contact )
    for side = 1, 2 do
        local c = contact[side]
        c.traces, c.hits, c.rear, c.front = 0, 0, math.huge, -math.huge
    end
end

local function contactAdd( c, result )
    c.traces = c.traces + 1
    if not result.Hit then return end

    c.hits = c.hits + 1

    -- kept in hull space so it moves with the hull between traces
    local hx, hy, hz = result.HitPos:Unpack()
    local x, y, z = frameToLocal( hx - f14, hy - f24, hz - f34 )
    if x < c.rear then c.rear, c.rx, c.ry, c.rz = x, x, y, z end
    if x > c.front then c.front, c.fx, c.fy, c.fz = x, x, y, z end
end

-- where a wheel dropped from s meets the ground, traced or on the plane the last trace hit
local function groundHit( trace, sx, sy, sz, len, contact, real )
    local ex, ey, ez = sx - f13 * len, sy - f23 * len, sz - f33 * len

    if real then
        trace.start:SetUnpacked( sx, sy, sz )
        trace.endpos:SetUnpacked( ex, ey, ez )

        local result = util_TraceHull( trace )
        contactAdd( contact, result )

        local hx, hy, hz = result.HitPos:Unpack()
        trace.frac = result.Fraction
        if result.Hit and not result.StartSolid then
            local nx, ny, nz = result.HitNormal:Unpack()
            trace.nx, trace.ny, trace.nz, trace.d = nx, ny, nz, nx * hx + ny * hy + nz * hz
        else
            trace.d = nil
        end
        return hx, hy, hz
    end

    local t = trace.frac or 1
    local d = trace.d
    if d then
        local nx, ny, nz = trace.nx, trace.ny, trace.nz
        local ds = nx * sx + ny * sy + nz * sz - d
        local de = nx * ex + ny * ey + nz * ez - d
        if ds > 0 then t = de < 0 and ds / ( ds - de ) or 1 end
    end
    return sx + ( ex - sx ) * t, sy + ( ey - sy ) * t, sz + ( ez - sz ) * t
end

local function stopDust( self )
    local dust = self.autotracks_dust
    if not dust then return end
    for side = 1, 2 do
        if IsValid( dust[side] ) then dust[side]:StopEmission() end
    end
    self.autotracks_dust = nil
end

-- tanks that stop thinking (off screen, disabled) stop kicking up dust
local function idleDust( self )
    local dust = self.autotracks_dust
    if not dust then return end
    for side = 1, 2 do
        if IsValid( dust[side] ) then dust[side]:SetControlPoint( 2, vector_origin ) end
    end
end

local function updateDust( controller, side, vel, values, c )
    local dust = controller.autotracks_dust
    local fx = dust and dust[side]

    local effscale = values.systemEffScale or 0

    -- smoothed, the hull's position can arrive in steps and the raw speed jumps between 0 and a lot
    local smooth = controller.autotracks_dust_speed
    if not smooth then
        smooth = { 0, 0 }
        controller.autotracks_dust_speed = smooth
    end

    local ft = math_max( FrameTime(), 0.001 )
    local speed = smooth[side] + ( math_abs( vel ) / ft - smooth[side] ) * ( 1 - math_exp( -ft / 0.3 ) )
    smooth[side] = speed

    if effscale <= 0 or c.hits == 0 or speed < 5 then
        if IsValid( fx ) then fx:SetControlPoint( 2, vector_origin ) end
        return
    end

    _dustpos:SetUnpacked( frameToWorld( c.rx, c.ry, c.rz ) )

    if not IsValid( fx ) then
        if not dust then
            dust = { light = { 0, 0 } }
            controller.autotracks_dust = dust
            controller:CallOnRemove( "tanktracktool_dust", stopDust )
        end
        fx = CreateParticleSystemNoEntity( "tanktracktool_dust", _dustpos )
        if not IsValid( fx ) then return end
        dust[side] = fx
        dust.light[side] = 0
    end

    fx:SetControlPoint( 0, _dustpos )
    _dustpos:SetUnpacked( frameToWorld( c.fx, c.fy, c.fz ) )
    fx:SetControlPoint( 1, _dustpos )

    local width = values.trackEnable and values.trackWidth or values.wheelWidth
    _dustvalue:SetUnpacked( math_min( 1, speed / 200 ) * c.hits / c.traces, math_min( width * effscale, 0.05 * speed ), 0 )
    fx:SetControlPoint( 2, _dustvalue )

    -- the light under the tank, sampled a few times a second
    local now = CurTime()
    if dust.light[side] < now then
        dust.light[side] = now + 0.25

        local r, g, b = render.GetLightColor( _dustpos ):Unpack()
        _dustvalue:SetUnpacked( 255 * math_min( 1, ( r * 2 ) ^ 0.4545 ), 255 * math_min( 1, ( g * 2 ) ^ 0.4545 ), 255 * math_min( 1, ( b * 2 ) ^ 0.4545 ) )
        fx:SetControlPoint( 3, _dustvalue )
    end
end

function ENT:Think()
    idleDust( self )

    if tanktracktool.disable_autotracks then
        self.tanktracktool_reset = true
        return
    end

    BaseClass.Think( self )

    if self:IsDormant() then
        return
    end

    if self.tanktracktool_reset then
        self.tanktracktool_reset = nil

        local values = self.netvar.values
        if not values then return end
        self.tanktracktool_values = values

        self.autotracks_dotracks = values.trackEnable ~= 0
        self.autotracks_isdouble = values.systemMirror ~= 0
        self.autotracks_le_lastvel = self.autotracks_le_lastvel or 1
        self.autotracks_le_lastrot = self.autotracks_le_lastrot or 1
        self.autotracks_ri_lastvel = self.autotracks_ri_lastvel or 1
        self.autotracks_ri_lastrot = self.autotracks_ri_lastrot or 1
        self:autotracks_setMatrix()

        self.tanktracktool_mode = modes[values.suspensionType] or nil
        if self.tanktracktool_mode then
            self.tanktracktool_mode = self.tanktracktool_mode:init( self )

            if self.autotracks_dotracks then
                self.autotracks_trackvalues = {
                    trackColor = values.trackColor,
                    trackMaterial = values.trackMaterial,
                    trackWidth = values.trackWidth,
                    trackHeight = values.trackHeight,
                    trackGuideY = values.trackGuideY,
                    trackGuideZ = values.trackGuideZ,
                    trackGrouser = values.trackGrouser,
                    trackTension = values.trackTension,
                    trackRes = values.trackRes,
                }

                tanktracktool.autotracks.setup( self )
                tanktracktool.autotracks.think( self )
            end

            setRenderBounds( self )
        end
    end

    if self.tanktracktool_mode and self.tanktracktool_visible then
        self.tanktracktool_visible = nil
        self:autotracks_setMatrix()
        self.tanktracktool_mode:think( self )

        if self.autotracks_dotracks then
            tanktracktool.autotracks.think( self )
        end
    end
end

function ENT:Draw( flags )
    self:DrawModel( flags )

    if tanktracktool.disable_autotracks then return end

    if self.tanktracktool_mode then
        self.tanktracktool_visible = true
        self.tanktracktool_mode:draw( self )

        -- if self.autotracks_dotracks then
        --     tanktracktool.autotracks.render( self, self.autotracks_matrix )
        -- end
    end
end


--[[
    classic mode
]]
do
    modes.classic:addCSent( "wheel_road", "wheel_roller" )

    function modes.classic:onInit( controller )
        local isdouble = controller.autotracks_isdouble
        local values = controller.netvar.values
        local parts = self:getParts( controller )
        local data = self:getData( controller )

        local xgap = values.suspensionX / ( values.wheelCount - 1 )
        local xpos = values.systemOffsetX
        local ypos = values.systemOffsetY
        local zpos = values.systemOffsetZ

        data.numroadwheels = 0
        data.lastroadwheel = 0
        data.isdouble = isdouble

        for i = 1, values.wheelCount do
            local assem = self:addAssembly( controller, i == 1 and 1 or i == 2 and values.wheelCount or i - 1 )

            local wheel = assem:addPart( controller, "wheel_road" )
            wheel:setnodraw( false, not isdouble )

            local specs = {
                whnBodygroup = values.whnBodygroup[i],
                whnColor = values.whnColor[i],
                whnMaterial = values.whnMaterial[i],
                whnModel = values.whnModel[i],
                whnOffsetX = values.whnOffsetX[i],
                whnOffsetY = values.whnOffsetY[i],
                whnOffsetZ = values.whnOffsetZ[i],
                whnOverride = values.whnOverride[i],
                whnRadius = values.whnRadius[i],
                whnSuspension = values.whnSuspension[i],
                whnTraceZ = values.whnTraceZ[i],
                whnWidth = values.whnWidth[i],
            }

            wheel.specs = specs
            wheel.useTable = specs.whnOverride ~= 0
            local override = wheel.useTable

            local fixed = tanktracktool.util.fixWheelModel(
                override and specs.whnModel or values.wheelModel,
                override and specs.whnBodygroup or values.wheelBodygroup,
                override and specs.whnMaterial or values.wheelMaterial,
                override and specs.whnRadius or values.wheelRadius,
                override and specs.whnWidth or values.wheelWidth
            )
            wheel.mins = fixed.mins
            wheel.maxs = fixed.maxs
            wheel.width = override and specs.whnWidth or values.wheelWidth
            wheel.radius = override and specs.whnRadius or values.wheelRadius
            wheel.circumference = math.max( 0.0001, 2 * math.pi * wheel.radius )

            wheel:setmodel( fixed.model )
            wheel:setscalemv( fixed.scalem, fixed.scalev )
            wheel:setbodygroup( fixed.bodygroup )
            wheel:setmaterial( fixed.material )
            wheel:setcolor( override and specs.whnColor or values.wheelColor )


            if specs.whnSuspension ~= 0 then
                wheel.suspension = true
            end

            -- interleaving alternately spaces the wheels on the y axis, disabled in bogie mode
            local interleave = 0
            if wheel.suspension and values.suspensionType ~= "bogie" then
                interleave = ( assem.index % 2 == 0 and 1 or -1 ) * values.suspensionInterleave
            end

            -- custom y axis spacing
            local clamp = values.trackEnable ~= 0 and values.trackWidth * 0.5 or wheel.width * 0.5
            local y_offset = math.Clamp( ( specs.whnOffsetY + interleave ) * clamp, -clamp, clamp )
            if y_offset ~= 0 then
                wheel.y_offset = y_offset
                wheel.scale_m:SetTranslation( Vector( 0, y_offset, 0 ) )
            end

            --
            if wheel.suspension then
                data.numroadwheels = data.numroadwheels + 1
                data.lastroadwheel = assem.index

                wheel.trace_len = values.suspensionZ - ( values.suspensionZ - wheel.radius ) * specs.whnTraceZ

                local maxs = Vector( wheel.radius, wheel.radius, 0 ) * 0.5
                local mins = -maxs

                wheel.le_trace = { mask = MASK_SOLID_BRUSHONLY, maxs = maxs, mins = mins }
                if isdouble then wheel.ri_trace = { mask = MASK_SOLID_BRUSHONLY, maxs = maxs, mins = mins } end

                wheel.le_poslocal.z = zpos

                wheel.spacing = specs.whnOffsetX * 0.5
                local pairgap = tanktracktool.util.map( values.suspensionPairGap, -1, 1, -0.5, 0.5 )
                wheel.spacing = wheel.spacing + ( assem.index % 2 == 0 and -pairgap or pairgap ) * ( 1 - ( wheel.spacing % 1 ) ) * 0.5
            else
                wheel.le_poslocal.z = zpos + math.max( -values.suspensionZ + wheel.radius, specs.whnOffsetZ )
                wheel.spacing = specs.whnOffsetX * 0.5
            end

            wheel.le_poslocal.x = xpos + values.suspensionX * 0.5 - xgap * ( assem.index - 1 ) + xgap * wheel.spacing
            --wheel.le_poslocal.x = xpos + values.suspensionX * 0.5 - xgap * ( assem.id - 1 ) + xgap * specs.whnOffsetX * 0.5
            wheel.le_poslocal.y = ypos + values.suspensionY * 0.5

            wheel[1] = Vector( wheel.le_poslocal ) -- this goes to the track mesh renderer

            if isdouble then
                wheel.ri_poslocal.x = wheel.le_poslocal.x
                wheel.ri_poslocal.y = ypos - values.suspensionY * 0.5
                wheel.ri_poslocal.z = wheel.le_poslocal.z
                wheel.ri_anglocal.y = 180

                wheel[2] = Vector( wheel.ri_poslocal )
            end
        end

        local wheel1 = self:getPart( controller, 1, 1 )--parts[1][1]
        local wheel2 = self:getPart( controller, values.wheelCount, 1 ) --parts[values.wheelCount][1]
        local wheelDiff = ( wheel1.le_poslocal - wheel2.le_poslocal ):Cross( Vector( 0, 1, 0 ) ):GetNormalized()

        for i = 1, values.rollerCount do
            local assem = self:addAssembly( controller, values.wheelCount + ( values.rollerCount - i + 1 ) )

            local roller = assem:addPart( controller, "wheel_roller" )
            roller:setnodraw( false, not isdouble )

            local specs = {
                ronBodygroup = values.ronBodygroup[i],
                ronColor = values.ronColor[i],
                ronMaterial = values.ronMaterial[i],
                ronModel = values.ronModel[i],
                ronOffsetX = values.ronOffsetX[i],
                ronOffsetY = values.ronOffsetY[i],
                ronOffsetZ = values.ronOffsetZ[i],
                ronOverride = values.ronOverride[i],
                ronRadius = values.ronRadius[i],
                ronWidth = values.ronWidth[i],
            }

            roller.specs = specs
            roller.useTable = specs.ronOverride ~= 0
            local override = roller.useTable

            local fixed = tanktracktool.util.fixWheelModel(
                override and specs.ronModel or values.rollerModel,
                override and specs.ronBodygroup or values.rollerBodygroup,
                override and specs.ronMaterial or values.rollerMaterial,
                override and specs.ronRadius or values.rollerRadius,
                override and specs.ronWidth or values.rollerWidth
            )
            roller.mins = fixed.mins
            roller.maxs = fixed.maxs
            roller.width = override and specs.ronWidth or values.rollerWidth
            roller.radius = override and specs.ronRadius or values.rollerRadius
            roller.circumference = math.max( 0.0001, 2 * math.pi * roller.radius )

            roller:setmodel( fixed.model )
            roller:setscalemv( fixed.scalem, fixed.scalev )
            roller:setbodygroup( fixed.bodygroup )
            roller:setmaterial( fixed.material )
            roller:setcolor( override and specs.ronColor or values.rollerColor )

            -- custom y axis spacing
            local clamp = values.trackEnable ~= 0 and values.trackWidth * 0.5 or roller.width * 0.5
            local y_offset = math.Clamp( specs.ronOffsetY * clamp, -clamp, clamp )
            if y_offset ~= 0 then
                roller.scale_m:SetTranslation( Vector( 0, y_offset, 0 ) )
            end

            --
            local lerp = LerpVector( ( i - 0.5 - specs.ronOffsetX * 0.5 ) / values.rollerCount, wheel1.le_poslocal, wheel2.le_poslocal )
            roller.le_poslocal.x = lerp.x
            roller.le_poslocal.y = lerp.y

            if values.rollerLocalZ ~= 0 then
                roller.le_poslocal.z = lerp.z
                roller.le_poslocal:Add( wheelDiff * ( specs.ronOffsetZ + values.rollerOffsetZ ) ) -- this needs to be clamped along this axis somehow
            else
                roller.le_poslocal.z = lerp.z + specs.ronOffsetZ + values.rollerOffsetZ
            end

            roller.le_poslocal.z = math.max( roller.le_poslocal.z, zpos - values.suspensionZ + roller.radius )
            roller[1] = Vector( roller.le_poslocal )

            if isdouble then
                roller.ri_poslocal.x = roller.le_poslocal.x
                roller.ri_poslocal.y = ypos - values.suspensionY * 0.5
                roller.ri_poslocal.z = roller.le_poslocal.z
                roller.ri_anglocal.y = 180
                roller[2] = Vector( roller.ri_poslocal )
            end
        end
    end

    -- drops a wheel onto the ground under poslocal, trackpos keeps where it landed in hull space
    local function traceWheel( wheel, trace, poslocal, trackpos, contact, real )
        local len, height = wheel.trace_len, wheel.trackHeight or wheel.radius

        local sx, sy, sz = frameToWorld( poslocal:Unpack() )
        local hx, hy, hz = groundHit( trace, sx, sy, sz, len, contact, real )
        hx, hy, hz = hx + f13 * height, hy + f23 * height, hz + f33 * height

        -- hacky localized vector used by the track renderer written for the old system, I hate it but I'm not redoing it
        trackpos:SetUnpacked( frameToLocal( hx - f14, hy - f24, hz - f34 ) )
    end

    function modes.classic:onThink( controller )
        local frame = controller.autotracks_matrix
        loadFrame( frame )

        local isdouble = controller.autotracks_isdouble
        local values = controller.netvar.values

        local rot_le, rot_ri = updateScroll( controller, values, isdouble )

        local data = self:getData( controller )
        local trace, moved = traceDue( data, controller:EntIndex() )
        if not trace and not moved and rot_le == 0 and rot_ri == 0 then return end

        local contact = getContact( data )
        if trace then contactReset( contact ) end

        local parts = self:getParts( controller )

        for i = 1, #parts do
            local wheel = parts[i][1]
            local enabled = wheel.suspension

            wheel.le_anglocal.p = wheel.le_anglocal.p - rot_le / wheel.circumference

            if enabled then
                traceWheel( wheel, setupTrace( wheel.le_trace ), wheel.le_poslocal, wheel[1], contact[1], trace )
                wheel.le_posworld:SetUnpacked( frameToWorld( wheel[1]:Unpack() ) )
                toWorld( frame, nil, wheel.le_anglocal, nil, wheel.le_angworld )
            else
                toWorld( frame, wheel.le_poslocal, wheel.le_anglocal, wheel.le_posworld, wheel.le_angworld )
            end

            if isdouble then
                wheel.ri_anglocal.p = wheel.ri_anglocal.p + rot_ri / wheel.circumference

                if enabled then
                    traceWheel( wheel, setupTrace( wheel.ri_trace ), wheel.ri_poslocal, wheel[2], contact[2], trace )
                    wheel.ri_posworld:SetUnpacked( frameToWorld( wheel[2]:Unpack() ) )
                    toWorld( frame, nil, wheel.ri_anglocal, nil, wheel.ri_angworld )
                else
                    toWorld( frame, wheel.ri_poslocal, wheel.ri_anglocal, wheel.ri_posworld, wheel.ri_angworld )
                end
            end
        end

        updateDust( controller, 1, controller.autotracks_le_lastvel, values, contact[1] )
        if isdouble then
            updateDust( controller, 2, controller.autotracks_ri_lastvel, values, contact[2] )
        end
    end

    function modes.classic:onDraw( controller, eyepos, eyedir, empty, flashlight )
        self:renderParts( controller, eyepos, eyedir, empty )
        if controller.autotracks_dotracks then
            tanktracktool.autotracks.render( controller, controller.autotracks_matrix )
        end

        if flashlight then
            render.PushFlashlightMode( true )
            self:renderParts( controller, eyepos, eyedir, empty )
            if controller.autotracks_dotracks then
                tanktracktool.autotracks.render( controller, controller.autotracks_matrix )
            end
            render.PopFlashlightMode()
        end
    end
end


--[[
    torsion bar mode
]]
do
    modes.torsion:addCSent( "wheel_road", "wheel_roller", "arm", "damper" )

    local render_multiply = "RenderMultiply"

    local function setupscale_damper( self, csent, left, controller )
        csent:EnableMatrix( render_multiply, self.bone0 )
        csent:ManipulateBonePosition( 1, self.bone1pos )
        csent:ManipulateBonePosition( 2, left and self.bone2pos_le or self.bone2pos_ri )
        csent:SetupBones()
    end

    local function setupscale_arm( self, csent, left, controller )
        csent:EnableMatrix( render_multiply, self.bone0 )
        if self.type == 1 then
            csent:ManipulateBoneScale( 1, self.bone1scale )
            csent:ManipulateBoneScale( 2, self.bone2scale )
            csent:ManipulateBoneScale( 4, self.bone4scale )
            csent:ManipulateBoneScale( 5, self.bone5scale )
            csent:ManipulateBonePosition( 2, self.bone2pos )
            csent:ManipulateBonePosition( 3, self.bone3pos )
            csent:ManipulateBonePosition( 5, self.bone5pos )
        elseif self.type == 2 then
            csent:ManipulateBonePosition( 1, self.bone1pos )
            csent:ManipulateBonePosition( 2, self.bone2pos )
            csent:ManipulateBonePosition( 3, self.bone3pos )
            csent:ManipulateBonePosition( 4, self.bone4pos )
        end
        csent:SetupBones()
    end

    function modes.torsion:onInit( controller )
        modes.classic.onInit( self, controller )

        local values = controller.netvar.values

        local xgap = values.suspensionX / ( values.wheelCount - 1 )
        local xpos = values.systemOffsetX
        local ypos = values.systemOffsetY
        local zpos = values.systemOffsetZ

        local data = self:getData( controller )
        local parts = self:getParts( controller )

        local isdouble = data.isdouble

        for i = 1, values.wheelCount do
            local assem = parts[i == 1 and 1 or i == 2 and values.wheelCount or i - 1]
            local wheel = assem[1]

            if not wheel or not wheel.suspension then
                goto CONTINUE
            end

            local specs = wheel.specs

            local arm = assem:addPart( controller, "arm" )
            arm:setnodraw( false, not isdouble )

            if values.suspensionType == "torsion" then arm.type = 1 elseif values.suspensionType == "bogie" then arm.type = 2 end
            if data.numroadwheels % 2 ~= 0 and assem.index == data.lastroadwheel then arm.type = 1 end

            arm:setcolor( values.suspensionColor )
            arm:setmaterial( values.suspensionMaterial )

            arm.barangle = values.suspensionTAngle

            arm.barsize = values.suspensionTSize
            arm.barlengthbeam = values.suspensionTBeam
            arm.barlengthaxle = values.suspensionTAxle
            arm.barlengthconn = values.suspensionTConn

            local xmove = 0
            if arm.type == 1 then
                local interleave = values.suspensionInterleave
                local w = values.trackEnable ~= 0 and values.trackWidth or wheel.width

                local addlength = 0
                if interleave > 0 then
                    if assem.index % 2 == 0 then
                        addlength = interleave * w
                        arm.barlengthconn = arm.barlengthconn - arm.barsize * 0.5
                    else
                        addlength = -interleave * w
                    end
                elseif interleave < 0 then
                    if assem.index % 2 ~= 0 then
                        addlength = -interleave * w
                        arm.barlengthconn = arm.barlengthconn - arm.barsize * 0.5
                    else
                        addlength = interleave * w
                    end
                end

                arm:setmodel( "models/tanktracktool/torsionbar1.mdl" )

                arm.bone0 = Matrix()
                arm.bone0:SetScale( Vector( arm.barsize, arm.barsize / 2, arm.barsize ) )
                arm.bone0:SetAngles( Angle( 0, 180, 0 ) )

                local offset = wheel.width * 0.5 - ( wheel.y_offset or 0 ) + arm.barlengthaxle + math.max( 0, addlength + arm.barsize * 0.5 )
                if offset ~= 0 then
                    arm.bone0:SetTranslation( Vector( 0, -offset, 0 ) )
                end

                local connrad = ( values.suspensionTConnRad * arm.barsize * 1 ) / arm.barsize
                arm.bone1scale = Vector( 1, connrad, connrad )
                arm.bone2scale = Vector( 1, connrad, connrad )

                arm.bone2pos = Vector( -1 + ( 2 * arm.barlengthconn ) / arm.barsize, 0, 0 )
                arm.bone3pos = Vector( 0, -2 + arm.barlengthbeam / arm.barsize, 0 )

                local axlerad = ( values.suspensionTAxleRad * arm.barsize * 1 ) / arm.barsize
                arm.bone4scale = Vector( 1, axlerad, axlerad )
                arm.bone5scale = Vector( 1, axlerad, axlerad )

                arm.bone5pos = Vector( -( offset * 2 - arm.barsize - wheel.width * 0.75 + addlength ) / arm.barsize, 0, 0 )

                if offset + arm.barlengthconn > values.suspensionY * 0.5 then
                    xmove = arm.barsize * values.suspensionTConnRad * 0.25 + 0.125
                end
            else
                arm.csent = controller.tanktracktool_modeData_csents["bogie"]
                arm:setmodel( "models/tanktracktool/bogie1.mdl" )

                arm.barlengthbeam = math.max( wheel.radius, arm.barlengthbeam )
                if i % 2 ~= 0 then arm.barangle = -arm.barangle end

                local size = arm.barsize * 1.5

                arm.bone0 = Matrix()
                arm.bone0:SetScale( Vector( size, size / 2, size ) )
                arm.bone0:SetAngles( Angle( 0, 180, 0 ) )

                local offset = -( wheel.y_offset or 0 )
                if offset ~= 0 then
                    arm.bone0:SetTranslation( Vector( 0, -offset, 0 ) )
                end

                arm.bone1pos = Vector( wheel.width / size, 0, 0 )
                arm.bone2pos = Vector( 0, -2 + arm.barlengthbeam / size, 0 )
                arm.bone3pos = Vector( -wheel.width / size, 0, 0 )
                arm.bone4pos = Vector( 0, -2 + arm.barlengthbeam / size, 0 )
            end

            arm.setupscale = setupscale_arm

            --
            local x = xpos + xgap * wheel.spacing + values.suspensionX * 0.5 - xgap * ( assem.index - 1 )
            local z = zpos - values.suspensionZ + ( values.suspensionZ - wheel.radius ) * specs.whnTraceZ + wheel.radius

            local normal = Vector( 0, 0, 1 )
            normal:Rotate( Angle( arm.barangle, 0, 0 ) )
            normal:Mul( values.suspensionTBeam )

            --
            arm.le_anglocal = Angle( values.suspensionTAngle + 180, 0, 0 )
            arm.le_poslocal = Vector( x - xmove, ypos + values.suspensionY * 0.5, z )
            arm.le_poslocal:Add( normal )

            arm.le_offsetX = Vector()
            arm.le_offsetK = sin( arm.barangle ) * arm.barlengthbeam
            arm.le_origin = Vector( wheel.le_poslocal )

            wheel.le_poslocal = Vector( 0, 0, arm.barlengthbeam )

            if isdouble then
                arm.ri_anglocal = Angle( -values.suspensionTAngle + 180, 180, 0 )
                arm.ri_poslocal = Vector( x + xmove, ypos - values.suspensionY * 0.5, z )
                arm.ri_poslocal:Add( normal )

                arm.ri_offsetX = Vector()
                arm.ri_offsetK = sin( arm.barangle ) * arm.barlengthbeam
                arm.ri_origin = Vector( wheel.ri_poslocal )

                wheel.ri_poslocal = Vector( 0, 0, arm.barlengthbeam )
                wheel.ri_anglocal.y = 0
            end

            -- dampers
            if values.suspensionTDamp ~= 0 then
                if assem.index % values.suspensionTDamp == 0 then
                    local damper = assem:addPart( controller, "damper" )
                    damper:setnodraw( false, not isdouble )

                    damper:setmodel( "models/tanktracktool/spring1.mdl" )
                    damper.color = arm.color
                    damper.material = arm.material

                    damper.bone0 = Matrix()
                    damper.bone0:SetScale( Vector( arm.barsize, arm.barsize, arm.barsize ) )
                    damper.bone0:SetAngles( Angle( 0, 180, 0 ) )

                    if arm.type == 1 then
                        damper.bone0:SetTranslation( arm.bone0:GetTranslation() )
                        damper.bone0:Translate( Vector( 0, 0.25, 0 ) )
                    else
                        damper.bone0:SetTranslation( arm.bone0:GetTranslation() )
                        damper.bone0:Translate( Vector( 0, ( wheel.width * 0.5 + arm.barsize ) / arm.barsize - 0.125, 0 ) )
                    end

                    local length = 0.5 * values.suspensionZ * ( 1 - values.suspensionTDampZ )

                    damper.zlength = ( ( values.suspensionZ * values.suspensionTDampZ ) / 4 ) / arm.barsize
                    damper.bone1pos = Vector( 0, damper.zlength - 2, 0 )
                    damper.bone2pos_le = Vector( 0, 0, 0 )

                    damper.setupscale = setupscale_damper

                    damper.le_poslocal.z = wheel.radius
                    damper.le_poslocal:Rotate( Angle( -arm.barangle, 0, 0 ) )
                    damper.le_poslocal.z = zpos - length
                    damper.le_poslocal.x = damper.le_poslocal.x + arm.le_origin.x
                    damper.le_poslocal.y = arm.le_poslocal.y

                    if isdouble then
                        damper.bone2pos_ri = Vector( 0, 0, 0 )
                        damper.ri_poslocal.z = wheel.radius
                        damper.ri_poslocal:Rotate( Angle( -arm.barangle, 0, 0 ) )
                        damper.ri_poslocal.z = zpos - length
                        damper.ri_poslocal.x = damper.ri_poslocal.x + arm.ri_origin.x
                        damper.ri_poslocal.y = arm.ri_poslocal.y
                        damper.ri_anglocal.y = 180
                    end

                    -- bone 2 is the only one that moves, so the dampers can still be drawn batched
                    damper.batchmove = { bone = 2, le = damper.bone2pos_le, ri = damper.bone2pos_ri }
                end
            end

            ::CONTINUE::
        end
    end

    local sides = {
        { s = 1, track = 1, trace = "le_trace", origin = "le_origin", offset = "le_offsetX", offsetK = "le_offsetK", poslocal = "le_poslocal", posworld = "le_posworld", anglocal = "le_anglocal", angworld = "le_angworld", bone2pos = "bone2pos_le" },
        { s = -1, track = 2, trace = "ri_trace", origin = "ri_origin", offset = "ri_offsetX", offsetK = "ri_offsetK", poslocal = "ri_poslocal", posworld = "ri_posworld", anglocal = "ri_anglocal", angworld = "ri_angworld", bone2pos = "bone2pos_ri" },
    }

    -- traces and solves the arm angle, s is 1 on the left and -1 on the right
    local function torsionSolve( frame, side, wheel, arm, wheel_radius, contact, real )
        local s = side.s
        local trace = setupTrace( wheel[side.trace] )

        -- trace from arm origin to ground
        local ox, oy, oz = arm[side.origin]:Unpack()
        local kx, ky, kz = arm[side.offset]:Unpack()
        local sx, sy, sz = frameToWorld( ox - s * kx, oy - s * ky, oz - s * kz )
        local hx, hy, hz = groundHit( trace, sx, sy, sz, wheel.trace_len, contact, real )

        -- inverse kinematics to solve the arm angle
        local ax, ay, az = frameToWorld( arm[side.poslocal]:Unpack() )
        local arm_length = arm.barlengthbeam
        local dx, dy, dz = hx - ax, hy - ay, hz - az
        local dist = math_min( math_sqrt( dx * dx + dy * dy + dz * dz ), arm_length + wheel_radius )
        local lx, _, lz = frameToLocal( dx, dy, dz )

        local arm_ang_l = arm[side.anglocal]
        arm_ang_l.p = atan( s * lx, lz ) + s * icos( dist, arm_length, wheel_radius ) * ( arm[side.offsetK] > 0 and 1 or -1 )

        -- protect against divide by zero
        if arm_ang_l.p ~= arm_ang_l.p then arm_ang_l.p = 0 end

        -- forward kinematics to adjust the trace position in the next tick
        arm[side.offset].x = -sin( arm_ang_l.p ) * arm_length - s * arm[side.offsetK]
    end

    -- puts the arm, wheel and damper where the hull and the solved arm angle say
    local function torsionPlace( frame, side, wheel, arm, damper )
        local s = side.s
        local arm_ang_l = arm[side.anglocal]

        arm[side.posworld]:SetUnpacked( frameToWorld( arm[side.poslocal]:Unpack() ) )
        toWorld( frame, nil, arm_ang_l, nil, arm[side.angworld] )

        -- position wheel at the end of the arm
        _tmat:Set( frame )
        _tmat:Translate( arm[side.poslocal] )
        _tmat:Rotate( arm_ang_l )
        _tmat:Translate( wheel[side.poslocal] )
        _tmat:Rotate( wheel[side.anglocal] )

        local wheelpos = wheel[side.posworld]
        readTMat( wheelpos, wheel[side.angworld] )

        local wx, wy, wz = wheelpos:Unpack()

        -- hacky localized vector used by the track renderer written for the old system, I hate it but I'm not redoing it
        wheel[side.track]:SetUnpacked( frameToLocal( wx - f14, wy - f24, wz - f34 ) )

        if damper then
            local px, py, pz = frameToWorld( damper[side.poslocal]:Unpack() )
            damper[side.posworld]:SetUnpacked( px, py, pz )

            local dx, dy, dz = wx - px, wy - py, wz - pz
            local lx, _, lz = frameToLocal( dx, dy, dz )

            local damper_ang_l = damper[side.anglocal]
            damper_ang_l.p = atan( s * lx, lz )
            toWorld( frame, nil, damper_ang_l, nil, damper[side.angworld] )
            damper[side.bone2pos].y = math_sqrt( dx * dx + dy * dy + dz * dz ) / arm.barsize - damper.zlength - 1
        end
    end

    function modes.torsion:onThink( controller )
        local frame = controller.autotracks_matrix
        loadFrame( frame )

        local isdouble = controller.autotracks_isdouble
        local values = controller.netvar.values

        local rot_le, rot_ri = updateScroll( controller, values, isdouble )

        local data = self:getData( controller )
        local trace, moved = traceDue( data, controller:EntIndex() )
        if not trace and not moved and rot_le == 0 and rot_ri == 0 then return end

        local contact = getContact( data )
        if trace then contactReset( contact ) end

        local parts = self:getParts( controller )

        for i = 1, #parts do
            local assem = parts[i]
            local wheel = assem[1]

            wheel.le_anglocal.p = wheel.le_anglocal.p - rot_le / wheel.circumference
            if isdouble then
                wheel.ri_anglocal.p = wheel.ri_anglocal.p + rot_ri / wheel.circumference
            end

            if wheel.suspension then
                local arm, damper = assem[2], assem[3]

                local wheel_radius = values.trackEnable and wheel.trackHeight or wheel.radius
                torsionSolve( frame, sides[1], wheel, arm, wheel_radius, contact[1], trace )
                if isdouble then
                    torsionSolve( frame, sides[2], wheel, arm, wheel_radius, contact[2], trace )
                end

                torsionPlace( frame, sides[1], wheel, arm, damper )
                if isdouble then
                    torsionPlace( frame, sides[2], wheel, arm, damper )
                end
            else
                toWorld( frame, wheel.le_poslocal, wheel.le_anglocal, wheel.le_posworld, wheel.le_angworld )
                if isdouble then
                    toWorld( frame, wheel.ri_poslocal, wheel.ri_anglocal, wheel.ri_posworld, wheel.ri_angworld )
                end
            end
        end

        updateDust( controller, 1, controller.autotracks_le_lastvel, values, contact[1] )
        if isdouble then
            updateDust( controller, 2, controller.autotracks_ri_lastvel, values, contact[2] )
        end
    end

    function modes.torsion:onDraw( controller, eyepos, eyedir, empty, flashlight )
        self:renderParts( controller, eyepos, eyedir, empty )
        if controller.autotracks_dotracks then
            tanktracktool.autotracks.render( controller, controller.autotracks_matrix )
        end

        if flashlight then
            render.PushFlashlightMode( true )
            self:renderParts( controller, eyepos, eyedir, empty )
            if controller.autotracks_dotracks then
                tanktracktool.autotracks.render( controller, controller.autotracks_matrix )
            end
            render.PopFlashlightMode()
        end
    end
end


--[[
    bogie mode
]]
do
    modes.bogie:addCSent( "wheel_road", "wheel_roller", "arm", "damper", "bogie" )

    function modes.bogie:onInit( controller )

        modes.torsion.onInit( self, controller )

    end

    function modes.bogie:onThink( controller )

        modes.torsion.onThink( self, controller )

    end

    function modes.bogie:onDraw( controller, eyepos, eyedir, empty, flashlight )

        modes.torsion.onDraw( self, controller, eyepos, eyedir, empty, flashlight )

    end
end
