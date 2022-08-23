require 'rdf-config/model'
require 'rdf-config/grasp/common_methods'

class RDFConfig
  class Grasp
    class QueryTypeGenerator
      include CommonMethods

      DEFAULT_TYPE_NAME = 'Query'.freeze

      def initialize
        @query_lines = []
      end

      def generate
        lines = ['directive @embedded on OBJECT']
        lines << ''
        lines << "type #{type_name} {"
        @query_lines.each do |line|
          lines << line
        end
        lines << '}'

        lines
      end

      def generate_by_config(config)
        Model.instance(config).subjects.each do |subject|
          add(config, subject)
        end
      end

      def add(config, subject)
        type = subject_type_name(config, subject)
        @query_lines << "#{INDENT}#{type}(#{IRI_ARG_NAME}: String): #{type}"
      end

      private

      def type_name
        DEFAULT_TYPE_NAME
      end
    end
  end
end
