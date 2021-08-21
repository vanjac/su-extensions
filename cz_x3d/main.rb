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
      @used_materials = Set[] # set of material names

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

      model.definitions.each do |definition|
        write_definition(definition, scene)
      end

      # unit conversion / coordinate space transform
      # TODO version 3.3 supports UNIT statement
      transform = scene.add_element('Transform')
      transform.add_attribute('rotation', "-1 0 0 #{Math::PI / 2}")
      transform.add_attribute('scale', ([1.to_m] * 3).join(' '))

      write_entities(model.entities, transform)

      File.open(path, 'w') do |file|
        doc.write(output: file, indent: @debug ? 2 : -1)
      end
    end

    def write_definition(definition, root)
      declare = root.add_element('ProtoDeclare')
      declare.add_attribute('name', definition.name)
      body = declare.add_element('ProtoBody')
      group = body.add_element('Group')
      write_entities(definition.entities, group)
    end

    def write_entities(entities, root)
      entities.grep(Sketchup::ComponentInstance) do |instance|
        write_instance(instance, root)
      end
      entities.grep(Sketchup::Group) do |group|
        write_instance(group, root)
      end

      # TODO: share mesh between instances. use a StaticGroup?
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

    def write_mesh(entities, root)
      # TODO: group by material
      entities.grep(Sketchup::Face) do |face|
        shape = root.add_element('Shape')

        mesh = face.mesh(1 | 4) # UVQFront, Normals
        normals_array = (1..mesh.count_points).map { |i| mesh.normal_at(i) }
        indices_array = mesh.polygons.flatten(1).map { |x| x.abs - 1 }

        tri_set = shape.add_element('IndexedTriangleSet')
        coord = tri_set.add_element('Coordinate')
        coord.add_attribute('point', write_mfvec3f(mesh.points))
        normal = tri_set.add_element('Normal')
        normal.add_attribute('vector', write_mfvec3f(normals_array))
        texcoord = tri_set.add_element('TextureCoordinate')
        texcoord.add_attribute('point', texcoords_to_mfvec2f(mesh.uvs(true)))
        tri_set.add_attribute('index', join_mf(indices_array))

        face_mat = face.material

        if face_mat
          if @used_materials.include? face_mat.name
            shape.add_element('Appearance', { 'USE' => "mat:#{face_mat.name}" })
          else
            appearance = shape.add_element('Appearance')
            # TODO: can't share between prototypes?
            appearance.add_attribute('DEF', "mat:#{face_mat.name}")
            appearance.add_element('Material')
            face_tex = face_mat.texture
            if face_tex
              # TODO version 4.0 supports textures assigned to Material
              imagetex = appearance.add_element('ImageTexture')
              imagetex.add_attribute('url', path_to_uri(face_tex.filename))
            end
            @used_materials.add(face_mat.name)
          end
        end
      end
    end

    def path_to_uri(path)
      # TODO handle relative paths
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

    def texcoord_to_svvec2f(point)
      # X3D does not support homogeneous coordinates
      # TODO: use vertex attribute?
      u = point.x.to_f / point.z.to_f
      v = point.y.to_f / point.z.to_f
      "#{u} #{v}"
    end

    def texcoords_to_mfvec2f(points)
      join_mf(points.map { |x| texcoord_to_svvec2f(x) })
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
