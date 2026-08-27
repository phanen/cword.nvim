-- Specs for setup().

local helpers = require('test.cword_helpers')

local eq = helpers.eq

describe('setup', function()
  before_each(function()
    helpers.clear()
    helpers.setup_path()
  end)

  it('exposes the icu_ffi segmenter', function()
    eq(
      'function',
      helpers.exec_lua(function()
        return type(require('cword.segmenter').cut)
      end)
    )
  end)

  it('setup() is idempotent', function()
    helpers.exec_lua(function()
      local cword = require('cword')
      cword.setup()
      cword.setup() -- second call is a no-op
      assert(type(cword.move_forward) == 'function')
    end)
  end)
end)
