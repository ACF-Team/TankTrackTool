
include( "shared.lua" )

local tanktracktool = tanktracktool

local math, util, string, table, render =
      math, util, string, table, render

local next, pairs, FrameTime, Entity, IsValid, EyePos, EyeVector, Vector, Angle, Matrix, WorldToLocal, LocalToWorld, Lerp, LerpVector =
      next, pairs, FrameTime, Entity, IsValid, EyePos, EyeVector, Vector, Angle, Matrix, WorldToLocal, LocalToWorld, Lerp, LerpVector

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
hooks.netvar_syncData = function( self )
    self.tanktracktool_reset = true
end

function ENT:netvar_callback( id, ... )
    if hooks[id] then hooks[id]( self, ... ) end
end


--[[
    base ent
]]
local _mvec = Vector()
local _mang = Angle()

local pos_le, vel_le, rot_le
local pos_ri, vel_ri, rot_ri
local _empty

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

    matrix:SetTranslation( base:GetPos() )
    matrix:SetAngles( axis:GetAngles() )
end

function ENT:autotracks_getMatrix()
    if not self.autotracks_matrix then
        return self:GetPos(), self:GetAngles()
    end
    return self.autotracks_matrix:GetTranslation(), self.autotracks_matrix:GetAngles()
end

function ENT:autotracks_getGroundFX( width )
    local scale = self.netvar.values.systemEffScale
    if not scale or scale == 0 then return end

    local max = width * scale

    local scale_le = math.min( max, 2 * math.abs( self.autotracks_le_lastvel ) )
    local scale_ri = math.min( max, 2 * math.abs( self.autotracks_ri_lastvel ) )

    if scale_le == 0 then scale_le = nil end
    if scale_ri == 0 then scale_ri = nil end

    return scale_le, scale_ri
end

local eff = "tanktracks_dust"
function ENT:autotracks_playGroundFX( pos, scale )
    local fxdata = EffectData()

    fxdata:SetOrigin( pos )
    fxdata:SetScale( scale )

    util.Effect( eff, fxdata )
end

function ENT:Think()
    if tanktracktool.disable_autotracks then
        self.tanktracktool_reset = true
        return
    end

    self.BaseClass.Think( self )

    if self:IsDormant() then
        return
    end

    if self.tanktracktool_reset then
        self.tanktracktool_reset = nil

        local values = self.netvar.values
        if not values then return end

        self.autotracks_dotracks = values.trackEnable ~= 0
        self.autotracks_isdouble = values.systemMirror ~= 0
        self.autotracks_le_lastpos = self.autotracks_le_lastpos or Vector()
        self.autotracks_le_lastvel = self.autotracks_le_lastvel or 1
        self.autotracks_le_lastrot = self.autotracks_le_lastrot or 1
        self.autotracks_ri_lastpos = self.autotracks_ri_lastpos or Vector()
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

function ENT:Draw()
    self:DrawModel()

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

    function modes.classic:onThink( controller )
        local pos, ang = controller:autotracks_getMatrix()
        local up, ri, fo = ang:Up(), ang:Right(), ang:Forward()

        local trace_len, trace_dir
        local wheel_rad, wheel_dir

        local isdouble = controller.autotracks_isdouble
        local values = controller.netvar.values
        local data = self:getData( controller )

        pos_le = pos - ri * values.suspensionY

        if controller:GetNW2Bool( "netwire_leftBrake", false ) then
            rot_le = 0
            vel_le = 0
        else
            local override = controller:GetNW2Float( "netwire_leftScroll", 0 )
            vel_le = override ~= 0 and -override or fo:Dot( controller.autotracks_le_lastpos - pos_le )
            rot_le = vel_le * 360
        end

        controller.autotracks_le_lastpos = pos_le
        controller.autotracks_le_lastvel = vel_le

        if isdouble then
            pos_ri = pos + ri * values.suspensionY

            if controller:GetNW2Bool( "netwire_rightBrake", false ) then
                rot_le = 0
                vel_le = 0
            else
                local override = controller:GetNW2Float( "netwire_rightScroll", 0 )
                vel_ri = override ~= 0 and -override or fo:Dot( controller.autotracks_ri_lastpos - pos_ri )
                rot_ri = vel_ri * 360
            end

            controller.autotracks_ri_lastpos = pos_ri
            controller.autotracks_ri_lastvel = vel_ri
        end

        local fx_le, fx_ri = controller:autotracks_getGroundFX( values.trackEnable and values.trackWidth or values.wheelWidth )
        local parts = self:getParts( controller )

        for i = 1, #parts do
            local parts = parts[i]
            local wheel = parts[1]

            local enabled = wheel.suspension
            if enabled then
                if trace_len ~= wheel.trace_len then
                    trace_len = wheel.trace_len
                    trace_dir = -trace_len * up
                end
                if wheel_rad ~= wheel.radius then
                    wheel_rad = wheel.radius
                    wheel_dir = ( wheel.trackHeight or wheel_rad ) * up
                end
            end

            wheel.le_anglocal.p = wheel.le_anglocal.p - rot_le / wheel.circumference

            if enabled then
                wheel.le_trace.start, wheel.le_angworld = LocalToWorld( wheel.le_poslocal, wheel.le_anglocal, pos, ang )
                wheel.le_trace.endpos = wheel.le_trace.start + trace_dir

                local trace = util.TraceHull( wheel.le_trace )
                if fx_le and trace.Hit then controller:autotracks_playGroundFX( trace.HitPos, fx_le ) end

                wheel.le_posworld = trace.HitPos + wheel_dir

                -- hacky localized vector used by the track renderer written for the old system, I hate it but I'm not redoing it
                wheel[1], _empty = WorldToLocal( wheel.le_posworld, _mang, pos, ang )
            else
                wheel.le_posworld, wheel.le_angworld = LocalToWorld( wheel.le_poslocal, wheel.le_anglocal, pos, ang )
            end

            if isdouble then
                wheel.ri_anglocal.p = wheel.ri_anglocal.p + rot_ri / wheel.circumference

                if enabled then
                    wheel.ri_trace.start, wheel.ri_angworld = LocalToWorld( wheel.ri_poslocal, wheel.ri_anglocal, pos, ang )
                    wheel.ri_trace.endpos = wheel.ri_trace.start + trace_dir

                    local trace = util.TraceHull( wheel.ri_trace )
                    if fx_ri and trace.Hit then controller:autotracks_playGroundFX( trace.HitPos, fx_ri ) end

                    wheel.ri_posworld = trace.HitPos + wheel_dir

                    -- hacky localized vector used by the track renderer written for the old system, I hate it but I'm not redoing it
                    wheel[2], _empty = WorldToLocal( wheel.ri_posworld, _mang, pos, ang )
                else
                    wheel.ri_posworld, wheel.ri_angworld = LocalToWorld( wheel.ri_poslocal, wheel.ri_anglocal, pos, ang )
                end
            end
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
                end
            end

            ::CONTINUE::
        end
    end

    function modes.torsion:onThink( controller )
        --if true then return end

        local pos, ang = controller:autotracks_getMatrix()
        local up, ri, fo = ang:Up(), ang:Right(), ang:Forward()

        local trace_len, trace_dir

        local isdouble = controller.autotracks_isdouble
        local values = controller.netvar.values
        local data = self:getData( controller )

        pos_le = pos - ri * values.suspensionY

        if controller:GetNW2Bool( "netwire_leftBrake", false ) then
            rot_le = 0
            vel_le = 0
        else
            local override = controller:GetNW2Float( "netwire_leftScroll", 0 )
            vel_le = override ~= 0 and -override or fo:Dot( controller.autotracks_le_lastpos - pos_le )
            rot_le = vel_le * 360
        end

        controller.autotracks_le_lastpos = pos_le
        controller.autotracks_le_lastvel = vel_le

        if isdouble then
            pos_ri = pos + ri * values.suspensionY

            if controller:GetNW2Bool( "netwire_rightBrake", false ) then
                rot_le = 0
                vel_le = 0
            else
                local override = controller:GetNW2Float( "netwire_rightScroll", 0 )
                vel_ri = override ~= 0 and -override or fo:Dot( controller.autotracks_ri_lastpos - pos_ri )
                rot_ri = vel_ri * 360
            end

            controller.autotracks_ri_lastpos = pos_ri
            controller.autotracks_ri_lastvel = vel_ri
        end

        local fx_le, fx_ri = controller:autotracks_getGroundFX( values.trackEnable and values.trackWidth or values.wheelWidth )
        local parts = self:getParts( controller )

        for i = 1, #parts do
            local parts = parts[i]
            local wheel = parts[1]

            if not wheel.suspension then
                wheel.le_anglocal.p = wheel.le_anglocal.p - rot_le / wheel.circumference
                wheel.le_posworld, wheel.le_angworld = LocalToWorld( wheel.le_poslocal, wheel.le_anglocal, pos, ang )

                if isdouble then
                    wheel.ri_anglocal.p = wheel.ri_anglocal.p + rot_ri / wheel.circumference
                    wheel.ri_posworld, wheel.ri_angworld = LocalToWorld( wheel.ri_poslocal, wheel.ri_anglocal, pos, ang )

                end

                goto GOTS_NO_ARMS
            end

            --[[

                everything below is a complete disaster and should probably be all be redone to
                use local coordinates or matrices or something

            ]]

            local arm = parts[2]

            if trace_len ~= wheel.trace_len then
                trace_len = wheel.trace_len
                trace_dir = trace_len * up
            end

            local arm_length = arm.barlengthbeam
            local wheel_radius = values.trackEnable and wheel.trackHeight or wheel.radius


            -- LEFT SIDE
            -- trace from arm origin to ground
            local wheel_trace = wheel.le_trace
            wheel_trace.start = LocalToWorld( arm.le_origin - arm.le_offsetX, _mang, pos, ang )
            wheel_trace.endpos = wheel_trace.start - trace_dir

            local trace = util.TraceHull( wheel_trace )
            if fx_le and trace.Hit then controller:autotracks_playGroundFX( trace.HitPos, fx_le ) end

            -- update the arm's world position
            arm.le_posworld = LocalToWorld( arm.le_poslocal, _mang, pos, ang )

            local arm_pos_w = arm.le_posworld
            local arm_ang_l = arm.le_anglocal

            -- inverse kinematics to solve the arm angle
            local diff = trace.HitPos - arm_pos_w
            local dist = math.min( diff:Length(), arm_length + wheel_radius )
            local axis = WorldToLocal( diff + pos, _mang, pos, ang )

            arm_ang_l.p = atan( axis.x, axis.z ) + icos( dist, arm_length, wheel_radius ) * ( arm.le_offsetK > 0 and 1 or -1 )

            -- protect against divide by zero
            if arm_ang_l.p ~= arm_ang_l.p then arm_ang_l.p = 0 end

            -- update the arm's world angle
            _empty, arm.le_angworld = LocalToWorld( _mvec, arm_ang_l, pos, ang )

            -- forward kinematics to adjust the trace position in the next tick
            arm.le_offsetX.x = -sin( arm_ang_l.p ) * arm_length - arm.le_offsetK

            -- position wheel at the end of the arm
            local wheel_ang_l = wheel.le_anglocal

            wheel_ang_l.p = wheel_ang_l.p - rot_le / wheel.circumference
            wheel.le_posworld, wheel.le_angworld = LocalToWorld( wheel.le_poslocal, wheel_ang_l, arm_pos_w, arm.le_angworld )

            -- hacky localized vector used by the track renderer written for the old system, I hate it but I'm not redoing it
            wheel[1], _ = WorldToLocal( wheel.le_posworld, _mang, pos, ang )

            -- damper
            local damper = parts[3]--parts.damper
            if damper then
                damper.le_posworld = LocalToWorld( damper.le_poslocal, _mang, pos, ang )

                local diff = wheel.le_posworld - damper.le_posworld
                local axis = WorldToLocal( diff + pos, _mang, pos, ang )

                damper.le_anglocal.p = atan( axis.x, axis.z )
                _empty, damper.le_angworld = LocalToWorld( _mvec, damper.le_anglocal, pos, ang )
                damper.bone2pos_le.y = ( diff:Length() ) / arm.barsize - damper.zlength - 1
            end


            -- RIGHT SIDE
            if isdouble then
                -- trace from arm origin to ground
                local wheel_trace = wheel.ri_trace
                wheel_trace.start, _empty = LocalToWorld( arm.ri_origin + arm.ri_offsetX, _mang, pos, ang )
                wheel_trace.endpos = wheel_trace.start - trace_dir

                local trace = util.TraceHull( wheel_trace )
                if fx_ri and trace.Hit then controller:autotracks_playGroundFX( trace.HitPos, fx_ri ) end

                -- update the arm's world position
                arm.ri_posworld = LocalToWorld( arm.ri_poslocal, _mang, pos, ang )

                local arm_pos_w = arm.ri_posworld
                local arm_ang_l = arm.ri_anglocal

                -- inverse kinematics to solve the arm angle
                local diff = trace.HitPos - arm_pos_w
                local dist = math.min( diff:Length(), arm_length + wheel_radius )
                local axis = WorldToLocal( diff + pos, _mang, pos, ang )

                arm_ang_l.p = atan( -axis.x, axis.z ) - icos( dist, arm_length, wheel_radius ) * ( arm.ri_offsetK > 0 and 1 or -1 )

                -- protect against divide by zero
                if arm_ang_l.p ~= arm_ang_l.p then arm_ang_l.p = 0 end

                -- update the arm's world angle
                _empty, arm.ri_angworld = LocalToWorld( _mvec, arm_ang_l, pos, ang )

                -- forward kinematics to adjust the trace position in the next tick
                arm.ri_offsetX.x = -sin( arm_ang_l.p ) * arm_length + arm.ri_offsetK

                -- position wheel at the end of the arm
                local wheel_ang_l = wheel.ri_anglocal

                wheel_ang_l.p = wheel_ang_l.p + rot_ri / wheel.circumference
                wheel.ri_posworld, wheel.ri_angworld = LocalToWorld( wheel.ri_poslocal, wheel_ang_l, arm_pos_w, arm.ri_angworld )

                -- hacky localized vector used by the track renderer written for the old system, I hate it but I'm not redoing it
                wheel[2], _ = WorldToLocal( wheel.ri_posworld, _mang, pos, ang )

                if damper then
                    damper.ri_posworld = LocalToWorld( damper.ri_poslocal, _mang, pos, ang )

                    local diff = wheel.ri_posworld - damper.ri_posworld
                    local axis = WorldToLocal( diff + pos, _mang, pos, ang )

                    damper.ri_anglocal.p = atan( -axis.x, axis.z )
                    _empty, damper.ri_angworld = LocalToWorld( _mvec, damper.ri_anglocal, pos, ang )
                    damper.bone2pos_ri.y = ( diff:Length() ) / arm.barsize - damper.zlength - 1
                end
            end

            ::GOTS_NO_ARMS::
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
