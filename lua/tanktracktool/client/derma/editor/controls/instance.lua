
local PANEL = {}

function PANEL:Init()
end

function PANEL:Setup( editData )
    self:Clear()

    editData = editData or {}

    local editor = self:Add( "DNumSlider" )

    editor:SetMin( editData.min or 0 )
    editor:SetMax( editData.max or 1 )

    local int = true
    editor:SetDecimals( 0 )

    editor:Dock( FILL )
    editor.TextArea:Dock( LEFT )
    editor.Label:Dock( RIGHT )

    editor:SetDark( true )

    editor.Slider.Knob:NoClipping( false )
    editor.Slider.UpdateNotches = function( s ) return s:SetNotches( 8 ) end
    editor.Slider:UpdateNotches()

    editor.Label:SetWide( 15 )
    editor.TextArea:SetWide( 50 )
    editor.TextArea:SetUpdateOnType( false )
    editor.Scratch:SetImageVisible( true )
    editor.Scratch:SetImage( "icon16/link.png" )

    editor.PerformLayout = function()
        editor.Scratch:SetVisible( true )
        editor.Label:SetVisible( true )
        editor.Slider:StretchToParent( 0, 0, 0, 0 )
        editor.Slider:SetSlideX( editor.Scratch:GetFraction() )
    end

    editor.TextArea.Paint = function( t, w, h )
        local sk = self:GetEditorSkin()

        surface.SetDrawColor( sk.colorTextEntry )
        surface.DrawRect( 0, 0, w, h )

        surface.SetDrawColor( 0, 0, 0, 50 )
        surface.DrawOutlinedRect( 0, 0, w, h )

        t:DrawTextEntryText( t:GetTextColor(), t:GetHighlightColor(), t:GetCursorColor() )
    end

    editor.OnValueChanged = function( _, newval )
        self:ValueChanged( math.floor( newval ) )
    end

    self.IsEnabled = function( _ )
        return editor:IsEnabled()
    end
    self.SetEnabled = function( _, b )
        editor:SetEnabled( b )
    end

    self.IsEditing = function( _ )
        return editor:IsEditing()
    end

    self.SetValue = function( _, val )
        editor:SetValue( val )
        self:Callback( editData, val )
    end

    self.Paint = function()
        local vis = self:IsEditing() or self:GetIsDragging() or self:GetRow():IsChildHovered()

        editor.Slider:SetVisible( vis )
        editor.Scratch:SetVisible( vis )
    end

    self.Instances = {}

    for i = 1, editData.max do
        local label = editData.label or editData.title or self:GetRow():GetText()
        if isfunction( label ) then label = label( i ) else label = string.format( "%s [%d]", label, i ) end
        self.Instances[i] = self:GetRow():AddNode( label )
        self.Instances[i].Categories = {}
    end
end

local function DoRightClick( self )
    if not self.i_inherit then return end

    if isstring( self.i_inherit ) then
        local menu = DermaMenu()

        menu:AddOption( "inherit " .. self:GetText() .. " value", function()
            self:DataChanged( self.Inner.m_Editor.m_Entity:netvar_get( self.i_inherit, nil ) )
        end ):SetImage( "icon16/connect.png" )

        menu:AddOption( "cancel", function() end ):SetImage( "icon16/cancel.png" )

        local x, y = self:LocalToScreen( self.Label:GetTextInset(), self.Label:GetTall() )
        menu:Open( x, y )
        return
    end

    if istable( self.i_inherit ) then
        local menu = DermaMenu()

        menu:AddOption( "inherit all values", function()
            for k, v in pairs( self.i_inherit ) do
                if self.i_table.Categories[k] then
                    self.i_table.Categories[k]:DataChanged( self.Inner.m_Editor.m_Entity:netvar_get( v, nil ) )
                end
            end
        end ):SetImage( "icon16/connect.png" )

        menu:AddOption( "cancel", function() end ):SetImage( "icon16/cancel.png" )

        local x, y = self:LocalToScreen( self.Label:GetTextInset(), self.Label:GetTall() )
        menu:Open( x, y )
    end
end

function PANEL:EditVariable( name, edit )
    local nodes = {}
    for i = 1, #self.Instances do
        local instance = self.Instances[i]
        local parent = instance.Categories[edit.category] or instance

        local child = parent:AddNode( edit.title or name )
        child:Setup( edit )
        child.DoRightClick = DoRightClick
        child.i_inherit = edit.inherit
        child.i_index = i
        child.i_table = instance

        instance.Categories[name] = child
        if parent ~= instance then
            if not parent.Categories then
                parent.Categories = {}
            end
            parent.Categories[name] = child
        end

        table.insert( nodes, child )
    end
    return nodes
end



vgui.Register( "tanktracktoolEditor_Instance", PANEL, "tanktracktoolEditor_Generic" )
