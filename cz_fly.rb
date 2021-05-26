require 'sketchup.rb'
require 'extensions.rb'

module Chroma

  unless file_loaded?(__FILE__)
    ex = SketchupExtension.new('Fly Tool', 'cz_fly/main')
    ex.description = 'Fly using noclip-style controls'
    ex.version = '-1'
    ex.creator = 'Jacob van\'t Hoog'
    Sketchup.register_extension(ex, true)
    file_loaded(__FILE__)
  end

end
