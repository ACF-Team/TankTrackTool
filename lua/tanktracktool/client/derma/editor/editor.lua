
--[[
    SETUP & SKIN
]]
local tanktracktool = tanktracktool
tanktracktool.editor = tanktracktool.editor or {}
local editor = tanktracktool.editor

editor.skin = {}
editor.skin.fontSmall = "tanktracktoolEditor_small"
editor.skin.fontLarge = "tanktracktoolEditor_large"
editor.skin.panelBevel = 4
editor.skin.colorHeader = Color( 122, 189, 254, 255 )
editor.skin.colorHeaderLight = Color( 122, 189, 254, 255 )
editor.skin.colorTextEntry = Color( 122, 189, 254, 50 )
editor.skin.colorBackground = Color( 245, 245, 245, 255 )
editor.skin.colorRowHighlight = Color( 122, 189, 254, 50 )

surface.CreateFont( editor.skin.fontSmall, { font = "Arial", size = 14 } )
surface.CreateFont( editor.skin.fontLarge, { font = "Arial Bold", size = 14 } )

editor.types = {}
editor.types.int = "Number"
editor.types.float = "Number"
editor.types.number = "Number"
editor.types.string = "Generic"
editor.types.bool = "Checkbox"
editor.types.boolean = "Checkbox"
editor.types.checkbox = "Checkbox"
editor.types.bitfield = "Bitfield"
editor.types.combo = "Combo"
editor.types.vector = "Vector"
editor.types.angle = "Vector"
editor.types.instance = "Instance"
editor.types.array = "Array"
editor.types.color = "Color"

function editor.openUI( ent )
    local frame = g_ContextMenu:Add( "DFrame" )
    local h = math.Round( ScrH() / 2 ) * 2
    local w = math.Round( ScrW() / 2 ) * 2

    local tall = math.Round( ( h * 0.8 ) / 2 ) * 2
    local wide = 400

    frame:SetSize( wide + 8, tall + 8 )
    frame:SetPos( w - wide - 50 - 4, h - 50 - tall - 4 )
    frame:SetSizable( true )

    local edit = frame:Add( "tanktracktoolEditor" )
    edit.frame = frame
    edit:SetupWindow()
    edit:SetEntity( ent )
    edit:Dock( FILL )
end

local cv_overlay = CreateClientConVar( "tanktracktool_editor_overlay", "1", true, false, "enable editor overlays" )
cvars.AddChangeCallback( "tanktracktool_editor_overlay", function( convar_name, value_old, value_new )
    if not tanktracktool.render then tanktracktool.render = {} end
    tanktracktool.render.overlay = tobool( value_new )
end )
if not tanktracktool.render then tanktracktool.render = {} end
tanktracktool.render.overlay = cv_overlay:GetBool()


--[[
    VGUI
]]

local PANEL = {}

function PANEL:GetEditorSkin()
    return editor.skin
end

function PANEL:PostNodeAdded( pNode )
end

function PANEL:OnEntityLost()
    self.frame:Remove()
end

function PANEL:OnWindowStopDragging()
end

function PANEL:Init()
    self:DockMargin( 0, 3, 0, 3 )
    self.RootNode:DockMargin( 0, 0, 0, 0 )
    self.Paint = nil

    self.VBar.SetEnabled = function( self, b )
        DVScrollBar.SetEnabled( self, true )
    end
    self.VBar:SetHideButtons( true )
end

function PANEL:PerformLayoutInternal()
    local Tall = self.pnlCanvas:GetTall()
    local Wide = self:GetWide()
    local YPos = 0

    self:Rebuild()

    self.VBar:SetUp( self:GetTall(), self.pnlCanvas:GetTall() )
    YPos = self.VBar:GetOffset()

    if self.VBar.Enabled then Wide = Wide - self.VBar:GetWide() - 3 end

    self.pnlCanvas:SetPos( 0, YPos )
    self.pnlCanvas:SetWide( Wide )

    self:Rebuild()

    if Tall ~= self.pnlCanvas:GetTall() then
        self.VBar:SetScroll( self.VBar:GetScroll() )
    end
end

function PANEL:OnNodeSelected(item)
    self:SetSelectedItem( nil )
end

function PANEL:OnRemove()
    if IsValid( self.m_Entity ) then
        if isfunction( self.m_Entity.netvar_callback ) then self.m_Entity:netvar_callback( "editor_close", self ) end
        self.m_Entity:RemoveCallOnRemove( "tanktracktoolEditor" )
    end
end

function PANEL:SetEntity( entity )
    if self.m_Entity == entity then return end

    if IsValid( self.m_Entity ) then
        self.m_Entity:RemoveCallOnRemove( "tanktracktoolEditor" )
    end

    if not IsValid( entity ) then return end

    self.m_Entity = entity
    self.m_Entity:CallOnRemove( "tanktracktoolEditor", function( e )
        timer.Simple( 0, function()
            if IsValid( e ) then return end

            if IsValid( self ) then
                self:GetParent():Remove()
            end
        end )
    end )

    self:GetParent():SetTitle( tostring( self.m_Entity ) )

    self:RebuildControls()
end

function PANEL:EntityLost()
    self:Clear()
    self:OnEntityLost()
end

function PANEL:AddNode( strName, strIcon )
    self.RootNode:CreateChildNodes()

    local pNode = vgui.Create( "tanktracktoolEditor_Category", self.RootNode )
    pNode:SetText( string.upper( strName ) )
    pNode:SetParentNode( self.RootNode )
    pNode:SetRoot( self.RootNode:GetRoot() )
    pNode.Label:SetFont( self:GetEditorSkin().fontLarge )

    self.RootNode:InstallDraggable( pNode )

    self.RootNode.ChildNodes:Add( pNode )
    self.RootNode:InvalidateLayout()

    self.RootNode:OnNodeAdded( pNode )

    return pNode
end

function PANEL:RebuildSettings()
    local cat = self:AddNode( "TOOL SETTINGS" )

    local node = cat:AddNode( "Enable Overlays" )
    node:Setup( { type = "checkbox" } )

    node.DataUpdate = function( _ )
        if not IsValid( self.m_Entity ) then self:EntityLost() return end
        node:SetValue( cv_overlay:GetBool() )
    end
    node.DataChanged = function( _, val )
        if not IsValid( self.m_Entity ) then self:EntityLost() return end
        self.m_Entity:netvar_callback( "editor_setting", self, self.m_Entity, "overlay", tobool( val ) )
        cv_overlay:SetBool( tobool( val ) )
    end
end

function PANEL:RebuildControls()
    self.coroutine = coroutine.create( function()
        self:Clear()

        if not IsValid( self.m_Entity ) then coroutine.yield( true ) end
        if not istable( self.m_Entity.netvar ) then coroutine.yield( true ) end

        self:SetDisabled( true )
        self.mywindow.btnClose:SetImage( "gui/point.png" )

        local editor = self.m_Entity.netvar

        self.m_iLabelWidth = 0

        self:RebuildSettings()

        self.Categories = {}
        self.Variables  = {}

        for _, edit in ipairs( editor.variables.data.n ) do
            self:EditVariable( edit )
            coroutine.yield( false )
        end

        self:SetDisabled( false )
        self.m_Entity:netvar_callback( "editor_open", self )

        coroutine.yield( true )
    end )
end

function PANEL:Think()
    if not self.coroutine then return end

    local t = SysTime()

    while SysTime() - t < 0.01 do
        local a, b = coroutine.resume( self.coroutine )
        if not a or b then
            self.coroutine = nil
            self.mywindow.btnClose:SetImage( "gui/cross.png" )
            break
        end
    end
end

function PANEL:EditVariable( edit )
    local data = edit.data
    local name = edit.name

    if edit.parent then
        local variables = self.Variables[edit.parent.name].Inner:EditVariable( name, data )
        for i, v in ipairs( variables ) do
            v.DataUpdate = function( _ )
                if not IsValid( self.m_Entity ) then self:EntityLost() return end
                v:SetValue( self.m_Entity:netvar_get( name, i ) )
            end

            v.DataChanged = function( _, val )
                if not IsValid( self.m_Entity ) then self:EntityLost() return end
                self.m_Entity:netvar_callback( "editor_edit", self, v, data, name, i, val )
                self.m_Entity:netvar_edit( name, i, val )
            end
        end
    else
        local category = data.category or "GENERAL"
        if not self.Categories[category] then
            self.Categories[category] = self:AddNode( category )
            self.Categories[category].nonvar = true
            self.Categories[category].Categories = {}
        end

        local parent = self.Categories[category]
        local subcategory = data.subcategory
        if subcategory then
            if not self.Categories[category].Categories[subcategory] then
                self.Categories[category].Categories[subcategory] = self.Categories[category]:AddNode( subcategory )
                self.Categories[category].Categories[subcategory].nonvar = true
            end
            parent = self.Categories[category].Categories[subcategory]
        end

        local variable = parent:AddNode( data.title or name )
        variable:Setup( data )
        self.Variables[name] = variable

        variable.DataUpdate = function( _ )
            if not IsValid( self.m_Entity ) then self:EntityLost() return end
            variable:SetValue( self.m_Entity:netvar_get( name ) )
        end

        variable.DataChanged = function( _, val )
            if not IsValid( self.m_Entity ) then self:EntityLost() return end
            self.m_Entity:netvar_callback( "editor_edit", self, variable, data, name, nil, val )
            self.m_Entity:netvar_edit( name, nil, val )
        end
    end
end

function PANEL:OnNodeAdded( pNode )
    local lw = pNode.Label:GetTextSize()
    local ix = pNode.Label:GetTextInset()
    local ew = pNode.Expander:IsVisible() and pNode.Expander:GetWide() or 0
    local iw = pNode.Icon:IsVisible() and pNode.Icon:GetWide() or 0

    local x = ( lw + ix + ew + iw ) + ( pNode.m_iNodeLevel or 0 ) * 16

    if self.m_iLabelWidth < x then
        self.m_iLabelWidth = x
    end

    pNode.m_Editor = self

    self:PostNodeAdded( pNode )
end

function PANEL:GetLabelWidth()
    return self.m_iLabelWidth
end

function PANEL:SetupWindow()
    local window = self:GetParent()
    if not IsValid( window ) then return end
    self.mywindow = window

    local header = 24
    local footer = 12

    window:DockPadding( 4, header, 4, footer )

    window.GetEditorSkin = self.GetEditorSkin

    local color_faded = Color( 120, 120, 120, 255 )

    local function Box( bevel, x, y, w, h, color, ... )
        if bevel then
            draw.RoundedBoxEx( bevel, x, y, w, h, color_faded, ... )
            draw.RoundedBoxEx( bevel, x + 1, y + 1, w - 2, h - 2, color, ... )
        else
            surface.SetDrawColor( color_faded )
            surface.DrawRect( x, y, w, h )
            surface.SetDrawColor( color )
            surface.DrawRect( x + 1, y + 1, w - 2, h - 2)
        end
    end

    window.Paint = function( pnl, w, h )
        local sk = pnl:GetEditorSkin()

        Box( sk.panelBevel, 0, 0, w, header, sk.colorHeader, true, true, false, false )
        Box( sk.panelBevel, 0, h - footer, w, footer, sk.colorHeader, false, false, true, true )
        Box( false, 0, header - 1, w, h - footer - header + 2, sk.colorBackground )
    end

    window.lblTitle:SetFont( self:GetEditorSkin().fontSmall )
    window.lblTitle:SetColor( color_white )
    window.lblTitle:SetTextInset( 4, 0 )
    window.lblTitle:SetContentAlignment( 5 )

    window.btnMinim:Remove()
    window.btnMaxim:Remove()
    window.btnClose:Remove()

    window.btnClose = vgui.Create( "DImageButton", window )
    window.btnClose:SetImage( "gui/cross.png" )
    window.btnClose.DoClick = function()
        window:Remove()
    end

    window.PerformLayout = function( _, w, h )
        window.lblTitle:SetPos( 0, 0 )
        window.lblTitle:SetSize( w - 20, header )

        window.btnClose:SetPos( w - 16 - 4, 4 )
        window.btnClose:SetSize( 16, 16 )
    end

    window.Think = function()
        DFrame.Think( window )

        if window.Dragging then
            self.m_bIsDragging = true
        elseif self.m_bIsDragging then
            self:WindowStopDragging()
            self.m_bIsDragging = nil
        end
    end
end

function PANEL:WindowStopDragging()
    self:OnWindowStopDragging()
end

vgui.Register( "tanktracktoolEditor", PANEL, "DTree" )
