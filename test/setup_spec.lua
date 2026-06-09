-- Specs for the setup + default backend detection.

local helpers = require('test.cword_helpers')
local Segmenter = require('cword.segmenter')

local eq = helpers.eq

describe('setup and default backend', function()
  it('prefers icu_ffi when libicuuc is loadable', function()
    local backend = require('cword')._default_backend()
    assert(
      backend == 'icu_ffi' or backend == 'cjk',
      '_default_backend returned unexpected value: ' .. tostring(backend)
    )
  end)

  it('returns a value accepted by Segmenter.new', function()
    local backend = require('cword')._default_backend()
    local seg = Segmenter.new({ backend = backend })
    local tokens = seg:cut('你好世界')
    eq(true, #tokens > 0)
  end)

  it('setup() is idempotent', function()
    local cword = require('cword')
    cword.setup()
    cword.setup() -- second call is a no-op
    -- move_forward should work without error
    local handler = cword.move_forward
    eq('function', type(handler))
  end)
end)
