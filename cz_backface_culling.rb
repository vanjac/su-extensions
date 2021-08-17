require 'sketchup'
require 'extensions'

module Chroma
  unless file_loaded?(__FILE__)
    ex = SketchupExtension.new('Hide Back Faces', 'cz_backface_culling/main')
    ex.description = 'Hide faces which face away from the camera'
    ex.version = '1.0.2'
    ex.creator = 'Jacob van\'t Hoog'
    Sketchup.register_extension(ex, true)
    @@backface_culling_extension = ex
    file_loaded(__FILE__)
  end
end
