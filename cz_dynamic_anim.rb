require 'sketchup.rb'
require 'extensions.rb'

module SUExtensions

  unless file_loaded?(__FILE__)
    ex = SketchupExtension.new('Dynamic Animations', 'cz_dynamic_anim/main')
    ex.description = 'Extends animation capabilities of dynamic components'
    ex.version = '-1'
    ex.creator = 'vanjac'
    Sketchup.register_extension(ex, true)
    file_loaded(__FILE__)
  end

end
