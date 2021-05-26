require 'sketchup.rb'
require 'extensions.rb'

module Chroma

  unless file_loaded?(__FILE__)
    ex = SketchupExtension.new('Dynamic Animations', 'zz_dynamic_anim/main')
    ex.description = 'Extends animation capabilities of Dynamic Components'
    ex.version = '-1'
    ex.creator = 'Jacob van\'t Hoog'
    Sketchup.register_extension(ex, true)
    file_loaded(__FILE__)
  end

end
