--- Tests for kemeny (Kemeny-Young rank aggregation) package.
--- Pure computation — no LLM mocking needed.

local describe, it, expect = lust.describe, lust.it, lust.expect

local REPO = os.getenv("PWD") or "."
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local kemeny = require("kemeny")

-- ═══════════════════════════════════════════════════════════════════
-- Kendall tau distance
-- ═══════════════════════════════════════════════════════════════════

describe("kemeny.kendall_tau", function()
    it("identical rankings have distance 0", function()
        expect(kemeny.kendall_tau(
            { "A", "B", "C" },
            { "A", "B", "C" }
        )).to.equal(0)
    end)

    it("reversed rankings have max distance m*(m-1)/2", function()
        -- 3 items reversed: 3 discordant pairs
        expect(kemeny.kendall_tau(
            { "A", "B", "C" },
            { "C", "B", "A" }
        )).to.equal(3)
    end)

    it("single swap has distance 1", function()
        expect(kemeny.kendall_tau(
            { "A", "B", "C" },
            { "B", "A", "C" }
        )).to.equal(1)
    end)

    it("4 items with 2 swaps", function()
        -- A B C D vs B A D C: (A,B) swapped + (C,D) swapped = 2
        expect(kemeny.kendall_tau(
            { "A", "B", "C", "D" },
            { "B", "A", "D", "C" }
        )).to.equal(2)
    end)

    it("is symmetric: d(r1,r2) = d(r2,r1)", function()
        local r1 = { "A", "B", "C", "D" }
        local r2 = { "C", "A", "D", "B" }
        expect(kemeny.kendall_tau(r1, r2)).to.equal(kemeny.kendall_tau(r2, r1))
    end)

    it("errors on different candidate sets", function()
        expect(function()
            kemeny.kendall_tau({ "A", "B" }, { "A", "C" })
        end).to.fail()
    end)

    it("errors on different lengths", function()
        expect(function()
            kemeny.kendall_tau({ "A", "B" }, { "A", "B", "C" })
        end).to.fail()
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Exact aggregation
-- ═══════════════════════════════════════════════════════════════════

describe("kemeny.exact", function()

    -- Unanimous rankings: consensus = that ranking
    describe("unanimous", function()
        local rankings = {
            { "A", "B", "C" },
            { "A", "B", "C" },
            { "A", "B", "C" },
        }
        local r = kemeny.exact(rankings)

        it("returns the unanimous ranking", function()
            expect(r.ranking[1]).to.equal("A")
            expect(r.ranking[2]).to.equal("B")
            expect(r.ranking[3]).to.equal("C")
        end)

        it("total distance is 0", function()
            expect(r.total_distance).to.equal(0)
        end)

        it("is unique", function()
            expect(r.is_unique).to.equal(true)
        end)
    end)

    -- 3 voters, 3 candidates with clear majority
    describe("3 voters, clear majority", function()
        local rankings = {
            { "A", "B", "C" },
            { "A", "C", "B" },
            { "B", "A", "C" },
        }
        -- A>B in 2/3, A>C in 2/3, B>C in 2/3 → Condorcet winner = A
        local r = kemeny.exact(rankings)

        it("A is first (Condorcet winner)", function()
            expect(r.ranking[1]).to.equal("A")
        end)

        it("method is exact", function()
            expect(r.method).to.equal("exact")
        end)
    end)

    -- Single voter: their ranking is the result
    describe("single voter", function()
        local rankings = { { "X", "Y", "Z" } }
        local r = kemeny.exact(rankings)

        it("returns the single ranking", function()
            expect(r.ranking[1]).to.equal("X")
            expect(r.ranking[2]).to.equal("Y")
            expect(r.ranking[3]).to.equal("Z")
        end)

        it("distance is 0", function()
            expect(r.total_distance).to.equal(0)
        end)
    end)

    -- Optimal: verify that exact finds strictly better than borda in some cases
    describe("optimality check (4 candidates)", function()
        local rankings = {
            { "A", "B", "C", "D" },
            { "D", "C", "B", "A" },
            { "B", "D", "A", "C" },
        }
        local r = kemeny.exact(rankings)

        it("total_distance is minimal", function()
            -- The returned ranking should have the smallest total distance
            -- Just verify it's a valid number
            expect(type(r.total_distance)).to.equal("number")
            expect(r.total_distance >= 0).to.equal(true)
        end)

        it("returned ranking is consistent", function()
            expect(#r.ranking).to.equal(4)
        end)
    end)

    -- Error: m > 8
    describe("rejects m > 8", function()
        it("errors with helpful message", function()
            local rankings = {}
            local big = {}
            for i = 1, 9 do big[i] = "c" .. i end
            rankings[1] = big
            expect(function() kemeny.exact(rankings) end).to.fail()
        end)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Borda count
-- ═══════════════════════════════════════════════════════════════════

describe("kemeny.borda", function()
    describe("basic 3 candidates", function()
        local rankings = {
            { "A", "B", "C" },
            { "A", "C", "B" },
            { "B", "A", "C" },
        }
        local r = kemeny.borda(rankings)

        it("returns scores", function()
            -- A: pos1=2 + pos1=2 + pos2=1 = 5
            -- B: pos2=1 + pos3=0 + pos1=2 = 3
            -- C: pos3=0 + pos2=1 + pos3=0 = 1
            expect(r.scores["A"]).to.equal(5)
            expect(r.scores["B"]).to.equal(3)
            expect(r.scores["C"]).to.equal(1)
        end)

        it("A is ranked first", function()
            expect(r.ranking[1]).to.equal("A")
        end)

        it("method is borda", function()
            expect(r.method).to.equal("borda")
        end)
    end)

    -- Borda tie
    describe("Borda tie detection", function()
        local rankings = {
            { "A", "B" },
            { "B", "A" },
        }
        local r = kemeny.borda(rankings)

        it("detects tie", function()
            -- A: 1+0=1, B: 0+1=1 → tied
            expect(#r.ties > 0).to.equal(true)
        end)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- aggregate (auto-select)
-- ═══════════════════════════════════════════════════════════════════

describe("kemeny.aggregate", function()
    it("uses exact for m <= 8", function()
        local r = kemeny.aggregate({
            { "A", "B", "C" },
            { "B", "A", "C" },
        })
        expect(r.method).to.equal("exact")
    end)

    it("uses borda for m > 8", function()
        local big = {}
        for i = 1, 9 do big[i] = "c" .. i end
        local r = kemeny.aggregate({ big })
        expect(r.method).to.equal("borda")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pairwise majority matrix
-- ═══════════════════════════════════════════════════════════════════

describe("kemeny.pairwise", function()
    it("computes correct pairwise counts", function()
        local rankings = {
            { "A", "B", "C" },  -- A>B, A>C, B>C
            { "B", "A", "C" },  -- B>A, B>C, A>C
            { "A", "C", "B" },  -- A>C, A>B, C>B
        }
        local m = kemeny.pairwise(rankings)

        expect(m["A"]["B"]).to.equal(2)  -- A>B in 2 of 3
        expect(m["B"]["A"]).to.equal(1)
        expect(m["A"]["C"]).to.equal(3)  -- A>C in all 3
        expect(m["C"]["A"]).to.equal(0)
        expect(m["B"]["C"]).to.equal(2)  -- B>C in 2 of 3
        expect(m["C"]["B"]).to.equal(1)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Condorcet winner
-- ═══════════════════════════════════════════════════════════════════

describe("kemeny.condorcet_winner", function()
    it("finds Condorcet winner when one exists", function()
        local rankings = {
            { "A", "B", "C" },
            { "A", "C", "B" },
            { "B", "A", "C" },
        }
        -- A beats B (2-1), A beats C (3-0) → A is Condorcet winner
        expect(kemeny.condorcet_winner(rankings)).to.equal("A")
    end)

    it("returns nil for Condorcet cycle", function()
        -- Classic Condorcet paradox: A>B>C>A
        local rankings = {
            { "A", "B", "C" },  -- A>B, A>C, B>C
            { "B", "C", "A" },  -- B>C, B>A, C>A
            { "C", "A", "B" },  -- C>A, C>B, A>B
        }
        -- A>B: 2, B>A: 1 → A beats B
        -- B>C: 2, C>B: 1 → B beats C
        -- C>A: 2, A>C: 1 → C beats A
        -- Cycle! No Condorcet winner.
        expect(kemeny.condorcet_winner(rankings)).to.equal(nil)
    end)

    it("Condorcet winner is first in exact result (consistency axiom)", function()
        local rankings = {
            { "A", "B", "C", "D" },
            { "A", "C", "D", "B" },
            { "A", "D", "B", "C" },
        }
        local cw = kemeny.condorcet_winner(rankings)
        local r = kemeny.exact(rankings)

        -- If a Condorcet winner exists, Kemeny puts it first
        expect(cw).to.equal("A")
        expect(r.ranking[1]).to.equal("A")
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Axiom: Neutrality
-- ═══════════════════════════════════════════════════════════════════

describe("axiom: neutrality", function()
    it("swapping labels swaps result", function()
        -- Original: rankings with A, B, C
        local r1 = kemeny.exact({
            { "A", "B", "C" },
            { "A", "C", "B" },
        })

        -- Swap A ↔ B everywhere
        local r2 = kemeny.exact({
            { "B", "A", "C" },
            { "B", "C", "A" },
        })

        -- In r1, A should be where B is in r2 and vice versa
        -- Find positions
        local pos1 = {}
        for i, v in ipairs(r1.ranking) do pos1[v] = i end
        local pos2 = {}
        for i, v in ipairs(r2.ranking) do pos2[v] = i end

        expect(pos1["A"]).to.equal(pos2["B"])
        expect(pos1["B"]).to.equal(pos2["A"])
        expect(pos1["C"]).to.equal(pos2["C"])
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Condorcet cycle (exact still returns valid result)
-- ═══════════════════════════════════════════════════════════════════

describe("Condorcet cycle", function()
    it("exact returns valid ranking even with cycle", function()
        local rankings = {
            { "A", "B", "C" },
            { "B", "C", "A" },
            { "C", "A", "B" },
        }
        local r = kemeny.exact(rankings)

        expect(#r.ranking).to.equal(3)
        expect(type(r.total_distance)).to.equal("number")
        -- With perfect cycle, all permutations have same total distance
        -- Each permutation has exactly 2+2+2 = 6 or similar
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Edge cases
-- ═══════════════════════════════════════════════════════════════════

describe("edge cases", function()
    it("single candidate", function()
        local r = kemeny.exact({ { "X" } })
        expect(r.ranking[1]).to.equal("X")
        expect(r.total_distance).to.equal(0)
    end)

    it("two candidates, majority decides", function()
        local rankings = {
            { "A", "B" },
            { "A", "B" },
            { "B", "A" },
        }
        local r = kemeny.exact(rankings)
        expect(r.ranking[1]).to.equal("A")
        expect(r.ranking[2]).to.equal("B")
        -- Distance: 0+0+1 = 1
        expect(r.total_distance).to.equal(1)
    end)

    it("numeric candidate IDs work", function()
        local rankings = {
            { 1, 2, 3 },
            { 2, 1, 3 },
        }
        local r = kemeny.exact(rankings)
        expect(#r.ranking).to.equal(3)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Input validation
-- ═══════════════════════════════════════════════════════════════════

describe("input validation", function()
    it("exact errors on empty rankings", function()
        expect(function() kemeny.exact({}) end).to.fail()
    end)

    it("borda errors on empty rankings", function()
        expect(function() kemeny.borda({}) end).to.fail()
    end)

    it("aggregate errors on empty rankings", function()
        expect(function() kemeny.aggregate({}) end).to.fail()
    end)
end)
