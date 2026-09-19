--- Tiny zero-dependency test harness: describe / it / eq / ok / tmpdir.
--- Deliberately not plenary or mini.test, so `make test` needs nothing but
--- nvim and CI has nothing to install.
local H = { passed = 0, failed = 0, failures = {}, _stack = {} }

function H.describe(name, fn)
  table.insert(H._stack, name)
  fn()
  table.remove(H._stack)
end

function H.it(name, fn)
  local label = table.concat(H._stack, " > ") .. " > " .. name
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    H.passed = H.passed + 1
  else
    H.failed = H.failed + 1
    table.insert(H.failures, label .. "\n    " .. tostring(err):gsub("\n", "\n    "))
  end
end

function H.eq(expected, actual, msg)
  if not vim.deep_equal(expected, actual) then
    error(
      ("%sexpected: %s\n  actual: %s"):format(msg and (msg .. "\n") or "", vim.inspect(expected), vim.inspect(actual)),
      2
    )
  end
end

function H.ok(v, msg)
  if not v then
    error(msg or "expected a truthy value", 2)
  end
end

--- Fresh temp dir, removed by H.cleanup().
H._tmp = {}
function H.tmpdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  table.insert(H._tmp, dir)
  return dir
end

function H.cleanup()
  for _, d in ipairs(H._tmp) do
    vim.fn.delete(d, "rf")
  end
  H._tmp = {}
end

return H
