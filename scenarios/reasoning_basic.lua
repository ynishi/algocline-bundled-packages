--[[
  reasoning_basic — Simple logical reasoning and common knowledge.

  Tests whether a strategy improves accuracy on questions that require
  a single step of reasoning beyond pure recall.
  Uses contains grader (lenient matching).
]]

local ef = require("evalframe")

return {
  ef.bind { ef.graders.contains, weight = 1.0 },

  cases = {
    ef.case "syllogism" {
      input    = "All cats are animals. Whiskers is a cat. Is Whiskers an animal? Reply Yes or No.",
      expected = "Yes",
    },
    ef.case "negation" {
      input    = "If it is raining, the ground is wet. The ground is dry. Is it raining? Reply Yes or No.",
      expected = "No",
    },
    ef.case "comparison" {
      input    = "Alice is taller than Bob. Bob is taller than Carol. Who is the shortest? Reply with just the name.",
      expected = "Carol",
    },
    ef.case "capital" {
      input    = "What is the capital of Japan? Reply with just the city name.",
      expected = "Tokyo",
    },
    ef.case "sequence" {
      input    = "What comes next in the sequence: 2, 4, 8, 16, ...? Reply with just the number.",
      expected = "32",
    },
  },
}
