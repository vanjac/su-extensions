# based on https://github.com/SketchUp/sketchup-ruby-api-tutorials/blob/master/tutorials/01_hello_cube/tut_hello_cube.rb

require 'sketchup.rb'
require 'extensions.rb'

module SUExtensions

  unless file_loaded?(__FILE__)
    ex = SketchupExtension.new('SUExtensions', 'su_extensions/main')
    ex.description = 'useful extensions'
    ex.version = '-1'
    ex.creator = 'vanjac'
    Sketchup.register_extension(ex, true)
    file_loaded(__FILE__)
  end

end
