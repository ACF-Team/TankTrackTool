
local fixtures = include( "tests/tanktracktool/helpers/fixtures.lua" )
local probe = include( "tests/tanktracktool/helpers/probe.lua" )

local function topProfile( frame, y, from, to, step )
    local heights = {}
    for x = from, to, step do
        heights[#heights + 1] = probe.height( frame, x, y, true ) or -math.huge
    end
    return heights
end

local function sag( tight, slack )
    local most = 0
    for i = 1, #tight do most = math.max( most, tight[i] - slack[i] ) end
    return most
end

local function lateral( frame, origin, dir, maxdist )
    local hit = probe.first( frame, origin, dir, maxdist )
    return hit and hit.t
end

return {
    groupName = "tanktracktool.autotracks options",

    beforeEach = function( state )
        state.backend, state.autotracks = fixtures.load()
        state.track = function( opts ) return fixtures.track( state.backend, state.autotracks, opts ) end
    end,

    cases = {
        {
            name = "Lower tension makes the top run sag more",
            func = function( state )
                for _, layout in ipairs( { "default", "norollers" } ) do
                    local profiles = {}
                    for _, tension in ipairs( { 1, 0.5, 0 } ) do
                        local track = state.track( { layout = layout, values = { trackTension = tension } } ):build()
                        local y = track:wheel( 1, 1 ).y + 0.3 * track.values.trackWidth
                        profiles[tension] = topProfile( track:frame(), y, -90, 90, 2 )
                    end

                    local half = sag( profiles[1], profiles[0.5] )
                    local none = sag( profiles[1], profiles[0] )

                    expect( half ).to.beGreaterThan( 0.5 )
                    expect( none ).to.beGreaterThan( half + 0.5 )
                end
            end
        },

        {
            name = "Full tension keeps the top run straight between level wheels",
            func = function( state )
                local track = state.track( { values = { trackTension = 1 } } ):build()
                local frame = track:frame()
                local y = track:wheel( 1, 1 ).y + 0.3 * track.values.trackWidth
                local top = 7.5 + track.values.trackHeight

                for x = -44, 44, 4 do
                    expect( probe.height( frame, x, y, true ) ).to.aboutEqual( top, 0.1 )
                end

                track = state.track( { layout = "norollers", values = { trackTension = 1 } } ):build()
                frame = track:frame()
                top = 10 + track.values.trackHeight

                for x = -90, 90, 10 do
                    expect( probe.height( frame, x, y, true ) ).to.aboutEqual( top, 0.1 )
                end
            end
        },

        {
            name = "The guide sits at its offset and reaches its height",
            func = function( state )
                for _, flip in ipairs( { 0, 1 } ) do
                    local track = state.track( { values = { trackGuideY = 0.5, trackGuideZ = 1.5, trackFlip = flip } } ):build()
                    local frame = track:frame()
                    local values = track.values
                    local offset = values.trackWidth * 0.5 * 0.375
                    local _, radius = track:wheel( 4, 1 )
                    local reach = radius + values.trackHeight * 0.5 - values.trackGuideZ * values.trackHeight

                    for _, side in ipairs( track:sides() ) do
                        local center = track:wheel( 4, side )
                        local towards = ( side == 1 ) == ( flip == 0 ) and 1 or -1
                        local inside = center - Vector( 0, 0, reach + 0.3 )
                        local beyond = center - Vector( 0, 0, reach - 0.3 )

                        expect( lateral( frame, inside, Vector( 0, towards, 0 ), values.trackWidth ) ).to.aboutEqual( offset, 0.05 )
                        expect( lateral( frame, inside, Vector( 0, -towards, 0 ), values.trackWidth ) ).to.beNil()
                        expect( lateral( frame, beyond, Vector( 0, towards, 0 ), values.trackWidth ) ).to.beNil()
                    end
                end
            end
        },

        {
            name = "Grousers stick out of the outer edge",
            func = function( state )
                for _, flip in ipairs( { 0, 1 } ) do
                    local track = state.track( { values = { trackGrouser = 0.5, trackFlip = flip } } ):build()
                    local frame = track:frame()
                    local half = track.values.trackWidth * 0.5
                    local reach = half + 0.9 * track.values.trackGrouser * track.values.trackWidth

                    for _, side in ipairs( track:sides() ) do
                        local y = track:wheel( 1, side ).y
                        local outward = ( side == 1 ) == ( flip == 0 ) and 1 or -1
                        local mins, maxs = probe.extents( frame, function( p ) return ( p.y > 0 ) == ( side == 1 ) end )
                        local far, near = maxs.y - y, y - mins.y
                        if outward < 0 then far, near = near, far end

                        expect( far ).to.beGreaterThan( reach )
                        expect( near ).to.aboutEqual( half, 0.05 )
                    end
                end
            end
        },

        {
            name = "Is drawn with the chosen track texture",
            func = function( state )
                local track = state.track( { values = { trackMaterial = "t72" } } ):build()
                local frame = track:frame()

                expect( #frame.draws ).to.beGreaterThan( 0 )
                for _, draw in ipairs( frame.draws ) do
                    local material = draw.material
                    expect( material:GetShader() ).to.equal( "VertexLitGeneric" )
                    expect( string.find( material:GetString( "$basetexture" ), "tanktracktool/autotracks/t72", 1, true ) ).to.exist()
                    expect( material:GetInt( "$alphatest" ) ).to.equal( 1 )
                    expect( material:GetInt( "$nocull" ) ).to.equal( 1 )
                end
            end
        },

        {
            name = "Still draws when the texture doesn't exist",
            func = function( state )
                local track = state.track( { values = { trackMaterial = "this_texture_does_not_exist" } } ):build()
                expect( #track:frame().tris ).to.beGreaterThan( 0 )
            end
        },

        {
            name = "Is tinted with the track color",
            func = function( state )
                local track = state.track( { values = { trackColor = "255 128 0 255" } } ):build()
                local frame = track:frame()

                for _, draw in ipairs( frame.draws ) do
                    expect( draw.color2.x ).to.aboutEqual( 1, 0.01 )
                    expect( draw.color2.y ).to.aboutEqual( 128 / 255, 0.01 )
                    expect( draw.color2.z ).to.aboutEqual( 0, 0.01 )
                end
            end
        },
    }
}
