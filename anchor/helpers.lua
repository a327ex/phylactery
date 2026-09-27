--[[
  helpers — small shared utilities for game code.

  collection_update(list, dt, method?)
  Reverse iteration over a plain array of entities: removes entries with ._dead
  (set by process_destroy_queue after kill), otherwise calls :update(dt) or the
  given method name. Use for enemies, bullets, etc.
]]

function collection_update(list, dt, method)
  method = method or 'update'
  for i = #list, 1, -1 do
    local e = list[i]
    if e._dead then
      table.remove(list, i)
    else
      local fn = e[method]
      if fn then fn(e, dt) end
    end
  end
end
