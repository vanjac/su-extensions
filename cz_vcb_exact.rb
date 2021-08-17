require 'sketchup'
require 'extensions'

module Chroma
  unless file_loaded?(__FILE__)
    ex = SketchupExtension.new('Exact Measurement', 'cz_vcb_exact/main')
    ex.description = 'Enter exact value from the Measurements box'
    ex.version = '-1'
    ex.creator = 'Jacob van\'t Hoog'
    Sketchup.register_extension(ex, true)
    file_loaded(__FILE__)
  end
end
