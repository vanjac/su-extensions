require 'sketchup'
require 'extensions'

module Chroma
  unless file_loaded?(__FILE__)
    ex = SketchupExtension.new('X3D Creator', 'cz_x3d/main')
    ex.description = ''
    ex.version = '-1'
    ex.creator = 'chroma zone'
    Sketchup.register_extension(ex, true)
    file_loaded(__FILE__)
  end
end
