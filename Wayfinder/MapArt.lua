-- Complete cartography underneath exploration fog. Loading an artwork texture
-- never discovers its area: discovery still comes from the character's own data.
local _, ns = ...
local complete = {}

local function Key(info)
	return table.concat({info.textureWidth,info.textureHeight,info.offsetX,info.offsetY}, ":")
end

function ns.GetExplorationOverlays(mapID)
	local native = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures(mapID) or {}
	if ns:GetSetting("unexploredTerrain")==ns.UNEXPLORED_HIDDEN then return native end
	local art = C_Map.GetMapArtID and C_Map.GetMapArtID(mapID)
	local records = art and ns.MapOverlayData[art]
	if not records then return native end
	if not complete[art] then
		local result = {}
		for _,record in ipairs(records) do
			local files={};for i=5,#record do files[#files+1]=record[i] end
			result[#result+1]={textureWidth=record[1],textureHeight=record[2],
				offsetX=record[3],offsetY=record[4],fileDataIDs=files}
		end
		complete[art]=result
	end
	local found,result={},{}
	for _,overlay in ipairs(native) do found[Key(overlay)]=true end
	for _,overlay in ipairs(complete[art]) do
		if not found[Key(overlay)] then result[#result+1]=overlay end
	end
	-- Prefer the client's live metadata for anything it already exposes.
	for _,overlay in ipairs(native) do result[#result+1]=overlay end
	return result
end
