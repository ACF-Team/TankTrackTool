
DEFINE_BASECLASS( "base_tanktracktool" )

ENT.Type      = "anim"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.Category  = "Tank Track Tool"
ENT.PrintName = "Tank Track Auto"

local netvar = tanktracktool.netvar.new()

local default = {
    whnSuspension = {
        [1] = 0,
        [2] = 0,
    },
    whnOverride = {
        [1] = 1,
        [2] = 1,
    },
    whnRadius = {
        [1] = 10,
        [2] = 10,
    },
    whnWidth = {
        [1] = 20,
        [2] = 20,
    },
    whnModel = {
        [1] = "models/sprops/trans/miscwheels/tank15.mdl",
        [2] = "models/sprops/trans/miscwheels/tank15.mdl",
    },
    whnBodygroup = {
        [1] = "001",
    },
}

function ENT:netvar_setup()
    return netvar, default
end

netvar:category( "System" )
netvar:var( "systemOffsetX", "Float", { min = -2000, max = 2000, def = 0, title = "x offset" } )
netvar:var( "systemOffsetY", "Float", { min = -2000, max = 2000, def = 0, title = "y offset" } )
netvar:var( "systemOffsetZ", "Float", { min = -2000, max = 2000, def = 0, title = "z offset" } )
netvar:var( "systemEffScale", "Float", { min = 0, max = 1, def = 0.5, title = "ground fx scale" } )
netvar:var( "systemMirror", "Bool", { def = 1, title = "mirror" } )

netvar:category( "Suspension" )
netvar:var( "suspensionType", "Combo", { values = { classic = 1, torsion = 2, bogie = 3 }, def = "classic", title = "type" } )
netvar:var( "suspensionX", "Float", { min = 0, max = 4000, def = 200, title = "length" } )
netvar:var( "suspensionY", "Float", { min = 0, max = 4000, def = 100, title = "width" } )
netvar:var( "suspensionZ", "Float", { min = 0, max = 4000, def = 40, title = "height" } )
netvar:var( "suspensionInterleave", "Float", { min = -1, max = 1, def = 0, title = "interleave" } )
netvar:var( "suspensionPairGap", "Float", { min = -1, max = 1, def = 0, title = "paired spacing" } )

netvar:subcategory( "model" )
netvar:var( "suspensionColor", "Color", { def = "", title = "color" } )
netvar:var( "suspensionMaterial", "String", { def = "", title = "material" } )
netvar:var( "suspensionTDamp", "Int", { min = 0, max = 3, def = 0, title = "damper_count" } )
netvar:var( "suspensionTDampZ", "Float", { min = 0, max = 1, def = 1, title = "damper_length" } )
netvar:var( "suspensionTAngle", "Float", { min = -90, max = 90, def = 45, title = "beam_angle" } )
netvar:var( "suspensionTSize", "Float", { min = 0, max = 250, def = 4, title = "beam_thickness" } )
netvar:var( "suspensionTBeam", "Float", { min = 0, max = 250, def = 20, title = "beam_length" } )
netvar:var( "suspensionTAxle", "Float", { min = 0, max = 250, def = 8, title = "axle_length" } )
netvar:var( "suspensionTAxleRad", "Float", { min = 0, max = 1, def = 1, title = "axle_radius" } )
netvar:var( "suspensionTConn", "Float", { min = 0, max = 250, def = 9, title = "conn_length" } )
netvar:var( "suspensionTConnRad", "Float", { min = 0, max = 1, def = 1, title = "conn_radius" } )

netvar:category( "Track" )
netvar:var( "trackEnable", "Bool", { def = 1, title = "enabled" } )
netvar:var( "trackColor", "Color", { def = "", title = "color" } )
netvar:var( "trackMaterial", "Combo", { def = "generic", title = "material" } )
netvar:var( "trackRes", "Int", { min = 1, max = 8, def = 2, title = "resolution" } )

netvar:subcategory( "shape" )
netvar:var( "trackTension", "Float", { min = 0, max = 1, def = 0.5, title = "tension" } )
netvar:var( "trackWidth", "Float", { min = 0, max = 250, def = 24, title = "width" } )
netvar:var( "trackHeight", "Float", { min = 0, max = 250, def = 3, title = "height" } )
netvar:var( "trackGuideY", "Float", { min = -1, max = 1, def = 0, title = "guide offset" } )
netvar:var( "trackGuideZ", "Float", { min = 0, max = 5, def = 1.5, title = "guide height" } )
netvar:var( "trackGrouser", "Float", { min = 0, max = 1, def = 0, title = "grouser length" } )

netvar:category( "Wheels" )
netvar:var( "wheelColor", "Color", { def = "", title = "color" } )
netvar:var( "wheelMaterial", "Array", { count = 5, title = "material", label = function( i ) return i == 1 and "base" or string.format( "submaterial %d", i - 1 ) end } )
netvar:var( "wheelModel", "String", { def = "models/sprops/trans/miscwheels/tank15.mdl", title = "model" } )
netvar:var( "wheelBodygroup", "String", { def = "", title = "bodygroup" } )
netvar:var( "wheelRadius", "Float", { min = 0, max = 250, def = 15, title = "radius" } )
netvar:var( "wheelWidth", "Float", { min = 0, max = 250, def = 10, title = "width" } )
netvar:var( "wheelCount", "Instance", { min = 2, max = 18, def = 7, title = "count", label = function( i ) return string.format( "wheel [%s]", i == 1 and "first" or i == 2 and "last" or i ) end } )

netvar:category( nil )
netvar:subvar( "whnOffsetX", "wheelCount", "Float", { min = -5, max = 5, def = 0, title = "x offset" } )
netvar:subvar( "whnOffsetY", "wheelCount", "Float", { min = -1, max = 1, def = 0, title = "y offset" } )
netvar:subvar( "whnOffsetZ", "wheelCount", "Float", { min = -2000, max = 2000, def = 0, title = "z offset" } )
netvar:subvar( "whnSuspension", "wheelCount", "Bool", { def = 1, title = "suspension" } )

netvar:category( "whnSuspension" )
netvar:subvar( "whnTraceZ", "wheelCount", "Float", { min = 0, max = 1, def = 0, title = "height" } )

netvar:category( nil )
netvar:subvar( "whnOverride", "wheelCount", "Bool", { def = 0, title = "visual",
    inherit = { whnColor = "wheelColor", whnMaterial = "wheelMaterial", whnModel = "wheelModel", whnBodygroup = "wheelBodygroup", whnRadius = "wheelRadius", whnWidth = "wheelWidth" }
} )

netvar:category( "whnOverride" )
netvar:subvar( "whnColor", "wheelCount", "Color", { def = "", title = "color", inherit = "wheelColor" } )
netvar:subvar( "whnMaterial", "wheelCount", "Array", { count = 5, title = "material", label = function( i ) return i == 1 and "base" or string.format( "submaterial %d", i - 1 ) end, inherit = "wheelMaterial" } )
netvar:subvar( "whnModel", "wheelCount", "String", { def = "", title = "model", inherit = "wheelModel" } )
netvar:subvar( "whnBodygroup", "wheelCount", "String", { def = "", title = "bodygroup", inherit = "wheelBodygroup" } )
netvar:subvar( "whnRadius", "wheelCount", "Float", { min = 0, max = 250, def = 0, title = "radius", inherit = "wheelRadius" } )
netvar:subvar( "whnWidth", "wheelCount", "Float", { min = 0, max = 250, def = 0, title = "width", inherit = "wheelWidth" } )

netvar:category( "Rollers" )
netvar:var( "rollerColor", "Color", { def = "", title = "color" } )
netvar:var( "rollerMaterial", "Array", { count = 5, title = "material", label = function( i ) return i == 1 and "base" or string.format( "submaterial %d", i - 1 ) end } )
netvar:var( "rollerModel", "String", { def = "models/sprops/trans/miscwheels/tank15.mdl", title = "model" } )
netvar:var( "rollerBodygroup", "String", { def = "", title = "bodygroup" } )
netvar:var( "rollerRadius", "Float", { min = 0, max = 250, def = 7.5, title = "radius" } )
netvar:var( "rollerWidth", "Float", { min = 0, max = 250, def = 10, title = "width" } )
netvar:var( "rollerOffsetZ", "Float", { min = -1000, max = 1000, def = 0, title = "z offset" } )
netvar:var( "rollerLocalZ", "Bool", { def = 0, title = "z local" } )
netvar:var( "rollerCount", "Instance", { min = 0, max = 18, def = 2, title = "count", label = "roller" } )

netvar:category( nil )
netvar:subvar( "ronOffsetX", "rollerCount", "Float", { min = -5, max = 5, def = 0, title = "x offset" } )
netvar:subvar( "ronOffsetY", "rollerCount", "Float", { min = -1, max = 1, def = 0, title = "y offset" } )
netvar:subvar( "ronOffsetZ", "rollerCount", "Float", { min = -2000, max = 2000, def = 0, title = "z offset" } )
netvar:subvar( "ronOverride", "rollerCount", "Bool", { def = 0, title = "visual",
    inherit = { ronColor = "rollerColor", ronMaterial = "rollerMaterial", ronModel = "rollerModel", ronBodygroup = "rollerBodygroup", ronRadius = "rollerRadius", ronWidth = "rollerWidth" }
} )

netvar:category( "ronOverride" )
netvar:subvar( "ronColor", "rollerCount", "Color", { def = "", title = "color", inherit = "rollerColor" } )
netvar:subvar( "ronMaterial", "rollerCount", "Array", { count = 5, title = "material", label = function( i ) return i == 1 and "base" or string.format( "submaterial %d", i - 1 ) end, inherit = "rollerMaterial" } )
netvar:subvar( "ronModel", "rollerCount", "String", { def = "", title = "model", inherit = "rollerModel" } )
netvar:subvar( "ronBodygroup", "rollerCount", "String", { def = "", title = "bodygroup", inherit = "rollerBodygroup" } )
netvar:subvar( "ronRadius", "rollerCount", "Float", { min = 0, max = 250, def = 0, title = "radius", inherit = "rollerRadius" } )
netvar:subvar( "ronWidth", "rollerCount", "Float", { min = 0, max = 250, def = 0, title = "width", inherit = "rollerWidth" } )


if CLIENT then
    netvar:get( "trackMaterial" ).data.values = tanktracktool.autotracks.textureList()
    netvar:get( "trackMaterial" ).data.images = "tanktracktool/autotracks/gui/%s"

    netvar:get( "trackEnable" ).data.hook = function( inner, val )
        local editor = inner.m_Editor
        local enabled = tobool( val )

        editor.Variables.trackColor:SetEnabled( enabled )
        editor.Variables.trackMaterial:SetEnabled( enabled )
        editor.Variables.trackRes:SetEnabled( enabled )

        if not enabled then
            editor.Categories.Track.Categories.shape:SetExpanded( false, true )
        end
        editor.Categories.Track.Categories.shape:SetEnabled( enabled )
    end
    netvar:get( "suspensionType" ).data.hook = function( inner, val )
        local editor = inner.m_Editor
        if val == "classic" then
            editor.Categories.Suspension.Categories.model:SetExpanded( false, true )
            editor.Categories.Suspension.Categories.model:SetEnabled( false )
            editor.Variables.suspensionInterleave:SetEnabled( true )
        else
            editor.Categories.Suspension.Categories.model:SetEnabled( true )
            editor.Variables.suspensionInterleave:SetEnabled( val == "torsion" )
        end
    end

    local function hide( inner, val )
        local obj = inner.Instances
        for i = 1, #obj do
            local enabled = i <= val
            if not enabled then
                obj[i]:SetExpanded( false, true )
            end
            obj[i]:SetEnabled( enabled )
        end
    end
    netvar:get( "wheelCount" ).data.hook = hide
    netvar:get( "rollerCount" ).data.hook = hide

    local function hide( inner, val )
        local enabled = tobool( val )
        for k, v in pairs( inner:GetRow().Categories ) do
            v:SetEnabled( enabled )
        end
    end

    netvar:get( "whnOverride" ).data.hook = hide
    netvar:get( "ronOverride" ).data.hook = hide
    netvar:get( "whnSuspension" ).data.hook = function( inner, val )
        local enabled = tobool( val )
        inner:GetRow():GetParentNode().Categories.whnOffsetZ:SetEnabled( not enabled )
        hide( inner, val )
    end
end
