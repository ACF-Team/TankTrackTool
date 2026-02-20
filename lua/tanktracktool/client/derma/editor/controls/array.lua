
local PANEL = {}

local function GetLabel( data, i, node )
    if istable( data.label ) then return data.label[i] or i end
    if isstring( data.label ) then return string.format( "%s [%d]", data.label, i ) end
    if isfunction( data.label ) then return data.label( i ) end
    return data.title or node:GetText()
end

function PANEL:Setup( editData )
    self:Clear()

    local function Paint( t, w, h )
        local sk = self:GetEditorSkin()

        surface.SetDrawColor( sk.colorTextEntry )
        surface.DrawRect( 0, 0, w, h )

        surface.SetDrawColor( 0, 0, 0, 50 )
        surface.DrawOutlinedRect( 0, 0, w, h )

        t:DrawTextEntryText( t:GetTextColor(), t:GetHighlightColor(), t:GetCursorColor() )
    end

    local editors = {}
    local count = tonumber( editData.count or 1 ) or 1
    local inner = {}

    for i = 1, count do
        local row = self:GetRow()
        local parent = row:AddNode( GetLabel( editData, i, row ) ).Container
        inner[i] = ""

        local panel = parent:Add( "DTextEntry" )
        editors[i] = panel

        panel:SetUpdateOnType( false )
        panel:SetPaintBackground( false )
        panel:Dock( FILL )

        panel.OnValueChange = function( _, val )
            inner[i] = val
            self:ValueChanged( inner )
        end

        panel.Paint = Paint
    end

    self.SetValue = function( self, val )
        for i = 1, #editors do
            inner[i] = val[i]
            editors[i]:SetText( util.TypeToString( val[i] ) )
        end
        self:Callback( editData, inner )
    end

    self.IsEditing = function( self )
        for i = 1, #editors do
            if editors[i]:IsEditing() then
                return true
            end
        end

        return false
    end

    self.IsEnabled = function( self )
        return editors[1]:IsEnabled()
    end

    self.SetEnabled = function( self, b )
        for i = 1, #editors do
            editors[i]:SetEnabled( b )
        end
    end
end

vgui.Register( "tanktracktoolEditor_Array", PANEL, "tanktracktoolEditor_Generic" )

