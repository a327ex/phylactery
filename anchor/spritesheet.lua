--[[
  spritesheet — thin wrapper for C spritesheet handles.

  Usage:
    spritesheets.hit = spritesheet_register('hit', 'assets/hit1.png', 96, 48)
    layer_spritesheet(game_layer, spritesheets.hit, 1, 100, 100)

  A spritesheet is a plain wrapper with .handle, .frame_width, .frame_height, .frames.
]]

---@class Spritesheet
---@field handle lightuserdata
---@field frame_width integer
---@field frame_height integer
---@field frames integer

spritesheet = class()

---@param handle lightuserdata
function spritesheet:new(handle)
  self.handle = handle
  self.frame_width = spritesheet_get_frame_width(handle)
  self.frame_height = spritesheet_get_frame_height(handle)
  self.frames = spritesheet_get_total_frames(handle)
end

-- Load a spritesheet from a file, wrap it, and add to the global `spritesheets` table.
-- (Named _register instead of _load to avoid colliding with the C `spritesheet_load`.)
---@param name string
---@param path string
---@param frame_w integer
---@param frame_h integer
---@return Spritesheet
function spritesheet_register(name, path, frame_w, frame_h)
  local handle = spritesheet_load(path, frame_w, frame_h)
  local sheet = spritesheet(handle)
  if spritesheets then spritesheets[name] = sheet end
  return sheet
end
