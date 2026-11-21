
local fixtures = include( "tests/tanktracktool/helpers/fixtures.lua" )
local probe = include( "tests/tanktracktool/helpers/probe.lua" )

local function bottomUnder( frame, track, i, side )
    local center = track:wheel( i, side )
    return probe.height( frame, center.x, center.y + 0.3 * track.values.trackWidth, false )
end

return {
    groupName = "tanktracktool.autotracks motion",

    beforeEach = function( state )
        state.backend, state.autotracks = fixtures.load()
        state.track = function( opts ) return fixtures.track( state.backend, state.autotracks, opts ) end
    end,

    cases = {
        {
            name = "Follows road wheels as the suspension moves",
            func = function( state )
                local track = state.track():build()
                local height = track.values.trackHeight

                track:moveWheel( 3, Vector( 0, 0, 6 ) )
                track:moveWheel( 5, Vector( 0, 0, -3 ) )
                track:think()

                local frame = track:frame()
                expect( track:contactFailures( frame, 0.5 ) ).to.equal( "" )

                for _, side in ipairs( track:sides() ) do
                    for _, i in ipairs( { 3, 5 } ) do
                        local center, radius = track:wheel( i, side )
                        expect( bottomUnder( frame, track, i, side ) ).to.aboutEqual( center.z - radius - height, 0.2 )
                    end
                end
            end
        },

        {
            name = "Follows a wheel back to where it started",
            func = function( state )
                local track = state.track():build()
                local before = bottomUnder( track:frame(), track, 4, 1 )

                for _, z in ipairs( { 2, 4, 6, 4, 2, 0, -2, 0 } ) do
                    track:moveWheel( 4, Vector( 0, 0, z ) )
                    track:think()
                    track:moveWheel( 4, Vector( 0, 0, -z ) )
                end
                track:think()

                local frame = track:frame()
                expect( bottomUnder( frame, track, 4, 1 ) ).to.aboutEqual( before, 0.001 )
                expect( track:contactFailures( frame, 0.5 ) ).to.equal( "" )
            end
        },

        {
            name = "Moves each side on its own",
            func = function( state )
                local track = state.track():build()
                local right = bottomUnder( track:frame(), track, 4, 2 )

                track:moveWheel( 4, Vector( 0, 0, 5 ), 1 )
                track:think()

                local frame = track:frame()
                local center, radius = track:wheel( 4, 1 )

                expect( bottomUnder( frame, track, 4, 1 ) ).to.aboutEqual( center.z - radius - track.values.trackHeight, 0.2 )
                expect( bottomUnder( frame, track, 4, 2 ) ).to.aboutEqual( right, 0.001 )
            end
        },

        {
            name = "Follows the idler and sprocket as they move",
            func = function( state )
                local track = state.track():build()

                track:moveWheel( 1, Vector( 6, 0, 3 ) )
                track:moveWheel( 7, Vector( -4, 0, -2 ) )
                track:think()

                expect( track:contactFailures( track:frame(), 0.5 ) ).to.equal( "" )
            end
        },
    }
}
