local ns,map=Wayfinder,WorldMapFrame
local S=ns.ContinuousEngine.MapStitch
local controller=ns.ContinuousEngine:GetModule("worldmap")
local passed,failed=0,0
local function test(name,fn)
	local ok,err=pcall(fn)
	if ok then passed=passed+1;io.write("  ok    ",name,"\n")
	else failed=failed+1;io.write("  FAIL  ",name,"\n        ",tostring(err),"\n") end
end
ns:SetSetting("importExploration",false)
ns.Exploration:Reset()
local native={}
local originalArt=C_Map.GetMapArtID
C_Map.GetMapArtID=function(id) return id==1411 and 2169 or originalArt and originalArt(id) end
C_MapExplorationInfo.GetExploredMapTextures=function() return native end
local function Show()
	map:Show()
	local u,v=ns.ContinuousMap.API.WorldFromMap(1411,.5,.5)
	controller.ShowNow(u,v,controller.FitZoom(1411))
	mock.Advance(.2)
	S.RefreshExplored()
end
local function ArtFrame()
	local file=C_Map.GetMapArtLayerTextures(1411,1)[1]
	for _,frame in ipairs(S.root.children) do
		for _,tex in ipairs(frame.textures or {}) do if tex:GetTexture()==file then return frame end end
	end
	error("Durotar artwork missing")
end
local function HasFile(file)
	for _,tex in ipairs(ArtFrame().textures) do if tex:IsShown() and tex:GetTexture()==file then return true end end
	return false
end
test("a fresh unexplored zone shows complete cartography under dark fog by default",function()
	assert(ns:GetSetting("unexploredTerrain")==ns.UNEXPLORED_DARKENED)
	assert(#native==0,"the character has not discovered any of the zone's artwork")
	Show()
	assert(HasFile(8073637) and HasFile(8074091) and HasFile(8074092),"whole zone artwork loads, including multi-tile overlays")
	assert(ns.WorldFog.frame:IsShown(),"unexplored artwork retains exploration shading")
	assert(ns.WorldFog.frame:GetFrameLevel()>ArtFrame():GetFrameLevel(),"dark fog stays above revealed cartography")
end)
test("revealing cartography never discovers terrain or services",function()
	local cells=ns.Exploration:CountExploredCells()
	local pois=0;for _ in pairs(ns.db.pois) do pois=pois+1 end
	for _=1,5 do ns.GetExplorationOverlays(1411);S.RefreshExplored() end
	assert(ns.Exploration:CountExploredCells()==cells)
	local after=0;for _ in pairs(ns.db.pois) do after=after+1 end
	assert(after==pois,"artwork does not import service locations")
end)
test("the live client metadata replaces matching stored overlays",function()
	local entry=ns.MapOverlayData[2169][1]
	native={{textureWidth=entry[1],textureHeight=entry[2],offsetX=entry[3],offsetY=entry[4],fileDataIDs={8999911}}}
	local overlays=ns.GetExplorationOverlays(1411)
	assert(#overlays==#ns.MapOverlayData[2169],"matching native and stored artwork never doubles up")
	Show()
	assert(HasFile(8999911) and not HasFile(entry[5]),"live client texture takes precedence")
end)
test("hidden mode keeps the native undiscovered map and darkened mode restores full artwork immediately",function()
	native={}
	ns:SetSetting("unexploredTerrain",ns.UNEXPLORED_HIDDEN);mock.Advance(.1)
	assert(#ns.GetExplorationOverlays(1411)==0 and not HasFile(8073637))
	ns:SetSetting("unexploredTerrain",ns.UNEXPLORED_DARKENED);mock.Advance(.1)
	assert(HasFile(8073637),"ordinary-map reveal follows the setting without reopening the map")
	ns:SetSetting("unexploredTerrain",ns.UNEXPLORED_SHOWN);mock.Advance(.1)
	assert(HasFile(8073637) and not ns.WorldFog.frame:IsShown(),"shown mode keeps cartography at full brightness")
end)
test("unknown or unavailable map art IDs retain the client's own overlays",function()
	native={{textureWidth=128,textureHeight=128,offsetX=0,offsetY=0,fileDataIDs={8999912}}}
	C_Map.GetMapArtID=function() return 99999999 end
	assert(ns.GetExplorationOverlays(1411)==native)
	C_Map.GetMapArtID=nil
	assert(ns.GetExplorationOverlays(1411)==native)
end)
assert(#mock.errors==0,"no asynchronous errors")
io.write("\n",passed," complete map artwork checks passed, ",failed," failed\n")
return failed
