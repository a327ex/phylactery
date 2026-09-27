--[[
  Array utilities for the list/array part of Lua tables.

  All operations that modify the array do so in-place.
  If you need to preserve the original, copy it first.

  Array functions:
    all                       - check if all elements pass predicate
    any                       - check if any element passes predicate
    average                   - compute average of values
    count                     - count elements or occurrences
    delete                    - remove all instances of value
    flatten                   - flatten nested arrays
    get                       - get element(s) by index with negative support
    get_circular_buffer_index - wrap index for circular buffer
    has                       - check if element exists
    index                     - find first index of element
    join                      - concatenate to string
    max                       - find maximum value
    print                     - debug print array
    random                    - get random element(s)
    remove                    - remove element at index
    remove_random             - remove random element(s)
    reverse                   - reverse array order
    rotate                    - shift elements circularly
    shuffle                   - randomize order
    sum                       - compute sum of values

  Table utilities:
    table.copy     - deep copy a table
    table.tostring - convert table to string
]]

array = {}

--[[
  Passes each element to the given function.
  Returns true if the function never returns false or nil.

  Usage:
    array.all({1, 2, 3}, function(v) return v > 0 end)         -- true
    array.all({1, 2, 3}, function(v) return v < 2 end)         -- false

  Parameters:
    t - array to check
    f - predicate function(value, index) returning boolean

  Returns: true if all elements pass, false otherwise, nil if t is nil
]]
function array.all(t, f)
  if not t then return nil end
  for i = 1, #t do
    if not f(t[i], i) then return false end
  end
  return true
end

--[[
  Passes each element to the given function.
  Returns true if the function returns true at least once.

  Usage:
    array.any({1, 2, 3}, function(v) return v > 2 end)         -- true
    array.any({1, 2, 3}, function(v) return v > 5 end)         -- false

  Parameters:
    t - array to check
    f - predicate function(value, index) returning boolean

  Returns: true if any element passes, false otherwise, nil if t is nil
]]
function array.any(t, f)
  if not t then return nil end
  for i = 1, #t do
    if f(t[i], i) then return true end
  end
  return false
end

--[[
  Returns the average of the values in the array.

  Usage:
    array.average({1, 3})    -- 2
    array.average({-3, 3})   -- 0

  Parameters:
    t - array of numbers

  Returns: average value, nil if array is empty
]]
function array.average(t)
  if #t == 0 then return nil end
  local sum = 0
  for _, v in ipairs(t) do
    sum = sum + v
  end
  return sum/#t
end

--[[
  Counts elements in the array.
  - No argument: returns array length
  - Value argument: counts occurrences of that value
  - Function argument: counts elements for which function returns true

  Usage:
    array.count({1, 1, 2})                                         -- 3
    array.count({1, 1, 2}, 1)                                      -- 2
    array.count({1, 1, 2, 3, 4, 4}, function(v) return v > 3 end)  -- 2

  Parameters:
    t - array to count
    v - (optional) value to count, or predicate function(value, index)

  Returns: count
]]
function array.count(t, v)
  if not v then return #t end
  if type(v) == 'function' then
    local count = 0
    for i = 1, #t do
      if v(t[i], i) then count = count + 1 end
    end
    return count
  else
    local count = 0
    for i = 1, #t do
      if t[i] == v then count = count + 1 end
    end
    return count
  end
end

--[[
  Deletes all instances of element v from the array.
  Modifies the array in place.

  Usage:
    t = {1, 2, 1, 3, 1}
    array.delete(t, 1)  -- returns 3, t is now {2, 3}

  Parameters:
    t - array to modify
    v - value to remove

  Returns: number of removed elements
]]
function array.delete(t, v)
  local count = 0
  for i = #t, 1, -1 do
    if t[i] == v then
      table.remove(t, i)
      count = count + 1
    end
  end
  return count
end

--[[
  Returns a new array that is a flattened version of the input.
  Extracts elements from nested arrays up to the specified level.

  Usage:
    array.flatten({1, 2, {3, 4}})           -- {1, 2, 3, 4}
    array.flatten({1, {2, {3, {4}}}})       -- {1, 2, 3, 4}
    array.flatten({1, {2, {3, {4}}}}, 1)    -- {1, 2, {3, {4}}}

  Parameters:
    t     - array to flatten
    level - (optional) recursion depth, default 1000

  Behavior:
    - Tables with metatables (objects) are not flattened
    - Returns a new array, does not modify original

  Returns: flattened array, nil if t is nil
]]
function array.flatten(t, level)
  if not t then return nil end
  level = level or 1000
  local out = {}
  local stack = {}
  local levels = {}
  for i = #t, 1, -1 do
    table.insert(stack, t[i])
    table.insert(levels, 0)
  end
  while #stack > 0 do
    local v = table.remove(stack)
    local current_level = table.remove(levels)
    if type(v) == 'table' and not getmetatable(v) and current_level < level then
      for i = #v, 1, -1 do
        table.insert(stack, v[i])
        table.insert(levels, current_level + 1)
      end
    else
      table.insert(out, v)
    end
  end
  return out
end

--[[
  Returns element(s) from the array by index.
  Supports negative indexes (-1 = last element).

  Usage:
    array.get({4, 3, 2, 1}, 1)       -- 4
    array.get({4, 3, 2, 1}, -1)      -- 1 (last)
    array.get({4, 3, 2, 1}, 1, 3)    -- {4, 3, 2}
    array.get({4, 3, 2, 1}, 2, -1)   -- {3, 2, 1}

  Parameters:
    t - array
    i - start index (negative counts from end)
    j - (optional) end index (negative counts from end)

  Behavior:
    - Single index returns single value
    - Range returns new array with values in that range (inclusive)

  Returns: value or array of values, nil if index invalid
]]
function array.get(t, i, j)
  if not i then return nil end
  if i < 0 then i = #t + i + 1 end
  if not j then return t[i] end
  if j < 0 then j = #t + j + 1 end
  if i == j then return t[i] end
  local out = {}
  local step = j > i and 1 or -1
  for k = i, j, step do
    table.insert(out, t[k])
  end
  return out
end

--[[
  Returns a normalized index for circular buffer access.
  Wraps indexes that go beyond array bounds.

  Usage:
    array.get_circular_buffer_index({'a', 'b', 'c'}, 1)   -- 1
    array.get_circular_buffer_index({'a', 'b', 'c'}, 0)   -- 3 (wraps to end)
    array.get_circular_buffer_index({'a', 'b', 'c'}, 4)   -- 1 (wraps to start)

  Parameters:
    t - array (used for length)
    i - index to normalize

  Returns: normalized index (1 to #t), nil if array is empty
]]
function array.get_circular_buffer_index(t, i)
  if not t then return nil end
  if #t == 0 then return nil end
  return ((i - 1) % #t) + 1
end

--[[
  Returns true if an element exists in the array.

  Usage:
    array.has({1, 2, 3}, 2)                                     -- true
    array.has({1, 2, 3}, 5)                                     -- false
    array.has({1, 2, 3, 4}, function(v) return v > 3 end)       -- true

  Parameters:
    t - array to search
    v - value to find, or predicate function(value)

  Returns: true if found, false otherwise
]]
function array.has(t, v)
  if not v or #t < 1 then return false end
  if type(v) == 'function' then
    for i = 1, #t do
      if v(t[i]) then return true end
    end
  else
    for i = 1, #t do
      if t[i] == v then return true end
    end
  end
  return false
end

--[[
  Returns the index of the first matching element.

  Usage:
    array.index({2, 1, 2}, 2)                                          -- 1
    array.index({2, 1}, 1)                                             -- 2
    array.index({4, 4, 4, 2, 1}, function(v) return v % 2 == 1 end)   -- 5

  Parameters:
    t - array to search
    v - value to find, or predicate function(value)

  Returns: index of first match, nil if not found
]]
function array.index(t, v)
  if not v or #t < 1 then return nil end
  if type(v) == 'function' then
    for i = 1, #t do
      if v(t[i]) then return i end
    end
  else
    for i = 1, #t do
      if t[i] == v then return i end
    end
  end
  return nil
end

--[[
  Joins array elements into a string.

  Usage:
    array.join({1, 2, 3})           -- '123'
    array.join({1, 2, 3}, ', ')     -- '1, 2, 3'

  Parameters:
    t         - array to join
    separator - (optional) string between elements, default ''

  Returns: concatenated string
]]
function array.join(t, separator)
  separator = separator or ''
  local s = ''
  for i = 1, #t do
    s = s .. tostring(t[i])
    if i < #t then s = s .. separator end
  end
  return s
end

--[[
  Returns the maximum value in the array.
  Optionally uses a function to extract comparison values.

  Usage:
    array.max({1, 5, 3})                                            -- 5
    array.max({{a = 1}, {a = 4}, {a = 2}}, function(v) return v.a end)  -- {a = 4}

  Parameters:
    t - array of values
    f - (optional) function(value) returning comparison value

  Returns: element with maximum value, nil if array is empty
]]
function array.max(t, f)
  if #t == 0 then return nil end
  if f then
    local max_val = f(t[1])
    local max_elem = t[1]
    for i = 2, #t do
      local val = f(t[i])
      if val > max_val then
        max_val = val
        max_elem = t[i]
      end
    end
    return max_elem
  else
    local max_elem = t[1]
    for i = 2, #t do
      if t[i] > max_elem then max_elem = t[i] end
    end
    return max_elem
  end
end

--[[
  Prints the array and returns its string representation.

  Usage:
    array.print({1, 2, 3})  -- prints and returns '{[1] = 1, [2] = 2, [3] = 3}'

  Parameters:
    t - array to print

  Returns: string representation
]]
function array.print(t)
  local s = table.tostring(t)
  print(s)
  return s
end

--[[
  Returns n random elements from the array.
  Elements come from unique indexes (no duplicates).

  Usage:
    array.random({1, 2, 3})        -- random element
    array.random({1, 2, 3}, 2)     -- {random, random} (2 unique elements)

  Parameters:
    t   - array to sample from
    n   - (optional) number of elements, default 1
    rng - (optional) rng handle from random_create; nil uses global_rng

  Behavior:
    - n=1 returns single element (not array)
    - n>1 returns array of unique elements
    - If n > #t, returns all elements in random order

  Returns: element or array of elements, nil if array is empty
]]
function array.random(t, n, rng)
  if #t == 0 then return nil end
  n = n or 1
  if n == 1 then
    return t[random_int(1, #t, rng)]
  else
    local out = {}
    local selected = {}
    while #out < n and #selected < #t do
      local i = random_int(1, #t, rng)
      if not array.has(selected, i) then
        table.insert(selected, i)
        table.insert(out, t[i])
      end
    end
    return out
  end
end

--[[
  Removes an element from the array at a specific position.
  This is equivalent to Lua's table.remove.

  Usage:
    t = {3, 2, 1}
    array.remove(t, 1)  -- returns 3, t is now {2, 1}

  Parameters:
    t - array to modify
    i - index to remove

  Returns: removed element
]]
function array.remove(t, i)
  return table.remove(t, i)
end

--[[
  Removes and returns n random elements from the array.

  Usage:
    t = {1, 2, 3, 4, 5}
    array.remove_random(t)        -- returns random element, t has 4 elements
    array.remove_random(t, 2)     -- returns {random, random}, t has 2 elements

  Parameters:
    t   - array to modify
    n   - (optional) number of elements, default 1
    rng - (optional) rng handle from random_create; nil uses global_rng

  Behavior:
    - n=1 returns single element (not array)
    - n>1 returns array of removed elements
    - Modifies array in place

  Returns: element or array of elements
]]
function array.remove_random(t, n, rng)
  if #t == 0 then return nil end
  n = n or 1
  if n == 1 then
    return table.remove(t, random_int(1, #t, rng))
  else
    local out = {}
    while #out < n and #t > 0 do
      table.insert(out, table.remove(t, random_int(1, #t, rng)))
    end
    return out
  end
end

--[[
  Reverses the array in place.
  Optionally reverses only a range of elements.

  Usage:
    array.reverse({1, 2, 3, 4})         -- {4, 3, 2, 1}
    array.reverse({1, 2, 3, 4}, 1, 2)   -- {2, 1, 3, 4}

  Parameters:
    t - array to reverse
    i - (optional) start index, default 1
    j - (optional) end index, default #t (negative counts from end)

  Returns: the reversed array (same reference)
]]
function array.reverse(t, i, j)
  if not t then return nil end
  i = i or 1
  if i < 0 then i = #t + i + 1 end
  j = j or #t
  if j < 0 then j = #t + j + 1 end
  if i == j then return t end
  for k = 0, math.floor((j - i)/2) do
    t[i + k], t[j - k] = t[j - k], t[i + k]
  end
  return t
end

--[[
  Rotates the array by shifting elements circularly.
  Positive n shifts right, negative shifts left.

  Usage:
    array.rotate({1, 2, 3, 4}, 1)   -- {4, 1, 2, 3}
    array.rotate({1, 2, 3, 4}, -1)  -- {2, 3, 4, 1}

  Parameters:
    t - array to rotate
    n - positions to shift (positive=right, negative=left)

  Behavior:
    - Modifies array in place
    - Uses reversal algorithm for efficiency

  Returns: the rotated array (same reference)
]]
function array.rotate(t, n)
  if not t then return nil end
  if not n then return t end
  if n < 0 then n = #t + n end
  n = n % #t
  if n == 0 then return t end
  array.reverse(t, 1, #t)
  array.reverse(t, 1, n)
  array.reverse(t, n + 1, #t)
  return t
end

--[[
  Shuffles the array randomly in place.

  Usage:
    array.shuffle({1, 2, 3, 4, 5})  -- random order

  Parameters:
    t   - array to shuffle
    rng - (optional) rng handle from random_create; nil uses global_rng

  Behavior:
    - Uses Fisher-Yates algorithm
    - Modifies array in place

  Returns: the shuffled array (same reference)
]]
function array.shuffle(t, rng)
  for i = #t, 2, -1 do
    local j = random_int(1, i, rng)
    t[i], t[j] = t[j], t[i]
  end
  return t
end

--[[
  Returns the sum of all elements in the array.
  Optionally uses a function to extract values.

  Usage:
    array.sum({1, 2, 3})    -- 6
    array.sum({-2, 0, 2})   -- 0

  Parameters:
    t - array of values
    f - (optional) function(value) returning number to sum

  Returns: sum of values
]]
function array.sum(t, f)
  local sum = 0
  if f then
    for _, v in ipairs(t) do
      sum = sum + f(v)
    end
  else
    for _, v in ipairs(t) do
      sum = sum + v
    end
  end
  return sum
end

--[[
  Deep copies a table recursively.

  Usage:
    original = {a = 1, b = {c = 2}}
    copy = table.copy(original)
    copy.b.c = 3  -- original.b.c is still 2

  Parameters:
    t - table to copy

  Behavior:
    - Recursively copies nested tables
    - Preserves keys and values
    - Does not preserve metatables

  Returns: deep copy of the table
]]
function table.copy(t)
  if type(t) ~= 'table' then return t end
  local copy = {}
  for k, v in next, t, nil do
    copy[table.copy(k)] = table.copy(v)
  end
  return copy
end

--[[
  Returns a string representation of a table.

  Usage:
    table.tostring({1, 2, 3})         -- '{[1] = 1, [2] = 2, [3] = 3}'
    table.tostring({a = 1, b = 2})    -- '{["a"] = 1, ["b"] = 2}'

  Parameters:
    t - table to stringify

  Returns: string representation
]]
function table.tostring(t)
  t = t or {}
  if type(t) ~= 'table' then return tostring(t) end
  local s = '{'
  for k, v in pairs(t) do
    local key = type(k) == 'number' and k or '"' .. k .. '"'
    s = s .. '[' .. key .. '] = ' .. table.tostring(v) .. ', '
  end
  if s ~= '{' then
    s = s:sub(1, -3)
  end
  return s .. '}'
end
