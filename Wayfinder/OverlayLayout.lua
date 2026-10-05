-- Texture geometry from the client's explored-texture metadata. No UI mixins.
local _, ns = ...

local function StorageSize(pixels)
	return math.max(16, 2 ^ math.ceil(math.log(pixels) / math.log(2)))
end

-- Enumerate row-major tiles by clipping their nominal rectangle to the image.
function ns.LayoutExplorationOverlay(info, tileWidth, tileHeight, emit)
	if info.isShownByMouseOver or tileWidth <= 0 or tileHeight <= 0 or
		info.textureWidth <= 0 or info.textureHeight <= 0 then return end
	local columns = math.ceil(info.textureWidth / tileWidth)
	for index = 1, columns * math.ceil(info.textureHeight / tileHeight) do
		local column = (index - 1) % columns
		local row = math.floor((index - 1) / columns)
		local width = math.min(tileWidth, info.textureWidth - column * tileWidth)
		local height = math.min(tileHeight, info.textureHeight - row * tileHeight)
		local fileID = info.fileDataIDs and info.fileDataIDs[index]
		if fileID then
			local storedWidth = column == columns - 1 and StorageSize(width) or tileWidth
			local storedHeight = row == math.ceil(info.textureHeight / tileHeight) - 1 and StorageSize(height) or tileHeight
			emit(fileID, info.offsetX + column * tileWidth, info.offsetY + row * tileHeight,
				width, height, width / storedWidth, height / storedHeight, info.isDrawOnTopLayer and 2 or 1)
		end
	end
end
