-- ImageLand Sprite Manager by Lukiiy (https://github.com/Lukiiy)

local imageLand = {}
imageLand.__index = imageLand

-- [Internal Use] Resizes image while preserving aspect ratio
local function resizeImg(image, targetSize)
    local ogWidth, ogHeight = image:getDimensions()
    local scale = targetSize / math.min(ogWidth, ogHeight) -- match spriteManager

    local newWidth = ogWidth * scale
    local newHeight = ogHeight * scale

    local canvas = love.graphics.newCanvas(targetSize, targetSize)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)

    local offsetX = (targetSize - newWidth) / 2
    local offsetY = (targetSize - newHeight) / 2

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, offsetX, offsetY, 0, scale, scale)
    love.graphics.setCanvas()

    return love.graphics.newImage(canvas:newImageData())
end

-- Combines sprites into single atlas texture  
-- (sprites: Sprite data table, atlasSize: Atlas dimensions in pixels)
local function createAtlas(sprites, atlasSize)
    atlasSize = atlasSize or 512
    local canvas = love.graphics.newCanvas(atlasSize, atlasSize)

    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)

    local x, y = 0, 0
    local rowHeight = 0
    local atlasData = {}

    for id, sprite in pairs(sprites) do
        local w, h = sprite.image:getDimensions()

        if x + w > atlasSize then -- next row if no fit
            x = 0
            y = y + rowHeight
            rowHeight = 0
        end

        love.graphics.draw(sprite.image, x, y)

        -- Store coords
        atlasData[id] = {
            x = x / atlasSize,
            y = y / atlasSize,
            w = w / atlasSize,
            h = h / atlasSize,
            metadata = sprite.metadata
        }

        x = x + w
        rowHeight = math.max(rowHeight, h)
    end

    love.graphics.setCanvas()

    return love.graphics.newImage(canvas:newImageData()), atlasData
end

-- Creates new sprite manager instance  
-- (defPath: Base path for the sprites, options: Settings {defPath, atlasSize})
function imageLand.new(defPath, options)
    options = options or {}
    local self = setmetatable({}, imageLand)

    self.defSize = options.defSize or 16
    self.defPath = defPath or ""
    self.atlasSize = options.atlasSize or 512
    self.registry = {}
    self.sprites = {}
    self.atlas = nil
    self.atlasData = {}
    self.needsRebuild = false

    return self
end

-- Adds sprite from file to manager  
-- (file: Image file to get from the set path, customId: Override sprite id)
function imageLand:add(file, customId)
    if not file:match("%.%w+$") then file = file .. ".png" end -- defaults to .png

    self:addFromPath(self.defPath .. file, customId or file)
end

-- Adds sprite from file to manager  
-- (file: Image file with path, customId: Override sprite id)
function imageLand:addFromPath(file, customId)
    local id = customId or file:match("([^/\\]+)%.%w+$") -- file without extension

    if not love.filesystem.getInfo(file) then error("Sprite file not found: " .. file) end

    local image = love.graphics.newImage(file)
    local width, height = image:getDimensions()
    local size = self.defSize

    if width ~= height then
        if width % height == 0 or height % width == 0 then
            size = math.min(width, height)
        else
            size = math.max(width, height)
        end
    end

    if width ~= size or height ~= size then image = resizeImg(image, size) end

    self.sprites[id] = {
        image = image,
        data = {}
    }

    self.needsRebuild = true

    return id
end

-- Sets data for a sprite  
-- (id: Sprite id, data: Data table)
function imageLand:setData(id, data)
    if self.sprites[id] then self.sprites[id].metadata = data end
end

-- Gets data for a sprite  
-- (id: Sprite id)
function imageLand:getData(id)
    return self.sprites[id] and self.sprites[id].metadata or {}
end

-- Builds sprite atlas from loaded sprites
function imageLand:buildAtlas()
    if not self.needsRebuild then return end

    self.atlas, self.atlasData = createAtlas(self.sprites, self.atlasSize)
    self.needsRebuild = false
end

-- Gets sprite data with atlas and UV coordinates  
-- (id: Sprite id)
function imageLand:get(id)
    if not self.atlas or self.needsRebuild then self:buildAtlas() end

    return {
        atlas = self.atlas,
        uv = self.atlasData[id],
        metadata = self.atlasData[id] and self.atlasData[id].metadata or {}
    }
end

-- Creates quad for sprite from atlas  
-- (id: Sprite id)
function imageLand:getQuad(id)
    if self.needsRebuild then self:buildAtlas() end

    local uv = self.atlasData[id]
    if not uv then return nil end

    local atlasW, atlasH = self.atlas:getDimensions()

    return love.graphics.newQuad(
        uv.x * atlasW, uv.y * atlasH,
        uv.w * atlasW, uv.h * atlasH,
        atlasW, atlasH
    )
end

-- Gets all sprites from a column  
-- (columnIndex: Column position; starts at 0)
function imageLand:getColumn(columnIndex)
    return self:getSpritesByAxis(columnIndex, "x")
end

-- Gets all sprites from atlas row  
-- (rowIndex: Row position; starts at 0)
function imageLand:getRow(rowIndex)
    return self:getSpritesByAxis(rowIndex, "y")
end

-- [Internal Usage] Gets all sprites from a given row or column
-- (index: row/column position; starts at 0, axis: "x" or "y")
function imageLand:getSpritesByAxis(index, axis)
    if self.needsRebuild then self:buildAtlas() end

    local sprites = {}
    local spriteSize = self.defSize / self.atlasSize
    local target = index * spriteSize

    for id, uv in pairs(self.atlasData) do
        if math.abs(uv[axis] - target) < 0.001 then
            table.insert(sprites, id)
        end
    end

    local otherAxis = (axis == "x") and "y" or "x"
    table.sort(sprites, function(a, b)
        return self.atlasData[a][otherAxis] < self.atlasData[b][otherAxis]
    end)

    return sprites
end


-- Draws sprite from atlas
function imageLand:draw(id, x, y, r, sx, sy, ox, oy)
    if not self.atlas or self.needsRebuild then self:buildAtlas() end

    local quad = self:getQuad(id)
    if quad and self.atlas then love.graphics.draw(self.atlas, quad, x, y, r or 0, sx or 1, sy or 1, ox or 0, oy or 0) end
end

-- Creates new sprite batch
function imageLand:newBatch()
    if self.needsRebuild then self:buildAtlas() end

    if not self.atlas then return nil end
    return love.graphics.newSpriteBatch(self.atlas)
end

-- Adds sprite to batch for rendering
function imageLand:addToBatch(batch, id, x, y, r, sx, sy, ox, oy)
    local quad = self:getQuad(id)

    if quad then batch:add(quad, x, y, r or 0, sx or 1, sy or 1, ox or 0, oy or 0) end
end

-- Gets atlas texture
function imageLand:getAtlas()
    if self.needsRebuild then self:buildAtlas() end

    return self.atlas
end

-- Saves atlas texture to a file
-- (filename: Output file name)
function imageLand:saveAtlas(filename)
    if self.needsRebuild then self:buildAtlas() end

    if self.atlas then self.atlas:newImageData():encode('png', filename or 'atlas.png') end
end

return imageLand