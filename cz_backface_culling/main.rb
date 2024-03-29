require 'sketchup'

module Chroma
  def self.backface_culling_extension
    @@backface_culling_extension
  end

  # active throughout model lifetime, once created
  class BackfaceManager < Sketchup::LayersObserver
    LAYER_NAME = 'Hide Back Faces'.freeze
    # key is model.definitions, because model objects are reused on Windows but
    # definitions objects are not
    @@model_managers = {}

    def self.add_manager(model)
      manager = @@model_managers[model.definitions]
      unless manager
        manager = BackfaceManager.new(model)
        @@model_managers[model.definitions] = manager
      end
      manager
    end

    def self.backfaces_hidden(model)
      manager = @@model_managers[model.definitions]
      !manager.nil? && manager.active?
    end

    def initialize(model)
      @model = model
      @enabled = false
      @paused = false
      @culled_layer = nil
      @reset_flag = false

      @model.layers.add_observer(self)
      @model.add_observer(BackfaceUndoObserver.new(self))

      # check for known conflicts with specific extensions...
      eneroth_auto_weld = Sketchup.extensions['16cd999d-050e-4910-b0a4-699f83decd75']
      @block_follow_me = eneroth_auto_weld && eneroth_auto_weld.loaded?
    end

    def enable
      return if @enabled

      @enabled = true

      @view_observer = BackfaceViewObserver.new(self)
      @model.active_view.add_observer(@view_observer)
      @model_observer = BackfaceModelObserver.new(self)
      @model.add_observer(@model_observer)
      @selection_observer = BackfaceSelectionObserver.new(self)
      @model.selection.add_observer(@selection_observer)

      create_culled_layer
    end

    def disable
      return unless @enabled

      @enabled = false

      @model.active_view.remove_observer(@view_observer)
      @view_observer = nil
      @model.remove_observer(@model_observer)
      @model_observer = nil
      @model.selection.remove_observer(@selection_observer)
      @selection_observer = nil

      remove_culled_layer
    end

    def active?
      @enabled && !@paused
    end

    def pause
      return unless !@paused && @enabled

      @paused = true
      notification = UI::Notification.new(Chroma.backface_culling_extension,
                                          'Hide Back Faces interrupted')
      notification.on_accept('Resume') do
        unpause
      end
      notification.on_dismiss('Stop') do
        disable
      end
      notification.show
      # hack to bring focus back to main window
      dialog = UI::HtmlDialog.new(width: 0, height: 0)
      dialog.show
      dialog.close
    end

    def unpause
      return unless @paused && @enabled

      @paused = false
      update_hidden_faces
    end

    def create_culled_layer(transparent: false)
      return unless @culled_layer.nil? || @culled_layer.deleted?

      @model.start_operation('Hide Back Faces', true, false, transparent)
      @culled_layer = @model.layers.add(LAYER_NAME)
      @culled_layer.visible = false
      @culled_layer.page_behavior = LAYER_HIDDEN_BY_DEFAULT
      @model.commit_operation # onLayerAdded should trigger here

      update_hidden_faces
    end

    def remove_culled_layer(transparent: false)
      if @culled_layer.nil? || @culled_layer.deleted?
        @culled_layer = nil
        return
      end

      @model.start_operation('Unhide Back Faces', true, false, transparent)
      @model.layers.remove(@culled_layer, false)
      @culled_layer = nil
      @model.commit_operation # onLayerRemoved should trigger here
    end

    # these seem to execute BEFORE onTransactionUndo/Redo when an undo event
    # causes layers to change
    def onLayerAdded(_layers, layer)
      return unless @culled_layer.nil? && layer.name == LAYER_NAME

      # puts 'layer added unexpectedly! probably undo/redo'
      @culled_layer = layer
      enable
    end

    def onLayerRemoved(layers, _layer)
      return unless @culled_layer && layers[LAYER_NAME].nil?

      # puts 'layer removed unexpectedly! probably undo/redo'
      @culled_layer = nil
      disable
    end

    def front_face_visible(face, cam_eye)
      normal = face.normal
      cam_dir = cam_eye - face.vertices[0].position
      normal.dot(cam_dir) >= 0
    end

    def update_hidden_faces(remove_broken_edges: false)
      return unless active?

      current_tool = @model.tools.active_tool_id
      # fix crash caused by updating faces with Move tool in "pick" state
      # (while in moving state back-faces don't update anyway)
      # also fix triggering Eneroth Auto Weld while in Follow Me tool
      return if current_tool == 21048 ||                    # move tool
                (current_tool == 21525 && @block_follow_me) # follow me tool

      cam_eye = @model.active_view.camera.eye
      layer0 = @model.layers['Layer0'] # aka "untagged"
      selection = @model.selection

      operation_started = false
      # prevents starting an empty operation
      operation = lambda {
        unless operation_started
          operation_started = true
          @model.start_operation('Back Face Culling', true, false, true)
        end
      }

      update_entities = lambda { |entities|
        entities.each do |entity|
          if entity.is_a?(Sketchup::Face)
            if entity.hidden?
              # ignore
            elsif selection.include?(entity)
              # avoid some crashes with performing operations on hidden faces
              # eg. intersect faces with model
              if entity.layer == @culled_layer
                operation.call
                entity.layer = layer0
              end
            elsif entity.layer == @culled_layer
              if front_face_visible(entity, cam_eye)
                operation.call
                entity.layer = layer0
              end
            elsif entity.layer == layer0
              unless front_face_visible(entity, cam_eye)
                operation.call
                entity.layer = @culled_layer
              end
            end
          elsif entity.layer == @culled_layer
            # only faces should be in the culled layer!
            operation.call
            if remove_broken_edges && entity.is_a?(Sketchup::Edge)
              # puts 'deleting broken edge'
              @culled_layer.visible = true
              entity.erase!
              @culled_layer.visible = false
            else
              # puts 'fixing ' + entity.to_s
              entity.layer = layer0
            end
          end
        end
      }

      update_entities.call(@model.entities) # root
      path = @model.active_path
      if path
        path.each do |context|
          update_entities.call(context.definition.entities)
        end
      end

      @model.commit_operation if operation_started
    end

    # necessary when the active path changes
    def reset
      return unless active?

      remove_culled_layer(transparent: true)
      create_culled_layer(transparent: true)
    end

    def reset_delay
      return if @reset_flag

      @reset_flag = true
      UI.start_timer(0.1, false) do
        reset
        @reset_flag = false
      end
    end
  end

  # active for lifetime of BackfaceManager
  class BackfaceUndoObserver < Sketchup::ModelObserver
    def initialize(manager)
      @manager = manager
      @redo_stack = 0
    end

    def onTransactionCommit(_model)
      @redo_stack = 0
      @manager.unpause
    end

    def onTransactionUndo(_model)
      @redo_stack += 1
      @manager.pause
    end

    def onTransactionRedo(_model)
      @redo_stack -= 1
      if @redo_stack <= 0
        @redo_stack = 0
        @manager.unpause
      end
    end
  end

  # active only when back faces hidden
  class BackfaceViewObserver < Sketchup::ViewObserver
    def initialize(manager)
      @manager = manager
    end

    def onViewChanged(_view)
      @manager.update_hidden_faces
    end
  end

  # another model observer, active only when back faces hidden
  class BackfaceModelObserver < Sketchup::ModelObserver
    def initialize(manager)
      @manager = manager
      @saving = false
    end

    def onPreSaveModel(_model)
      # fix an infinite loop of saving triggered when an autosave is deferred
      # due to being in the middle of an operation
      return if @saving

      @saving = true
      # save without hidden backfaces
      @manager.remove_culled_layer(transparent: true)
    end

    def onPostSaveModel(_model)
      @manager.create_culled_layer(transparent: true)
      @saving = false
    end

    def onActivePathChanged(_model)
      # can't reset immediately or it gets caught in an infinite undo loop
      @manager.reset_delay
    end
  end

  class BackfaceSelectionObserver < Sketchup::SelectionObserver
    def initialize(manager)
      @manager = manager
    end

    def onSelectionBulkChange(selection)
      # weird hack to detect if the user tried to delete/cut something
      # normally onSelectionCleared would be called if the selection was empty
      # there can be false positives but it should be fine
      if selection.empty?
        # puts 'deleted something'
        # fixes bug with deleting/cutting edges between hidden faces
        @manager.update_hidden_faces(remove_broken_edges: true)
      else
        @manager.update_hidden_faces
      end
    end

    def onSelectionCleared(_selection)
      @manager.update_hidden_faces
    end
  end

  def self.hide_backfaces
    manager = BackfaceManager.add_manager(Sketchup.active_model)
    manager.enable
    manager.unpause
  end

  def self.show_backfaces
    manager = BackfaceManager.add_manager(Sketchup.active_model)
    manager.disable
  end

  unless file_loaded?(__FILE__)
    menu = UI.menu
    hide_item = menu.add_item('Hide Back Faces') do
      if BackfaceManager.backfaces_hidden(Sketchup.active_model)
        show_backfaces
      else
        hide_backfaces
      end
    end
    menu.set_validation_proc(hide_item) do
      if BackfaceManager.backfaces_hidden(Sketchup.active_model)
        MF_CHECKED
      else
        MF_UNCHECKED
      end
    end
    file_loaded(__FILE__)
  end
end
