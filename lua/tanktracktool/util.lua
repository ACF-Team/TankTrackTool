
local tanktracktool = tanktracktool
tanktracktool.util = {}

local math, util, string, table, render =
      math, util, string, table, render

local next, pairs, FrameTime, Entity, IsValid, EyePos, EyeVector, Vector, Angle, Matrix, WorldToLocal, LocalToWorld, Lerp, LerpVector =
      next, pairs, FrameTime, Entity, IsValid, EyePos, EyeVector, Vector, Angle, Matrix, WorldToLocal, LocalToWorld, Lerp, LerpVector

local pi = math.pi
local deg2rad = pi / 180
local rad2deg = 180 / pi

local noang = Angle()
local novec = Vector()

function tanktracktool.util.toLocalAng( pos, ang, l )
    local p, a = WorldToLocal( novec, l, pos, ang )
    return a
end

function tanktracktool.util.toWorldAng( pos, ang, l )
    local p, a = LocalToWorld( novec, l, pos, ang )
    return a
end

function tanktracktool.util.toLocalAxis( pos, ang, axis )
    local p, a = WorldToLocal( axis + pos, noang, pos, ang )
    return p
end

function tanktracktool.util.toWorldAxis( pos, ang, axis )
    local p, a = LocalToWorld( axis, noang, pos, ang )
    p:Add( pos )
    return p
end

function tanktracktool.util.bearing( pos, ang, tar )
    local p = WorldToLocal( tar, noang, pos, ang )
    return math.deg( -math.atan2( p.y, p.x ) )
end

function tanktracktool.util.getNetEntity( key, self )
    local e = self:GetNW2Entity( key, self )
    return IsValid( e ) and e or self
end

function tanktracktool.util.getRGBM( c )
    if isstring( c ) then c = string.ToColor( c ) end
    return { r = c.r / 255, g = c.g / 255, b = c.b / 255, a = c.a / 255 }
end

function tanktracktool.util.sin( a )
    return math.sin( a * deg2rad )
end

function tanktracktool.util.atan( a, b )
    return math.atan2( a, b ) * rad2deg
end

function tanktracktool.util.acos( a )
    return math.acos( a ) * rad2deg
end

local acos = tanktracktool.util.acos

function tanktracktool.util.icos( a, b, c )
    return acos( ( a^2 + b^2 - c^2 )  /  ( 2 * a * b ) )
end

function tanktracktool.util.lerp( a, b, t )
    return a + ( b - a ) * t
end

function tanktracktool.util.map( x, in_min, in_max, out_min, out_max )
    return ( x - in_min ) * ( out_max - out_min ) / ( in_max - in_min ) + out_min
end

function tanktracktool.util.calcbounds( min, max, pos )
    if pos.x < min.x then min.x = pos.x elseif pos.x > max.x then max.x = pos.x end
    if pos.y < min.y then min.y = pos.y elseif pos.y > max.y then max.y = pos.y end
    if pos.z < min.z then min.z = pos.z elseif pos.z > max.z then max.z = pos.z end
end

local errormdl = "models/hunter/blocks/cube025x025x025.mdl"
local badmdl = {
    [""] = true,
    ["models/lubprops/seat/raceseat2.mdl"] = true,
    ["models/lubprops/seat/raceseat.mdl"] = true,
}
local goodmdl = {}
function tanktracktool.util.getModel( model )
    model = string.Trim( model )
    if badmdl[model] or IsUselessModel( model ) then model = errormdl end
    if goodmdl[model] == nil then
        goodmdl[model] = file.Exists( model, "GAME" )
        if not goodmdl[model] then
            model = errormdl
        end
    end
    if goodmdl[model] == false then model = errormdl end
    return model
end

local errormat = "___error"
local badmat = {
    ["pp/copy"] = true,
    ["engine/writez"] = true,
    ["effects/ar2_altfire1"] = true,
}
local goodmat = {}
function tanktracktool.util.getMaterial( material )
    if not isstring( material ) then material = "" end
    material = string.Trim( material )
    if material == "" then return material end
    if goodmat[material] == nil then
        goodmat[material] = Material( material ):IsError()
    end
    if goodmat[material] == true then
        material = errormat
    end
    return material
end

local emptyCSENT = ClientsideModel( "models/props_c17/oildrum001_explosive.mdl" )
emptyCSENT:SetNoDraw( true )
local submat = {}

function tanktracktool.util.fixWheelModel( model, bodygroups, materials, radius, width )
    if not IsValid( emptyCSENT ) then
        emptyCSENT = ClientsideModel( "models/props_c17/oildrum001_explosive.mdl" )
        emptyCSENT:SetNoDraw( true )
    end

    model = tanktracktool.util.getModel( model )

    emptyCSENT:SetModel( model )
    emptyCSENT:DisableMatrix( "RenderMultiply" )
    emptyCSENT:SetupBones()

    local bodygroup
    bodygroups = tostring( bodygroups )
    if bodygroups then
        bodygroup = string.rep( "0", emptyCSENT:GetNumBodyGroups() )
        for char = 1, #bodygroup do
            local isnum = tonumber( bodygroups[char] )
            if isnum then
                bodygroup = string.format( "%s%s%s", string.sub( bodygroup, 1, char - 1 ), isnum, string.sub( bodygroup, char + 1 ) )
            end
        end
    end

    do
        local m = {}
        local s
        for k, v in pairs( materials ) do
            m[k] = tanktracktool.util.getMaterial( v )
            if not s and m[k] ~= "" then s = k end
        end

        if m[1] ~= "" or not s then
            materials = { base = m[1] }
        else
            if not submat[model] then
                submat[model] = emptyCSENT:GetMaterials()
            end
            local s = {}
            for id in pairs( submat[model] ) do
                s[id] = m[id + 1]
            end
            materials = s
        end
    end

    -- HitBoxBounds is the only function I could find that returns the correct min, max
    -- of models that have bodygroups that extend past the model's obb bounding box
    -- but it also gives ( incorrectly ) rotated vectors on some models
    local hmin, hmax, hbb = emptyCSENT:GetHitBoxBounds( 0, 0 )
    if hmin and hmax then
        hbb = hmax -  hmin
    end
    local obb = emptyCSENT:OBBMaxs() - emptyCSENT:OBBMins()
    local scale, rotate

    -- scale vector has to have the length of hbb but component order of obb
    -- hack below should cover all cases
    if obb.y < obb.x and obb.y < obb.z then
        if hbb then
            if hbb.y < hbb.x and hbb.y < hbb.z then
            else
                obb.x = hbb.y
                obb.y = hbb.x
                obb.z = hbb.z
            end
        end
        scale = Vector( radius * 2 / obb.x, width / obb.y, radius * 2 / obb.z )
    elseif obb.x < obb.y and obb.x < obb.z then
        if hbb then
            obb.x = hbb.y
            obb.y = hbb.x
            obb.z = hbb.z
        end
        scale = Vector( width / obb.x, radius * 2 / obb.y, radius * 2 / obb.z )
        rotate = Angle( 0, 90, 0 )
    else
        scale = Vector( radius * 2 / obb.x, width / obb.y, radius * 2 / obb.z )
    end

    local m = Matrix()
    if rotate then
        m:Rotate( rotate )
    end
    m:SetScale( scale )

    return {
        model = model,
        material = materials,
        bodygroup = bodygroup,
        scalem = m,
        scalev = scale,
        mins = Vector( -radius, -width * 0.5, -radius ),
        maxs = Vector( radius, width * 0.5, radius ),
     }
end
