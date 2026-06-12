-- Specs for setup().

local helpers = require('test.cword_helpers')
local Segmenter = require('cword.segmenter')

local eq = helpers.eq

describe('setup', function()
  it('exposes the icu_ffi segmenter', function()
    eq('function', type(Segmenter.cut))
  end)

  it('setup() is idempotent', function()
    local cword = require('cword')
    cword.setup()
    cword.setup() -- second call is a no-op
    local handler = cword.move_forward
    eq('function', type(handler))
  end)
end)
