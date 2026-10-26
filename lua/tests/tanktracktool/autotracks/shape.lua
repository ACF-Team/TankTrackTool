
local fixtures = include( "tests/tanktracktool/helpers/fixtures.lua" )
local probe = include( "tests/tanktracktool/helpers/probe.lua" )

local function sameFrame( a, b, tolerance, map )
    if #a.tris ~= #b.tris then
        return string.format( "drew %d triangles, then %d", #a.tris, #b.tris )
    end
    for i = 1, #a.tris do
        for k = 1, 3 do
            local p, q = a.tris[i][k], b.tris[i][k]
            local x, y, z = p.x, p.y, p.z
            if map then
                local v = map( Vector( x, y, z ) )
                x, y, z = v.x, v.y, v.z
            end
            if math.abs( x - q.x ) > tolerance or math.abs( y - q.y ) > tolerance or math.abs( z - q.z ) > tolerance then
                return string.format( "triangle %d vertex %d moved from %s to %s", i, k, tostring( Vector( x, y, z ) ), tostring( Vector( q.x, q.y, q.z ) ) )
            end
        end
    end
    return ""
end

local function sideFilter( side )
    if side == 1 then return function( p ) return p.y > 0 end end
    return function( p ) return p.y < 0 end
end

return {
    groupName = "tanktracktool.autotracks shape",

    beforeEach = function( state )
        state.backend, state.autotracks = fixtures.load()
        state.track = function( opts ) return fixtures.track( state.backend, state.autotracks, opts ) end
    end,

    cases = {
        {
            name = "Draws a track for each side once it is set up",
            func = function( state )
                local track = state.track():build()
                local frame = track:frame()

                expect( #frame.tris ).to.beGreaterThan( 0 )
                expect( probe.extents( frame, sideFilter( 1 ) ) ).to.exist()
                expect( probe.extents( frame, sideFilter( 2 ) ) ).to.exist()
            end
        },

        {
            name = "Only draws one side when mirroring is off",
            func = function( state )
                local track = state.track( { mirror = false } ):build()
                local frame = track:frame()

                expect( probe.extents( frame, sideFilter( 1 ) ) ).to.exist()
                expect( probe.extents( frame, sideFilter( 2 ) ) ).to.beNil()
            end
        },

        {
            name = "Wraps around every wheel without cutting into any",
            func = function( state )
                for _, layout in ipairs( { "default", "norollers", "rollers3" } ) do
                    for _, tension in ipairs( { 0, 0.5, 1 } ) do
                        local track = state.track( { layout = layout, values = { trackTension = tension } } ):build()
                        local fails = track:contactFailures( track:frame(), 0.5 )
                        expect( fails ).to.equal( "" )
                    end
                end
            end
        },

        {
            name = "Is as thick as the track height",
            func = function( state )
                for _, height in ipairs( { 3, 6 } ) do
                    local track = state.track( { values = { trackHeight = height } } ):build()
                    local frame = track:frame()

                    for _, side in ipairs( track:sides() ) do
                        for _, i in ipairs( fixtures.roadwheels ) do
                            local center, radius = track:wheel( i, side )
                            local hits = probe.cast( frame, center + Vector( 0, 0.3 * track.values.trackWidth, 0 ), Vector( 0, 0, -1 ) )

                            expect( hits[1].t ).to.aboutEqual( radius, 0.05 )
                            expect( hits[2].t ).to.aboutEqual( radius + height, 0.05 )
                        end
                    end
                end
            end
        },

        {
            name = "Is as wide as the track width",
            func = function( state )
                for _, width in ipairs( { 24, 40 } ) do
                    local track = state.track( { values = { trackWidth = width } } ):build()
                    local frame = track:frame()

                    for _, side in ipairs( track:sides() ) do
                        local mins, maxs = probe.extents( frame, sideFilter( side ) )
                        local y = track:wheel( 1, side ).y

                        expect( mins.y ).to.aboutEqual( y - width * 0.5, 0.05 )
                        expect( maxs.y ).to.aboutEqual( y + width * 0.5, 0.05 )
                    end
                end
            end
        },

        {
            name = "Handles other track sizes",
            func = function( state )
                local track = state.track( { values = { trackWidth = 40, trackHeight = 6, trackRes = 5 } } ):build()
                expect( track:contactFailures( track:frame(), 0.5 ) ).to.equal( "" )
            end
        },

        {
            name = "Tells the wheels how far to sit above the ground",
            func = function( state )
                local track = state.track():build()
                local frame = track:frame()

                for _, i in ipairs( fixtures.roadwheels ) do
                    local center = track:wheel( i, 1 )
                    local bottom = probe.height( frame, center.x, center.y + 0.3 * track.values.trackWidth, false )
                    local clearance = track:groundHeight( i ) - ( center.z - bottom )

                    expect( clearance ).to.beBetween( 0, 0.2 )
                end
            end
        },

        {
            name = "Is drawn relative to the given matrix",
            func = function( state )
                local track = state.track():build()
                local flat = track:frame()

                local matrix = Matrix()
                matrix:SetTranslation( Vector( 100, -200, 300 ) )
                matrix:SetAngles( Angle( 10, 90, -20 ) )

                local moved = track:frame( matrix )

                expect( sameFrame( flat, moved, 0.001, function( v ) return matrix * v end ) ).to.equal( "" )
            end
        },

        {
            name = "Draws the same thing every frame while nothing changes",
            func = function( state )
                local track = state.track():build()
                local first = track:frame()

                expect( sameFrame( first, track:frame(), 0 ) ).to.equal( "" )

                track:think()
                track:think()

                expect( sameFrame( first, track:frame(), 0.001 ) ).to.equal( "" )
            end
        },
    }
}
