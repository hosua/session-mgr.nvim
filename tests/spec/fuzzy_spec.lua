local fuzzy = require "session-mgr.fuzzy"

describe("fuzzy.match", function()
  it("matches a subsequence and reports byte positions", function()
    eq({ 1, 2, 3 }, fuzzy.match("coo", "coolio"))
    eq(nil, fuzzy.match("coz", "coolio"))
    eq({}, fuzzy.match("", "anything"))
  end)
  it("is smartcase", function()
    eq({ 1 }, fuzzy.match("c", "Cool"))
    eq(nil, fuzzy.match("C", "cool"))
    eq({ 1 }, fuzzy.match("C", "Cool"))
  end)
  it("binds earlier characters to the closest later occurrence", function()
    eq({ 9, 10 }, fuzzy.match("mg", "session-mgr"))
    eq({ 7, 9 }, fuzzy.match("nm", "session-mgr"))
  end)
  it("treats pattern characters literally", function()
    eq({ 2 }, fuzzy.match(".", "a.b"))
    eq(nil, fuzzy.match("%", "abc"))
  end)
end)

describe("fuzzy.filter", function()
  local names = { "scratch-cool", "cool", "cooli", "coolio", "abc" }
  local function ranked(q)
    return vim.tbl_map(function(r)
      return r.item
    end, fuzzy.filter(q, names))
  end
  it("drops non-matches and ranks prefix + shorter first", function()
    eq({ "cool", "cooli", "coolio", "scratch-cool" }, ranked "coo")
  end)
  it("prefers a word-boundary match over a mid-word one", function()
    eq(
      { "fix-bar", "foobar" },
      vim.tbl_map(function(r)
        return r.item
      end, fuzzy.filter("bar", { "foobar", "fix-bar" }))
    )
  end)
  it("keeps the input order for an empty query", function()
    eq(names, ranked "")
  end)
  it("supports a key function", function()
    local rows = { { name = "beta" }, { name = "alpha" } }
    eq(
      "alpha",
      fuzzy.filter("al", rows, function(r)
        return r.name
      end)[1].item.name
    )
  end)
end)
