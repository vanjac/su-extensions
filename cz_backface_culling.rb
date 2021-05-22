require 'sketchup.rb'
require 'extensions.rb'

module Chroma

  unless file_loaded?(__FILE__)
    ex = SketchupExtension.new('Hide Back Faces', 'cz_backface_culling/main')
    ex.description = 'Hide faces which face away from the camera'
    ex.version = '1.0.0'
    ex.creator = 'Jacob van\'t Hoog'
    Sketchup.register_extension(ex, true)
    file_loaded(__FILE__)
  end

end
