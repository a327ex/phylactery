--[[
  image — thin wrapper for GPU texture handles.

  Usage:
    images.player = image_load('player', 'assets/player.png')
    layer_image(game_layer, images.player, 100, 100)

  An image is a plain table with .handle, .width, .height.
]]

---@class Image
---@field handle lightuserdata   the engine texture
---@field width integer
---@field height integer

image = class()

---@param handle lightuserdata
function image:new(handle)
  self.handle = handle
  self.width = texture_get_width(handle)
  self.height = texture_get_height(handle)
end

-- Load a texture from a file, wrap it, and add to the global `images` table.
-- `filter` (optional): 'smooth'/'linear' -> mipmapped linear (photos/large images,
-- smooth downscaling); default -> NEAREST (crisp pixel art).
---@param name string
---@param path string
---@param filter? string
---@return Image   (on the web only: nil while the file is still fetching — the renderer retries)
function image_load(name, path, filter)
  local handle = texture_load(path, filter)
  ---@diagnostic disable-next-line: return-type-mismatch   (web-only nil: the renderer retries next frame)
  if not handle then return nil end   -- web: texture not loaded yet (async fetch pending/failed) -> caller retries
  local img = image(handle)
  if images then images[name] = img end
  return img
end

-- Load an image resampled (high-quality, gamma-correct) to at most (w, h) device
-- pixels — browser-quality downscaling to display size. Use with image_info(path)
-- to get the source dimensions for layout first.
---@param name string
---@param path string
---@param w number
---@param h number
---@return Image   (on the web only: nil while the file is still fetching — the renderer retries)
function image_load_fit(name, path, w, h)
  local handle = texture_load_fit(path, math.floor(w + 0.5), math.floor(h + 0.5))
  ---@diagnostic disable-next-line: return-type-mismatch   (web-only nil: the renderer retries next frame)
  if not handle then return nil end   -- web: texture not loaded yet (async fetch pending/failed) -> caller retries
  local img = image(handle)
  if images then images[name] = img end
  return img
end
