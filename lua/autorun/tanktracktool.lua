
tanktracktool = {}

if SERVER then

    AddCSLuaFile( "tanktracktool/util.lua" )
    AddCSLuaFile( "tanktracktool/netvar.lua" )
    AddCSLuaFile( "tanktracktool/property.lua" )

    AddCSLuaFile( "tanktracktool/client/render/mode.lua" )
    AddCSLuaFile( "tanktracktool/client/render/effects.lua" )
    AddCSLuaFile( "tanktracktool/client/render/autotracks.lua" )

    AddCSLuaFile( "tanktracktool/client/derma/editor/editor.lua" )
    AddCSLuaFile( "tanktracktool/client/derma/editor/node.lua" )
    AddCSLuaFile( "tanktracktool/client/derma/editor/node_category.lua" )
    AddCSLuaFile( "tanktracktool/client/derma/editor/controls/array.lua" )
    AddCSLuaFile( "tanktracktool/client/derma/editor/controls/bitfield.lua" )
    AddCSLuaFile( "tanktracktool/client/derma/editor/controls/checkbox.lua" )
    AddCSLuaFile( "tanktracktool/client/derma/editor/controls/color.lua" )
    AddCSLuaFile( "tanktracktool/client/derma/editor/controls/combo.lua" )
    AddCSLuaFile( "tanktracktool/client/derma/editor/controls/generic.lua" )
    AddCSLuaFile( "tanktracktool/client/derma/editor/controls/instance.lua" )
    AddCSLuaFile( "tanktracktool/client/derma/editor/controls/number.lua" )
    AddCSLuaFile( "tanktracktool/client/derma/editor/controls/vector.lua" )

    include( "tanktracktool/netvar.lua" )
    include( "tanktracktool/property.lua" )

    resource.AddWorkshop("737640184")
end

if CLIENT then

    include( "tanktracktool/util.lua" )
    include( "tanktracktool/netvar.lua" )
    include( "tanktracktool/property.lua" )

    include( "tanktracktool/client/render/mode.lua" )
    include( "tanktracktool/client/render/effects.lua" )
    include( "tanktracktool/client/render/autotracks.lua" )

    include( "tanktracktool/client/derma/editor/editor.lua" )
    include( "tanktracktool/client/derma/editor/node.lua" )
    include( "tanktracktool/client/derma/editor/node_category.lua" )
    include( "tanktracktool/client/derma/editor/controls/array.lua" )
    include( "tanktracktool/client/derma/editor/controls/bitfield.lua" )
    include( "tanktracktool/client/derma/editor/controls/checkbox.lua" )
    include( "tanktracktool/client/derma/editor/controls/color.lua" )
    include( "tanktracktool/client/derma/editor/controls/combo.lua" )
    include( "tanktracktool/client/derma/editor/controls/generic.lua" )
    include( "tanktracktool/client/derma/editor/controls/instance.lua" )
    include( "tanktracktool/client/derma/editor/controls/number.lua" )
    include( "tanktracktool/client/derma/editor/controls/vector.lua" )

end

do
    local flags = { edit = 2, data = 4, link = 8, ents = 16 }
    local bits = 0
    local note = 0

    tanktracktool.loud_edit = flags.edit
    tanktracktool.loud_data = flags.data
    tanktracktool.loud_link = flags.link
    tanktracktool.loud_ents = flags.ents

    local c0 = Color( 255, 255, 0 )
    local c1 = Color( 255, 255, 255 )

    function tanktracktool.note( ... )
        note = ( note + 1 ) % 64000
        local msg = table.concat( { ... }, "\n" )
        MsgC( c0, string.format( "tanktracktool[%d]", note ), "\n", c1, msg, "\n" )
    end

    function tanktracktool.loud( flag )
        return bit.band( bits, flag ) == flag
    end

    local function setFlag( flag )
        if not ( bit.band( bits, flag ) == flag ) then
            bits =  bit.bor( bits, flag )
        end
    end

    local function unsetFlag( flag )
        if bit.band( bits, flag ) == flag then
            bits = bit.band( bits, bit.bnot( flag ) )
        end
    end

    concommand.Add( "tanktracktool_loud", function( ply, cmd, args )
        if not args then bits = 0 return end

        bits = 0
        note = 0

        local valid
        for k, v in pairs( args ) do
            if flags[v] then
                setFlag( flags[v] )
                valid = true
            end
        end

        if not valid then bits = 0 end
    end )
end
