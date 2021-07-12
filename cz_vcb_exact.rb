require 'sketchup.rb'
require 'extensions.rb'

module Chroma

  unless file_loaded?(__FILE__)
    ex = SketchupExtension.new('Exact VCB', 'cz_vcb_exact/main')
    ex.description = 'Enter exact value from the VCB'
    ex.version = '-1'
    ex.creator = 'Jacob van\'t Hoog'
    Sketchup.register_extension(ex, true)
    file_loaded(__FILE__)
  end

end
