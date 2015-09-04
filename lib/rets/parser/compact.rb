# coding: utf-8

require 'cgi'

module Rets
  module Parser
    class Compact
      DEFAULT_DELIMITER = "\t"

      INCLUDE_NULL_FIELDS = -1

      InvalidDelimiter = Class.new(ArgumentError)

      def self.parse_document(xml)
        doc = SaxParser.new
        parser = Nokogiri::XML::SAX::Parser.new(doc)
        io = StringIO.new(xml.to_s)

        parser.parse(io)
        doc.results.map {|r| parse(doc.columns, r, doc.delimiter) }
      end

      class SaxParser < Nokogiri::XML::SAX::Document
        attr_reader :results, :columns, :delimiter

        def initialize
          @results = []
          @columns = ''
          @result_index = nil
          @delimiter = nil
          @columns_start = false
          @data_start = false
        end

        def start_element name, attrs=[]
          case name
          when 'DELIMITER'
            @delimiter = attrs.last.last.to_i.chr
          when 'COLUMNS'
            @columns_start = true
          when 'DATA'
            @result_index = @results.size
          end
        end

        def end_element name
          case name
          when 'COLUMNS'
            @columns_start = false
          when 'DATA'
            @result_index = nil
          end
        end

        def characters string
          if @columns_start
            @columns << string
          end

          if @result_index
            @results[@result_index] ||= ''
            @results[@result_index] << string
          end
        end
      end

      # Parses a single row of RETS-COMPACT data.
      #
      # Delimiter must be a regexp because String#split behaves differently when
      # given a string pattern. (It removes leading spaces).
      #
      def self.parse(columns, data, delimiter = nil)
        delimiter ||= DEFAULT_DELIMITER
        delimiter = Regexp.new(Regexp.escape(delimiter))

        if delimiter == // || delimiter == /,/
          raise Rets::Parser::Compact::InvalidDelimiter, "Empty or invalid delimiter found, unable to parse."
        end

        column_names = columns.split(delimiter)
        data_values = data.split(delimiter, INCLUDE_NULL_FIELDS).map { |x| CGI::unescapeHTML(x) }

        zipped_key_values = column_names.zip(data_values).map { |k, v| [k.freeze, v.to_s] }

        hash = Hash[*zipped_key_values.flatten]
        hash.reject { |key, value| key.empty? && value.to_s.empty? }
      end

      def self.get_count(xml)
        doc = Nokogiri.parse(xml.to_s)
        if node = doc.at("//COUNT")
          return node.attr('Records').to_i
        elsif node = doc.at("//RETS-STATUS")
          # Handle <RETS-STATUS ReplyCode="20201" ReplyText="No matching records were found" />
          return 0 if node.attr('ReplyCode') == '20201'
        end
      end

    end
  end
end
