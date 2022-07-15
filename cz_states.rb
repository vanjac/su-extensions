require 'sketchup.rb'
require 'extensions.rb'

module Chroma

  unless file_loaded?(__FILE__)
    ex = SketchupExtension.new('States', 'cz_states/main')
    ex.description = 'Add state machines to components'
    ex.version = '-1'
    ex.creator = 'chroma zone'
    Sketchup.register_extension(ex, true)
    file_loaded(__FILE__)
  end

end
