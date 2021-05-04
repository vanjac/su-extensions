require 'sketchup.rb'
require 'extensions.rb'

module SUExtensions

  unless file_loaded?(__FILE__)
    ex = SketchupExtension.new('Fly Tool', 'cz_fly/main')
    ex.description = 'Fly using noclip-style controls'
    ex.version = '-1'
    ex.creator = 'vantjac'
    Sketchup.register_extension(ex, true)
    file_loaded(__FILE__)
  end

end
