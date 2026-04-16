--- Codegen runner for alc_shapes LuaCATS definitions.
---
--- Invoked via `just gen-shapes`. Reads alc_shapes/init.lua, collects
--- every `kind == "shape"` entry from the SSoT table, and prints the
--- LuaCATS class file to stdout. Redirect stdout to
--- `types/alc_shapes.d.lua` to persist.
---
--- `just verify-shapes` pipes this same output through `diff` against
--- the committed d.lua to detect drift.

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local S = require("alc_shapes")

local shapes = {}
for k, v in pairs(S) do
    if type(v) == "table" and rawget(v, "kind") == "shape" then
        shapes[k] = v
    end
end

io.write(S.LuaCats.gen(shapes, "AlcResult"))
