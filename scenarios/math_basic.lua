--[[
  math_basic — Arithmetic and number theory basics.

  Tests whether a strategy can reliably answer simple math questions.
  Uses deterministic graders only (contains + exact_match).
]]

local ef = require("evalframe")

return {
  ef.bind { ef.graders.contains,    weight = 0.6 },
  ef.bind { ef.graders.exact_match, weight = 0.4 },

  cases = {
    ef.case "addition"    { input = "What is 2+2? Reply with just the number.",           expected = "4"     },
    ef.case "subtraction" { input = "What is 15-7? Reply with just the number.",          expected = "8"     },
    ef.case "multiply"    { input = "What is 7*8? Reply with just the number.",           expected = "56"    },
    ef.case "division"    { input = "What is 144/12? Reply with just the number.",        expected = "12"    },
    ef.case "power"       { input = "What is 2^10? Reply with just the number.",          expected = "1024"  },
    ef.case "prime"       { input = "Is 17 a prime number? Reply Yes or No.",             expected = "Yes"   },
    ef.case "factorial"   { input = "What is 5! (5 factorial)? Reply with just the number.", expected = "120" },
  },
}
