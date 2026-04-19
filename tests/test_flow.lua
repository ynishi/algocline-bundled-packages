--- Tests for flow Frame (FlowState + ReqToken substrate)

local describe, it, expect = lust.describe, lust.it, lust.expect

-- Derive REPO from the first `?.lua` entry already prepended to
-- `package.path` by `mlua-probe-mcp`'s `search_paths` (mirrors
-- `tests/test_gen_docs.lua` §repo_root_from_package_path). Using
-- `os.getenv("PWD")` is unreliable under mlua-probe-mcp because the
-- server's startup CWD may be the parent repo rather than the
-- worktree root, which would silently shadow worktree code with
-- main-repo code and produce false-green results. The `debug`
-- library is also unavailable in the sandbox.
local function repo_root_from_package_path()
    for entry in package.path:gmatch("[^;]+") do
        local prefix = entry:match("^(.-)/%?%.lua$")
        if prefix and prefix ~= "" and prefix:sub(1, 1) == "/" then
            return prefix
        end
    end
    return "."
end
local REPO = repo_root_from_package_path()
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

-- ---------------------------------------------------------------------
-- Test helpers
-- ---------------------------------------------------------------------

local function mock_alc_state()
    local store = {}
    _G.alc = {
        state = {
            get = function(key) return store[key] end,
            set = function(key, val) store[key] = val end,
        },
        log = function() end,
    }
    return store
end

local function mock_alc_llm(llm_fn)
    local call_log = {}
    _G.alc = _G.alc or {}
    _G.alc.llm = function(prompt, opts)
        call_log[#call_log + 1] = { prompt = prompt, opts = opts }
        return llm_fn(prompt, opts, #call_log)
    end
    return call_log
end

local function reset()
    _G.alc = nil
    for _, k in ipairs({ "flow", "flow.util", "flow.state", "flow.token", "flow.llm" }) do
        package.loaded[k] = nil
    end
end

-- ---------------------------------------------------------------------
-- flow.util
-- ---------------------------------------------------------------------
describe("flow.util: random_hex", function()
    lust.after(reset)

    it("returns string of requested length", function()
        local util = require("flow.util")
        expect(#util.random_hex(16)).to.equal(16)
        expect(#util.random_hex(32)).to.equal(32)
        expect(#util.random_hex(1)).to.equal(1)
    end)

    it("contains only lowercase hex characters", function()
        local util = require("flow.util")
        local s = util.random_hex(64)
        expect(s:match("^[0-9a-f]+$")).to_not.equal(nil)
    end)

    it("returns different values across calls (probabilistic)", function()
        local util = require("flow.util")
        local a, b = util.random_hex(32), util.random_hex(32)
        expect(a).to_not.equal(b)
    end)

    it("defaults to 16 characters when n omitted", function()
        local util = require("flow.util")
        expect(#util.random_hex()).to.equal(16)
    end)
end)

describe("flow.util: parse_tag", function()
    lust.after(reset)

    it("extracts value from a simple tag", function()
        local util = require("flow.util")
        expect(util.parse_tag("hello [foo=abc123] world", "foo")).to.equal("abc123")
    end)

    it("returns nil when tag is absent", function()
        local util = require("flow.util")
        expect(util.parse_tag("no tag here", "foo")).to.equal(nil)
    end)

    it("returns nil for non-matching tag names", function()
        local util = require("flow.util")
        expect(util.parse_tag("[other=xyz]", "foo")).to.equal(nil)
    end)

    it("supports hyphen, underscore, and alphanumeric in VALUE", function()
        local util = require("flow.util")
        expect(util.parse_tag("[t=abc-def_123]", "t")).to.equal("abc-def_123")
    end)

    it("escapes magic chars in tag_name", function()
        local util = require("flow.util")
        expect(util.parse_tag("[a.b=xx]", "a.b")).to.equal("xx")
        expect(util.parse_tag("[a.b=xx]", "axb")).to.equal(nil)
    end)

    it("returns nil on non-string inputs", function()
        local util = require("flow.util")
        expect(util.parse_tag(nil, "t")).to.equal(nil)
        expect(util.parse_tag("[t=x]", nil)).to.equal(nil)
    end)

    it("returns the LAST value when the same tag appears multiple times", function()
        -- flow.llm appends its tag pair to the prompt end. Prompts often
        -- carry an earlier gate's echoed tags embedded in prev_output,
        -- so LAST-match is the correct semantics.
        local util = require("flow.util")
        expect(util.parse_tag("[t=first] middle [t=second]", "t")).to.equal("second")
        expect(util.parse_tag(
            "prev: [flow_slot=modeling_gen]\nnow [flow_slot=plan_gen]",
            "flow_slot"
        )).to.equal("plan_gen")
    end)
end)

describe("flow.util: deep_equal", function()
    lust.after(reset)

    it("returns true for identical primitives", function()
        local util = require("flow.util")
        expect(util.deep_equal(1, 1)).to.equal(true)
        expect(util.deep_equal("a", "a")).to.equal(true)
        expect(util.deep_equal(nil, nil)).to.equal(true)
        expect(util.deep_equal(true, true)).to.equal(true)
    end)

    it("returns false for different primitives or type mismatch", function()
        local util = require("flow.util")
        expect(util.deep_equal(1, 2)).to.equal(false)
        expect(util.deep_equal("a", "b")).to.equal(false)
        expect(util.deep_equal(1, "1")).to.equal(false)
        expect(util.deep_equal({}, 1)).to.equal(false)
    end)

    it("returns true for structurally equal nested tables", function()
        local util = require("flow.util")
        expect(util.deep_equal(
            { a = 1, b = { c = 2, d = { e = 3 } } },
            { a = 1, b = { c = 2, d = { e = 3 } } }
        )).to.equal(true)
    end)

    it("returns false when a subtree differs", function()
        local util = require("flow.util")
        expect(util.deep_equal(
            { a = 1, b = { c = 2 } },
            { a = 1, b = { c = 3 } }
        )).to.equal(false)
    end)

    it("returns false when key sets differ", function()
        local util = require("flow.util")
        expect(util.deep_equal({ a = 1 }, { a = 1, b = 2 })).to.equal(false)
        expect(util.deep_equal({ a = 1, b = 2 }, { a = 1 })).to.equal(false)
    end)

    it("treats two empty tables as equal", function()
        local util = require("flow.util")
        expect(util.deep_equal({}, {})).to.equal(true)
    end)
end)

describe("flow.util: shallow_copy", function()
    lust.after(reset)

    it("copies top-level keys into a new table", function()
        local util = require("flow.util")
        local src = { a = 1, b = "x" }
        local dst = util.shallow_copy(src)
        expect(dst.a).to.equal(1)
        expect(dst.b).to.equal("x")
        dst.a = 99
        expect(src.a).to.equal(1)
    end)

    it("shares inner tables (shallow)", function()
        local util = require("flow.util")
        local inner = { z = 9 }
        local dst = util.shallow_copy({ inner = inner })
        expect(dst.inner).to.equal(inner)
    end)

    it("returns non-tables unchanged", function()
        local util = require("flow.util")
        expect(util.shallow_copy(42)).to.equal(42)
        expect(util.shallow_copy("s")).to.equal("s")
        expect(util.shallow_copy(nil)).to.equal(nil)
    end)
end)

-- ---------------------------------------------------------------------
-- flow.state
-- ---------------------------------------------------------------------
describe("flow.state: basics", function()
    lust.after(reset)

    it("state_key returns key_prefix ':' id", function()
        mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "abc", id = "xyz" })
        expect(flow.state_key(st)).to.equal("abc:xyz")
    end)

    it("state_new without resume ignores persisted data", function()
        local store = mock_alc_state()
        store["p:id"] = { data = { k = "old" } }
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        expect(flow.state_get(st, "k")).to.equal(nil)
    end)

    it("state_new with resume=true restores data", function()
        local store = mock_alc_state()
        store["p:id"] = { data = { k = "persisted" }, _token_value = "tok" }
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id", resume = true })
        expect(flow.state_get(st, "k")).to.equal("persisted")
        expect(st._token_value).to.equal("tok")
    end)

    it("state_set then state_save persists via alc.state.set", function()
        local store = mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        flow.state_set(st, "k", "v")
        flow.state_save(st)
        expect(store["p:id"].data.k).to.equal("v")
    end)

    it("state_new errors on empty key_prefix or id", function()
        mock_alc_state()
        local flow = require("flow")
        expect(function() flow.state_new({ key_prefix = "", id = "id" }) end).to.fail()
        expect(function() flow.state_new({ key_prefix = "p", id  = "" }) end).to.fail()
    end)

    it("state_save persists identity alongside data", function()
        local store = mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({
            key_prefix = "p", id = "id",
            identity   = { K = 4, model = "m1" },
        })
        flow.state_set(st, "k", "v")
        flow.state_save(st)
        expect(store["p:id"].identity.K).to.equal(4)
        expect(store["p:id"].identity.model).to.equal("m1")
    end)

    it("resume accepts matching identity", function()
        mock_alc_state()
        local flow = require("flow")
        local st1 = flow.state_new({
            key_prefix = "p", id = "id",
            identity   = { K = 4, model = "m1" },
        })
        flow.state_set(st1, "phase", "done")
        flow.state_save(st1)

        local st2 = flow.state_new({
            key_prefix = "p", id = "id",
            identity   = { K = 4, model = "m1" },
            resume     = true,
        })
        expect(flow.state_get(st2, "phase")).to.equal("done")
    end)

    it("resume errors on identity mismatch", function()
        mock_alc_state()
        local flow = require("flow")
        local st1 = flow.state_new({
            key_prefix = "p", id = "id",
            identity   = { K = 4 },
        })
        flow.state_save(st1)
        expect(function()
            flow.state_new({
                key_prefix = "p", id = "id",
                identity   = { K = 8 },
                resume     = true,
            })
        end).to.fail()
    end)

    it("resume treats a bare persisted record (no identity field) as empty identity", function()
        -- Hand-crafted fixture without an identity field — the resume path
        -- treats the missing field as `{}`. Matches when opts.identity is
        -- absent or empty; errors when opts.identity is non-empty.
        local store = mock_alc_state()
        store["p:id"] = { data = { k = "bare" }, _token_value = "tok" }
        local flow = require("flow")

        local st = flow.state_new({ key_prefix = "p", id = "id", resume = true })
        expect(flow.state_get(st, "k")).to.equal("bare")

        expect(function()
            flow.state_new({
                key_prefix = "p", id = "id",
                identity   = { K = 4 },
                resume     = true,
            })
        end).to.fail()
    end)
end)

-- ---------------------------------------------------------------------
-- flow.token
-- ---------------------------------------------------------------------
describe("flow.token: issue", function()
    lust.after(reset)

    it("returns a token with value and _state_key", function()
        mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        local tok = flow.token_issue(st)
        expect(type(tok.value)).to.equal("string")
        expect(#tok.value).to.equal(32)
        expect(tok._state_key).to.equal("p:id")
    end)

    it("persists token value on issue", function()
        local store = mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        local tok = flow.token_issue(st)
        expect(store["p:id"]._token_value).to.equal(tok.value)
    end)

    it("restores the same token on resume", function()
        local store = mock_alc_state()
        local flow = require("flow")
        local st1 = flow.state_new({ key_prefix = "p", id = "id" })
        local tok1 = flow.token_issue(st1)

        local st2 = flow.state_new({ key_prefix = "p", id = "id", resume = true })
        local tok2 = flow.token_issue(st2)
        expect(tok2.value).to.equal(tok1.value)
        expect(store["p:id"]._token_value).to.equal(tok1.value)
    end)
end)

describe("flow.token: wrap", function()
    lust.after(reset)

    it("embeds token + slot in payload and exposes _expect_*", function()
        mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        local tok = flow.token_issue(st)
        local req = flow.token_wrap(tok, { slot = "gate", payload = { q = "Q" } })
        expect(req.slot).to.equal("gate")
        expect(req.payload.q).to.equal("Q")
        expect(req.payload._flow_token).to.equal(tok.value)
        expect(req.payload._flow_slot).to.equal("gate")
        expect(req._expect_token).to.equal(tok.value)
        expect(req._expect_slot).to.equal("gate")
    end)

    it("does not mutate the caller's payload table", function()
        mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        local tok = flow.token_issue(st)
        local payload = { q = "Q" }
        flow.token_wrap(tok, { slot = "gate", payload = payload })
        expect(payload._flow_token).to.equal(nil)
        expect(payload._flow_slot).to.equal(nil)
    end)

    it("accepts nil payload", function()
        mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        local tok = flow.token_issue(st)
        local req = flow.token_wrap(tok, { slot = "s" })
        expect(req.payload._flow_token).to.equal(tok.value)
    end)

    it("errors when payload already contains _flow_token", function()
        mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        local tok = flow.token_issue(st)
        expect(function()
            flow.token_wrap(tok, { slot = "s", payload = { _flow_token = "x" } })
        end).to.fail()
    end)

    it("errors when payload already contains _flow_slot", function()
        mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        local tok = flow.token_issue(st)
        expect(function()
            flow.token_wrap(tok, { slot = "s", payload = { _flow_slot = "x" } })
        end).to.fail()
    end)
end)

describe("flow.token: verify", function()
    lust.after(reset)

    local function make_req()
        mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        local tok = flow.token_issue(st)
        local req = flow.token_wrap(tok, { slot = "gate", payload = {} })
        return flow, tok, req
    end

    it("passes when result echoes matching token + slot", function()
        local flow, tok, req = make_req()
        local ok = flow.token_verify(tok, {
            _flow_token = req._expect_token,
            _flow_slot  = req._expect_slot,
        }, req)
        expect(ok).to.equal(true)
    end)

    it("fails when echoed token mismatches", function()
        local flow, tok, req = make_req()
        local ok = flow.token_verify(tok, { _flow_token = "wrong" }, req)
        expect(ok).to.equal(false)
    end)

    it("fails when echoed slot mismatches", function()
        local flow, tok, req = make_req()
        local ok = flow.token_verify(tok, { _flow_slot = "wrong_slot" }, req)
        expect(ok).to.equal(false)
    end)

    it("passes fail-open when result has no echo fields", function()
        local flow, tok, req = make_req()
        local ok = flow.token_verify(tok, { other = "data" }, req)
        expect(ok).to.equal(true)
    end)

    it("passes when result is not a table (boundary-verified only)", function()
        local flow, tok, req = make_req()
        expect(flow.token_verify(tok, "raw string", req)).to.equal(true)
        expect(flow.token_verify(tok, nil, req)).to.equal(true)
    end)
end)

-- ---------------------------------------------------------------------
-- flow.token: wrap_bound / verify_bound (session-spanning)
-- ---------------------------------------------------------------------
describe("flow.token: wrap_bound", function()
    lust.after(reset)

    it("persists a req under state.data._flow_req_<slot>", function()
        local store = mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        local req = flow.token_wrap_bound(st, { slot = "gate", payload = { q = "Q" } })

        expect(req.slot).to.equal("gate")
        expect(req.payload.q).to.equal("Q")
        expect(req.payload._flow_token).to.equal(st._token_value)
        expect(req._expect_slot).to.equal("gate")

        -- Persisted in-memory state
        expect(st.data._flow_req_gate._expect_token).to.equal(st._token_value)
        -- Persisted via state.save
        expect(store["p:id"].data._flow_req_gate._expect_slot).to.equal("gate")
    end)

    it("works with nil payload", function()
        mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        local req = flow.token_wrap_bound(st, { slot = "s" })
        expect(req.payload._flow_slot).to.equal("s")
        expect(st.data._flow_req_s).to_not.equal(nil)
    end)

    it("inherits wrap's reserved-key assertion", function()
        mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        expect(function()
            flow.token_wrap_bound(st, { slot = "s", payload = { _flow_token = "x" } })
        end).to.fail()
    end)

    it("errors on missing / empty slot", function()
        mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        expect(function() flow.token_wrap_bound(st, {}) end).to.fail()
        expect(function() flow.token_wrap_bound(st, { slot = "" }) end).to.fail()
    end)

    it("survives a session-boundary resume", function()
        -- Session 1: wrap_bound persists the req.
        mock_alc_state()
        local flow1 = require("flow")
        local st1 = flow1.state_new({ key_prefix = "p", id = "id" })
        local req1 = flow1.token_wrap_bound(st1, { slot = "gate" })

        -- Simulate full session restart: reset modules but keep the
        -- alc.state store. (reset() clears _G.alc, so preserve the store
        -- manually to mimic a persistent backend across sessions.)
        local preserved_key = "p:id"
        local preserved_val = _G.alc.state.get(preserved_key)
        reset()
        local store2 = mock_alc_state()
        store2[preserved_key] = preserved_val

        local flow2 = require("flow")
        local st2 = flow2.state_new({ key_prefix = "p", id = "id", resume = true })
        expect(st2.data._flow_req_gate._expect_token).to.equal(req1._expect_token)
    end)

    it("overwrites the persisted record on re-entry with the same slot", function()
        -- Re-calling wrap_bound on the same slot replaces the payload
        -- but preserves the state's token (token.issue is idempotent
        -- once _token_value is set). This is the expected resume-retry
        -- shape: after a mismatch/crash the driver may re-wrap the same
        -- slot with a fresh payload without rotating tokens.
        local store = mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        local req1 = flow.token_wrap_bound(st, { slot = "gate", payload = { v = 1 } })
        local req2 = flow.token_wrap_bound(st, { slot = "gate", payload = { v = 2 } })
        expect(req1._expect_token).to.equal(req2._expect_token)
        expect(st.data._flow_req_gate.payload.v).to.equal(2)
        expect(store["p:id"].data._flow_req_gate.payload.v).to.equal(2)
    end)

    it("keeps independent records per slot", function()
        mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        flow.token_wrap_bound(st, { slot = "a", payload = { v = "A" } })
        flow.token_wrap_bound(st, { slot = "b", payload = { v = "B" } })
        expect(st.data._flow_req_a.payload.v).to.equal("A")
        expect(st.data._flow_req_b.payload.v).to.equal("B")
        -- Verifying one slot must not touch the other's record.
        flow.token_verify_bound(st, "a", {
            _flow_token = st.data._flow_req_a._expect_token,
            _flow_slot  = "a",
        })
        expect(st.data._flow_req_a).to.equal(nil)
        expect(st.data._flow_req_b).to_not.equal(nil)
        expect(st.data._flow_req_b.payload.v).to.equal("B")
    end)
end)

describe("flow.token: verify_bound", function()
    lust.after(reset)

    local function setup_bound()
        local store = mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        local req = flow.token_wrap_bound(st, { slot = "gate", payload = {} })
        return flow, st, req, store
    end

    it("passes on matching echo and auto-deletes the record", function()
        local flow, st, req = setup_bound()
        local ok = flow.token_verify_bound(st, "gate", {
            _flow_token = req._expect_token,
            _flow_slot  = req._expect_slot,
        })
        expect(ok).to.equal(true)
        expect(st.data._flow_req_gate).to.equal(nil)
    end)

    it("auto-delete survives through state.save (persisted record cleared)", function()
        local flow, st, req, store = setup_bound()
        flow.token_verify_bound(st, "gate", {
            _flow_token = req._expect_token,
            _flow_slot  = req._expect_slot,
        })
        expect(store["p:id"].data._flow_req_gate).to.equal(nil)
    end)

    it("fail-open (no echo) is treated as success and auto-deletes", function()
        local flow, st = setup_bound()
        local ok = flow.token_verify_bound(st, "gate", { other = "data" })
        expect(ok).to.equal(true)
        expect(st.data._flow_req_gate).to.equal(nil)
    end)

    it("opts.keep=true retains the record on success", function()
        local flow, st, req = setup_bound()
        local ok = flow.token_verify_bound(st, "gate", {
            _flow_token = req._expect_token,
            _flow_slot  = req._expect_slot,
        }, { keep = true })
        expect(ok).to.equal(true)
        expect(st.data._flow_req_gate).to_not.equal(nil)
    end)

    it("returns false on mismatch and keeps the record", function()
        local flow, st = setup_bound()
        local ok = flow.token_verify_bound(st, "gate", { _flow_token = "wrong" })
        expect(ok).to.equal(false)
        expect(st.data._flow_req_gate).to_not.equal(nil)
    end)

    it("errors when no persisted record exists for slot", function()
        mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        expect(function() flow.token_verify_bound(st, "missing", {}) end).to.fail()
    end)

    it("errors on empty slot", function()
        mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        expect(function() flow.token_verify_bound(st, "", {}) end).to.fail()
    end)
end)

-- ---------------------------------------------------------------------
-- flow.llm
-- ---------------------------------------------------------------------
describe("flow.llm", function()
    lust.after(reset)

    it("embeds token + slot tags in the prompt", function()
        mock_alc_state()
        local log = mock_alc_llm(function() return "out" end)
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        local tok = flow.token_issue(st)
        flow.llm({ token = tok, slot = "s1", prompt = "hello" })
        local sent = log[1].prompt
        expect(sent:find("[flow_token=" .. tok.value .. "]", 1, true)).to_not.equal(nil)
        expect(sent:find("[flow_slot=s1]", 1, true)).to_not.equal(nil)
        expect(sent:find("hello", 1, true)).to_not.equal(nil)
    end)

    it("passes llm_opts straight through to alc.llm", function()
        mock_alc_state()
        local log = mock_alc_llm(function() return "out" end)
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        local tok = flow.token_issue(st)
        flow.llm({
            token    = tok,
            slot     = "s",
            prompt   = "p",
            llm_opts = { system = "sys", max_tokens = 42 },
        })
        expect(log[1].opts.system).to.equal("sys")
        expect(log[1].opts.max_tokens).to.equal(42)
    end)

    it("accepts response with matching echoed tags", function()
        mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        local tok = flow.token_issue(st)
        mock_alc_llm(function()
            return "answer [flow_token=" .. tok.value .. "][flow_slot=s]"
        end)
        local out = flow.llm({ token = tok, slot = "s", prompt = "p" })
        expect(out:find("answer", 1, true)).to_not.equal(nil)
    end)

    it("fails open when LLM omits echo tags", function()
        mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        local tok = flow.token_issue(st)
        mock_alc_llm(function() return "no echo" end)
        local out = flow.llm({ token = tok, slot = "s", prompt = "p" })
        expect(out).to.equal("no echo")
    end)

    it("errors on token mismatch", function()
        mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        local tok = flow.token_issue(st)
        mock_alc_llm(function() return "[flow_token=wrongtok]" end)
        expect(function()
            flow.llm({ token = tok, slot = "s", prompt = "p" })
        end).to.fail()
    end)

    it("errors on slot mismatch", function()
        mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        local tok = flow.token_issue(st)
        mock_alc_llm(function()
            return "[flow_token=" .. tok.value .. "][flow_slot=other]"
        end)
        expect(function()
            flow.llm({ token = tok, slot = "s", prompt = "p" })
        end).to.fail()
    end)
end)

describe("flow.llm_bound", function()
    lust.after(reset)

    it("persists _flow_req_<slot> BEFORE alc.llm runs", function()
        mock_alc_state()
        local observed_key
        _G.alc = _G.alc or {}
        -- Capture state snapshot at the moment alc.llm is called.
        _G.alc.llm = function(prompt)
            observed_key = _G.alc.state.get("p:id").data._flow_req_gate
            return "out [flow_slot=gate]"  -- echo slot to avoid mismatch-path noise
        end
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        flow.llm_bound(st, { slot = "gate", prompt = "hi" })
        expect(observed_key).to_not.equal(nil)
        expect(observed_key._expect_slot).to.equal("gate")
    end)

    it("auto-deletes _flow_req_<slot> on success", function()
        local store = mock_alc_state()
        mock_alc_llm(function() return "ok" end)  -- fail-open success
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        flow.llm_bound(st, { slot = "gate", prompt = "p" })
        expect(st.data._flow_req_gate).to.equal(nil)
        expect(store["p:id"].data._flow_req_gate).to.equal(nil)
    end)

    it("embeds flow_token + flow_slot tags in the prompt", function()
        mock_alc_state()
        local log = mock_alc_llm(function() return "out" end)
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        flow.llm_bound(st, { slot = "s1", prompt = "hello" })
        local sent = log[1].prompt
        expect(sent:find("[flow_token=" .. st._token_value .. "]", 1, true)).to_not.equal(nil)
        expect(sent:find("[flow_slot=s1]", 1, true)).to_not.equal(nil)
        expect(sent:find("hello", 1, true)).to_not.equal(nil)
    end)

    it("passes llm_opts through to alc.llm", function()
        mock_alc_state()
        local log = mock_alc_llm(function() return "out" end)
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        flow.llm_bound(st, {
            slot     = "s",
            prompt   = "p",
            llm_opts = { system = "sys", max_tokens = 42 },
        })
        expect(log[1].opts.system).to.equal("sys")
        expect(log[1].opts.max_tokens).to.equal(42)
    end)

    it("accepts matching echoed tags", function()
        mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        mock_alc_llm(function()
            return "answer [flow_token=" .. st._token_value .. "][flow_slot=s]"
        end)
        local out = flow.llm_bound(st, { slot = "s", prompt = "p" })
        expect(out:find("answer", 1, true)).to_not.equal(nil)
        expect(st.data._flow_req_s).to.equal(nil)
    end)

    it("rolls back and errors on token mismatch", function()
        local store = mock_alc_state()
        mock_alc_llm(function() return "[flow_token=wrongtok]" end)
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        expect(function()
            flow.llm_bound(st, { slot = "s", prompt = "p" })
        end).to.fail()
        -- Auto-rollback: the persisted record must be cleared even on error.
        expect(st.data._flow_req_s).to.equal(nil)
        expect(store["p:id"].data._flow_req_s).to.equal(nil)
    end)

    it("rolls back and errors on slot mismatch", function()
        local store = mock_alc_state()
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        mock_alc_llm(function()
            return "[flow_token=" .. st._token_value .. "][flow_slot=other]"
        end)
        expect(function()
            flow.llm_bound(st, { slot = "s", prompt = "p" })
        end).to.fail()
        expect(st.data._flow_req_s).to.equal(nil)
        expect(store["p:id"].data._flow_req_s).to.equal(nil)
    end)

    it("fails open on missing echo and auto-deletes", function()
        mock_alc_state()
        mock_alc_llm(function() return "no echo here" end)
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        local out = flow.llm_bound(st, { slot = "s", prompt = "p" })
        expect(out).to.equal("no echo here")
        expect(st.data._flow_req_s).to.equal(nil)
    end)

    it("errors on missing / invalid inputs", function()
        mock_alc_state()
        mock_alc_llm(function() return "" end)
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        expect(function() flow.llm_bound(st, {}) end).to.fail()
        expect(function() flow.llm_bound(st, { slot = "" }) end).to.fail()
        expect(function() flow.llm_bound(st, { slot = "s" }) end).to.fail()
        expect(function() flow.llm_bound(st, { slot = "s", prompt = 123 }) end).to.fail()
    end)

    it("leaves _flow_req_<slot> persisted when alc.llm raises (hard error)", function()
        -- Hard error from alc.llm is distinct from echo mismatch: the
        -- post-call cleanup never runs (error bubbles through the
        -- bare function), so the persisted record survives for the
        -- driver's resume path to clean up. This is documented
        -- behaviour (see flow/llm.lua §Hard-error residue).
        local store = mock_alc_state()
        mock_alc_llm(function() error("network down") end)
        local flow = require("flow")
        local st = flow.state_new({ key_prefix = "p", id = "id" })
        expect(function()
            flow.llm_bound(st, { slot = "s", prompt = "p" })
        end).to.fail()
        expect(st.data._flow_req_s).to_not.equal(nil)
        expect(st.data._flow_req_s._expect_slot).to.equal("s")
        expect(store["p:id"].data._flow_req_s).to_not.equal(nil)
    end)
end)

-- ---------------------------------------------------------------------
-- flow meta
-- ---------------------------------------------------------------------
describe("flow: meta", function()
    lust.after(reset)

    it("has expected meta fields", function()
        mock_alc_state()
        local flow = require("flow")
        expect(flow.meta.name).to.equal("flow")
        expect(flow.meta.category).to.equal("substrate")
        expect(type(flow.meta.version)).to.equal("string")
    end)

    it("does not expose M.run (substrate, not orchestrator)", function()
        mock_alc_state()
        local flow = require("flow")
        expect(flow.run).to.equal(nil)
    end)

    it("exposes the documented public API", function()
        mock_alc_state()
        local flow = require("flow")
        for _, name in ipairs({
            "state_new", "state_key", "state_get", "state_set", "state_save",
            "token_issue", "token_wrap", "token_verify",
            "token_wrap_bound", "token_verify_bound",
            "llm", "llm_bound",
        }) do
            expect(type(flow[name])).to.equal("function")
        end
    end)

    it("meta.version is 0.2.0 (session-spanning APIs added)", function()
        mock_alc_state()
        local flow = require("flow")
        expect(flow.meta.version).to.equal("0.2.0")
    end)
end)
