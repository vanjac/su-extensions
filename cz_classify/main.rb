require 'sketchup.rb'

module Chroma

  unless file_loaded?(__FILE__)
    UI.menu.add_item('Add Classification') {
      names = Sketchup.active_model.classifications.map {|c| c.name}
      if names.length == 0
        UI.messagebox("No classification schema loaded!", MB_OK)
        next
      end
      result = UI.inputbox(["Schema", "Type"], [names[0], ""],
        [names.join("|"), ""], "Add classification")
      if !result
        next
      end
      error = false
      Sketchup.active_model.selection.each{ |entity|
        if entity.is_a?(Sketchup::ComponentInstance) ||
            entity.is_a?(Sketchup::Group)
          if !entity.definition.add_classification(result[0], result[1])
            error = true
          end
        end
      }
      if error
        UI.messagebox("Unrecognized classification type!", MB_OK)
      end
    }

    UI.menu.add_item('Remove Classification') {
      schemas = {}
      Sketchup.active_model.selection.each{ |entity|
        if entity.is_a?(Sketchup::ComponentInstance) ||
            entity.is_a?(Sketchup::Group)
          schema_dict = entity.definition.attribute_dictionary(
            "AppliedSchemaTypes")
          if schema_dict
            schema_dict.each_key{ |key| schemas[key] = true }
          end
        end
      }
      names = schemas.keys
      if names.length == 0
        UI.messagebox("No classifications for selected objects!", MB_OK)
        next
      end
      result = UI.inputbox(["Schema"], [names[0]],
        [names.join("|"), ""], "Remove classification")
      if !result
        next
      end
      Sketchup.active_model.selection.each{ |entity|
        if entity.is_a?(Sketchup::ComponentInstance) ||
            entity.is_a?(Sketchup::Group)
          entity.definition.remove_classification(result[0], "")
        end
      }
    }
  end
end