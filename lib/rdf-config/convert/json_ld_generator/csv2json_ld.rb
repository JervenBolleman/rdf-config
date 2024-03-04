# frozen_string_literal: true

require 'json'

class RDFConfig
  class Convert
    class CSV2JSON_LD
      def initialize(config, convert)
        @config = config
        @convert = convert
        @reader = nil
        @converter = convert.rdf_converter

        @model = Model.instance(@config)

        @subject_node = {}
        @subject_names = []
        @object_names = []

        @object_triple_map = {}

        @json_ld = {
          '@context' => {}
        }
        @node = {}
      end

      def generate
        @convert.source_subject_map.each do |source, subject_names|
          @reader = @convert.file_reader(source: source)
          @subject_names = subject_names
          generate_json
          generate_context
        end

        # json_data = @node.map { |id, hash| { '@id' => id }.merge(hash) }
        @json_ld.merge!(data: @node.values)

        # puts JSON.pretty_generate(@json_ld)
        puts JSON.generate(@json_ld)
      end

      private

      def generate_context
        add_prefixes_to_context

        @subject_node.each_key do |subject_name|
          @json_ld['@context'][subject_name] = '@id'
          @json_ld['@context'][subject_type_key(subject_name)] = '@type'
        end

        @json_ld['@context']['data'] = '@graph'

        @object_triple_map.each do |object_name, triple|
          hash = { '@id' => triple.predicates.last.uri }
          object = triple.object.is_a?(Model::ValueList) ? triple.object.value.first : triple.object
          case object
          when Model::URI, Model::Subject
            hash['@type'] = '@id'
          end
          @json_ld['@context'][object_name] = hash
        end
      end

      def generate_json
        @reader.each_row do |row|
          @converter.push_target_row(row)
          generate_row(row)
          @converter.pop_target_row
        end
      end

      def generate_row(row)
        clear_subject_node

        process_convert_variable(row)
        generate_row_by_subject_names(row)
        generate_subject_relation_statement
      end

      def process_convert_variable(row)
        @converter.convert_variable_names.each do |variable_name|
          @converter.convert_value(row, variable_name)
        end
      end

      def generate_row_by_subject_names(row)
        @subject_names.each do |subject_name|
          values = @converter.convert_value(row, subject_name)
          next if values.empty?

          values = [values] unless values.is_a?(Array)
          values.each do |subject_value|
            subject_key = subject_value
            add_subject_node(subject_name, subject_key)
            add_node(subject_key, { subject_name => subject_value })
          end
          generate_rdf_by_object_names(subject_name, row)
        end
      end

      def generate_rdf_by_object_names(subject_name, row)
        object_names(subject_name).each do |object_name|
          generate_row_by_object_name(row, object_name)
        end
      end

      def generate_row_by_object_name(row, object_name)
        values = @converter.convert_value(row, object_name)
        values = [values] unless values.is_a?(Array)
        values.each_with_index do |value, idx|
          next if value.to_s.empty?

          triple = triple_by_object(object_name)
          # next if triple.nil? || triple.object.is_a?(Model::Subject)
          next if triple.nil?

          subject_name = triple.subject.name
          next unless @subject_node.key?(subject_name)

          generate_row_by_triple(triple, values, idx)
        end
      end

      def generate_row_by_triple(triple, values, value_idx)
        subject_name = triple.subject.name

        subject_iri = @subject_node[subject_name][value_idx]
        subject_iri = @subject_node[subject_name].first if subject_iri.nil?

        json_object_type = type_value_by_subject(triple.subject)
        add_node(subject_iri, { subject_type_key(subject_name) => json_object_type }) unless json_object_type.nil?

        add_node(subject_iri, object_hash_by_triple(triple, values[value_idx]))
      end

      def object_hash_by_triple(triple, values)
        { triple.object.name => values }
      end

      def generate_subject_relation_statement
        @subject_node.each do |subject_name, subject_nodes|
          subject_nodes.each do |as_object_node|
            @model.find_all_by_object_name(subject_name).each do |triple|
              next unless @subject_node.key?(triple.subject.name)

              @subject_node[triple.subject.name].each do |subject_node|
                @object_triple_map[triple.object_name] = triple unless @object_triple_map.key?(triple.object_name)
                add_node(subject_node, { triple.object_name => as_object_node })
              end
            end
          end
        end
      end

      def add_prefixes_to_context
        @config.prefix.each do |prefix, uri|
          @json_ld['@context'][prefix] = uri[1..-2]
        end
      end

      def object_names(subject_name)
        @convert.subject_object_map[subject_name]
      end

      def type_value_by_subject(subject)
        if subject.types.nil? || subject.types.empty?
          nil
        elsif subject.types.size == 1
          subject.types.first
        else
          subject.types
        end
      end

      def add_subject_node(subject_name, subject_node)
        @subject_node[subject_name] = [] unless @subject_node.key?(subject_name)
        @subject_node[subject_name] << subject_node
      end

      def add_node(key, object_hash)
        object_key = object_hash.keys.first
        return if @node.key?(key) && @node[key][object_key] == object_hash[object_key]

        if @node.key?(key)
          if @node[key].key?(object_key)
            @node[key][object_key] = [@node[key][object_key]] unless @node[key][object_key].is_a?(Array)
            @node[key][object_key] << object_hash[object_key]
          else
            @node[key][object_key] = object_hash[object_key]
          end
        else
          @node[key] = object_hash.dup
        end
      end

      def triple_by_object(object_name)
        unless @object_triple_map.key?(object_name)
          @object_triple_map[object_name] = @model.find_by_object_name(object_name)
        end

        @object_triple_map[object_name]
      end

      def clear_subject_node
        @subject_node.clear
      end

      def subject_type_key(subject_name)
        "#{subject_name}_type"
      end
    end
  end
end
