require 'sketchup.rb'
require 'extensions.rb'

module Chroma

  unless file_loaded?(__FILE__)
    ex = SketchupExtension.new('Make Pro', 'cz_make_pro/main')
    ex.version = '-1'
    ex.creator = 'Jacob van\'t Hoog'
    Sketchup.register_extension(ex, true)
    file_loaded(__FILE__)
  end

end
