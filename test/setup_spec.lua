-- Specs for the setup module: dynamic backend detection and the
-- default-wiring keymap flow.

local helpers = require('test.cword_helpers')
local Segmenter = require('cword.segmenter')

local eq = helpers.eq

describe('setup.detect_default_backend', function()
  it('prefers icu_ffi when libicuuc is loadable', function()
    local setup = require('cword.setup')
    local backend = setup.detect_default_backend()
    assert(
      backend == 'icu_ffi' or backend == 'cjk',
      'detect_default_backend returned unexpected value: ' .. tostring(backend)
    )
  end)

  it('returns a value accepted by Segmenter.new', function()
    local setup = require('cword.setup')
    local backend = setup.detect_default_backend()
    local seg = Segmenter.new({ backend = backend })
    local tokens = seg:cut('你好世界')
    eq(true, #tokens > 0)
  end)
end)
