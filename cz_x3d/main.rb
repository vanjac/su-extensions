require 'sketchup'
require 'rexml/document'
require 'set'

module Chroma
  class X3DWriter
    COMPONENT_VECTORS = [Geom::Vector3d.new(1, 0, 0),
                         Geom::Vector3d.new(0, 1, 0),
                         Geom::Vector3d.new(0, 0, 1)].freeze

    attr_accessor :debug

    def initialize(version, profile)
      @version = version
      @profile = profile
      @debug = false

      @units = Length::Meter
    end

    def write(model, path)
      # close all active contexts, to ensure all transformations are local
      active_path = model.active_path || []
      (0...(active_path.count)).each do |_|
        close_active(model)
      end

      doc = REXML::Document.new
      doc << REXML::XMLDecl.new('1.0', 'UTF-8')

      root = doc.add_element('X3D')
      root.add_attribute('version', @version)
      root.add_attribute('profile', @profile)
      scene = root.add_element('Scene')

      model.materials.each do |material|
        write_material(material, scene)
      end

      model.definitions.each do |definition|
        write_definition(definition, scene)
      end

      # unit conversion / coordinate space transform
      # TODO version 3.3 supports UNIT statement
      transform = scene.add_element('Transform')
      transform.add_attribute('rotation', "-1 0 0 #{Math::PI / 2}")
      transform.add_attribute('scale', ([1.to_m] * 3).join(' '))
      transform.add_attribute('DEF', '@world')

      write_entities(model.entities, transform)

      File.open(path, 'w') do |file|
        doc.write(output: file, indent: @debug ? 2 : -1)
      end
    end

    def write_material(material, root)
      # TODO: are material instances shared or copied?
      declare = root.add_element('ProtoDeclare')
      declare.add_attribute('name', "mat:#{material.name}")
      body = declare.add_element('ProtoBody')
      appearance = body.add_element('Appearance')
      mat_node = appearance.add_element('Material')
      texture = material.texture
      if texture
        # TODO version 4.0 supports textures assigned to Material
        imagetex = appearance.add_element('ImageTexture')
        imagetex.add_attribute('url', path_to_uri(texture.filename))
      else
        # TODO colorized textures
        mat_node.add_attribute('diffuseColor', write_sfcolor(material.color))
      end
    end

    def write_definition(definition, root)
      declare = root.add_element('ProtoDeclare')
      declare.add_attribute('name', definition.name)
      body = declare.add_element('ProtoBody')
      group = write_custom_node(definition, body) || body.add_element('Group')
      write_entities(definition.entities, group)
    end

    def write_entities(entities, root)
      entities.grep(Sketchup::ComponentInstance) do |instance|
        write_instance(instance, root)
      end
      entities.grep(Sketchup::Group) do |group|
        write_instance(group, root)
      end

      # TODO: share mesh between instances, with default material separate.
      write_mesh(entities, root)
    end

    def write_instance(instance, root)
      transformation = instance.transformation
      # https://math.stackexchange.com/a/1463487
      translate = transformation.origin
      scale = COMPONENT_VECTORS.map { |comp| (transformation * comp).length }
      rot = [transformation.xaxis, transformation.yaxis, transformation.zaxis]
      # https://en.wikipedia.org/wiki/Rotation_matrix
      # TODO: check for singularity?
      rot_axis = Geom::Vector3d.new(rot[1].z - rot[2].y,
                                    rot[2].x - rot[0].z,
                                    rot[0].y - rot[1].x)
      rot_angle = Math.asin(rot_axis.length / 2)
      rot_axis.normalize!

      transform = root.add_element('Transform')
      transform.add_attribute('translation', write_sfvec3f(translate))
      transform.add_attribute('rotation',
                              "#{write_sfvec3f(rot_axis)} #{rot_angle}")
      transform.add_attribute('scale', scale.map(&:to_f).join(' '))

      proto = transform.add_element('ProtoInstance')
      unless instance.name.empty?
        proto.add_attribute('DEF', instance.name)
      end
      proto.add_attribute('name', instance.definition.name)
    end

    class ShapeBuilder
      attr_accessor :points, :normals, :uvs, :indices

      def initialize
        @points = []
        @normals = []
        @uvs = []
        @indices = []
      end
    end

    def write_mesh(entities, root)
      material_builders = {}

      entities.grep(Sketchup::Face) do |face|
        face_mat = face.material
        builder = material_builders[face_mat]
        unless builder
          builder = ShapeBuilder.new
          material_builders[face_mat] = builder
        end

        mesh = face.mesh(1 | 4) # UVQFront, Normals
        index_start = builder.points.count
        builder.points.concat(mesh.points)
        builder.normals.concat((1..mesh.count_points).map do |i|
          mesh.normal_at(i)
        end)
        builder.uvs.concat(mesh.uvs(true).map do |point|
          # X3D does not support homogeneous coordinates
          # TODO: use vertex attribute?
          u = point.x.to_f / point.z.to_f
          v = point.y.to_f / point.z.to_f
          "#{u} #{v}"
        end)
        builder.indices.concat(mesh.polygons.flatten(1).map do |x|
          x.abs - 1 + index_start
        end)
      end

      material_builders.each do |face_mat, builder|
        shape = root.add_element('Shape')

        tri_set = shape.add_element('IndexedTriangleSet')
        coord = tri_set.add_element('Coordinate')
        coord.add_attribute('point', write_mfvec3f(builder.points))
        normal = tri_set.add_element('Normal')
        normal.add_attribute('vector', write_mfvec3f(builder.normals))
        texcoord = tri_set.add_element('TextureCoordinate')
        texcoord.add_attribute('point', join_mf(builder.uvs))
        tri_set.add_attribute('index', join_mf(builder.indices))

        if face_mat
          proto = shape.add_element('ProtoInstance')
          proto.add_attribute('name', "mat:#{face_mat.name}")
        end
      end
    end

    def write_custom_node(entity, root)
      x3d_dict = entity.attribute_dictionary('x3d')
      return nil unless x3d_dict

      node_type = x3d_dict['!type']
      return nil unless node_type

      node = root.add_element(node_type)
      x3d_dict.each do |key, value|
        next if key.start_with? '!'

        # TODO Arrays (MF)
        field_val = case value
                    when Length
                      value.to_f.to_s
                    when Geom::Point3d, Geom::Vector3d
                      write_sfvec3f(value)
                    when Sketchup::Color
                      if value.alpha == 255
                        write_sfcolor(value)
                      else
                        write_sfcolorrgba(value)
                      end
                    else
                      value.to_s
                    end
        node.add_attribute(key, field_val)
      end
      node
    end

    def path_to_uri(path)
      # TODO handle relative paths and special characters
      # https://doc.instantreality.org/documentation/nodetype/ImageTexture2D/
      "file:///#{path.gsub('\\', '/')}"
    end

    # FIELDS
    # https://www.web3d.org/documents/specifications/19776-1/V3.3/Part01/EncodingOfFields.html

    def join_mf(sf_array)
      sf_array.join(', ')
    end

    def write_sfvec3f(v)
      "#{v.x.to_f} #{v.y.to_f} #{v.z.to_f}"
    end

    def write_mfvec3f(array)
      join_mf(array.map { |x| write_sfvec3f(x) })
    end

    def write_sfcolor(color)
      "#{color.red / 255.0} #{color.green / 255.0} #{color.blue / 255.0}"
    end

    def write_sfcolorrgba(color)
      "#{color.red / 255.0} #{color.green / 255.0} #{color.blue / 255.0} #{color.alpha / 255.0}"
    end
  end

  def self.export_x3d
    # path = UI.savepanel('Export X3D', '', '*.x3d')
    writer = X3DWriter.new('3.2', 'Full')
    writer.debug = true
    writer.write(Sketchup.active_model, 'D:\\git\\su-extensions\\test.x3d')
  end

  unless file_loaded?(__FILE__)
    UI.menu.add_item('Export X3D') {
      export_x3d
    }

    file_loaded(__FILE__)
  end
end
