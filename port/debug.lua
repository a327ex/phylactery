--[[
  debug.lua -- the port to Anchor: tools for comparing with the three.js build (test-only).
  json(value) -> string; port_trace_frame(path): the next frame's draws (program key, uniforms,
  state) and clears written as JSON, for tools/port_compare.py against a GL capture.
]]
local D = {}

local function esc(s) return (s:gsub('[%c"\\]', function(c) return string.format('\\u%04x', c:byte()) end)) end
function D.json(v, out)
  out = out or {}
  local t = type(v)
  if t == 'nil' then out[#out + 1] = 'null'
  elseif t == 'boolean' then out[#out + 1] = v and 'true' or 'false'
  elseif t == 'number' then
    if v ~= v then out[#out + 1] = '"NaN"' elseif v == math.huge then out[#out + 1] = '"Infinity"' elseif v == -math.huge then out[#out + 1] = '"-Infinity"'
    else out[#out + 1] = string.format('%.9g', v) end
  elseif t == 'string' then out[#out + 1] = '"' .. esc(v) .. '"'
  elseif t == 'table' then
    if #v > 0 or next(v) == nil then
      out[#out + 1] = '['
      for i, e in ipairs(v) do if i > 1 then out[#out + 1] = ',' end; D.json(e, out) end
      out[#out + 1] = ']'
    else
      out[#out + 1] = '{'
      local first = true
      for k, e in pairs(v) do
        if not first then out[#out + 1] = ',' end
        first = false
        out[#out + 1] = '"' .. esc(tostring(k)) .. '":'
        D.json(e, out)
      end
      out[#out + 1] = '}'
    end
  else out[#out + 1] = '"' .. t .. '"' end
  return out
end
function D.encode(v) return table.concat(D.json(v)) end

-- the next rendered frame's trace (samplers written as "tex")
function port_trace_frame(path)
  G.trace_path = path
  G.R.renderer.trace = {}
end
function port_trace_flush()
  local tr = G.R.renderer.trace
  if not tr or not G.trace_path then return end
  for _, e in ipairs(tr) do
    if e.uniforms then for k, v in pairs(e.uniforms) do if type(v) == 'userdata' then e.uniforms[k] = 'tex' end end end
  end
  file_write_string(G.trace_path, D.encode(tr))
  G.R.renderer.trace = nil
  G.trace_path = nil
end

return D
