require 'sketchup.rb'
require 'extensions.rb'

module SUExtensions

  unless file_loaded?(__FILE__)
    ex = SketchupExtension.new('Hide Backfaces', 'cz_backface_culling/main')
    ex.description = 'Hide faces which face away from the camera'
    ex.version = '-1'
    ex.creator = 'vanjac'
    Sketchup.register_extension(ex, true)
    file_loaded(__FILE__)
  end

end
