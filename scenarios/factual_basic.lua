--[[
  factual_basic — Factual knowledge with verifiable answers.

  Tests whether a strategy produces factually correct, concise responses.
  Useful as a baseline for comparing strategy accuracy on recall tasks.
  Uses contains grader (lenient matching).
]]

local ef = require("evalframe")

return {
  ef.bind { ef.graders.contains, weight = 1.0 },

  cases = {
    ef.case "element" {
      input    = "What is the chemical symbol for gold? Reply with just the symbol.",
      expected = "Au",
    },
    ef.case "planet" {
      input    = "What is the largest planet in our solar system? Reply with just the name.",
      expected = "Jupiter",
    },
    ef.case "speed_of_light" {
      input    = "What is the speed of light in km/s (approximate integer)? Reply with just the number.",
      expected = "300000",
    },
    ef.case "inventor" {
      input    = "Who invented the telephone? Reply with just the name.",
      expected = "Bell",
    },
    ef.case "boiling_point" {
      input    = "What is the boiling point of water in Celsius? Reply with just the number.",
      expected = "100",
    },
  },
}
