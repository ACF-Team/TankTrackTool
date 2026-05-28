
DEFINE_BASECLASS( "base_tanktracktool" )

ENT.Type      = "anim"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.Category  = "Tank Track Tool"
ENT.PrintName = "Tank Track Legacy"

local tanktracktool = tanktracktool


--[[
    netvar setup
]]
local netvar = tanktracktool.netvar.new()

function ENT:netvar_setup()
    return netvar
end

netvar:category( "System" )
netvar:var( "systemRotate", "Bool", { def = 0, title = "swap chassis axis", help = "rotates the tool arrows by 90 degrees" } )

netvar:category( "Tracks" )
netvar:var( "trackColor", "Color", { def = "", title = "color" } )
netvar:var( "trackMaterial", "Combo", { def = "generic", title = "material" } )
netvar:var( "trackRes", "Int", { min = 1, max = 8, def = 2, title = "resolution" } )
netvar:var( "trackOffsetY", "Float", { min = -250, max = 250, def = 0, title = "y offset" } )
netvar:var( "trackFlip", "Bool", { def = 0, title = "flip mesh", help = "affects y offset, guide offset, and grouser" } )

netvar:subcategory( "Shape" )
netvar:var( "trackTension", "Float", { min = 0, max = 1, def = 0.5, title = "tension" } )
netvar:var( "trackWidth", "Float", { min = 0, max = 250, def = 24, title = "width" } )
netvar:var( "trackHeight", "Float", { min = 0, max = 250, def = 3, title = "height" } )
netvar:var( "trackGuideY", "Float", { min = -1, max = 1, def = 0, title = "guide offset" } )
netvar:var( "trackGuideZ", "Float", { min = 0, max = 5, def = 1.5, title = "guide height" } )
netvar:var( "trackGrouser", "Float", { min = 0, max = 1, def = 0, title = "grouser length" } )

netvar:category( "Wheels" )
netvar:var( "wheelSprocket", "Int", { min = 1, max = 250, def = 1,  title = "sprocket id", help = "controls which wheel scrolls the tracks" } )
netvar:var( "scrollMod", "Float", { min = 0, max = 2, def = 1, title = "scroll speed", help = "divisor for track scroll speed" } )
netvar:var( "wheelRadius", "Float", { min = -250, max = 250, def = 0, title = "offset wheel radius" } )
netvar:var( "rollerRadius", "Float", { min = -250, max = 250, def = 0, title = "offset roller radius" } )

if CLIENT then
    netvar:get( "trackMaterial" ).data.values = tanktracktool.autotracks.textureList()
    netvar:get( "trackMaterial" ).data.images = "tanktracktool/autotracks/gui/%s"
end
