module RNS
  # A configuration file parser compatible with Python's configobj.
  # Supports nested sections via bracket depth ([section], [[subsection]], etc.),
  # key = value pairs, comments, list values, boolean/int/float coercion,
  # and file I/O.
  class ConfigObj
    class ValueError < Exception; end

    class ParseError < Exception; end

    class NestingError < Exception; end

    # Boolean map matching Python configobj._bools
    BOOLS = {
      "yes" => true, "no" => false,
      "on" => true, "off" => false,
      "1" => true, "0" => false,
      "true" => true, "false" => false,
    }

    alias Value = String | Array(String) | Section

    # A section within a config file, at a given nesting depth.
    class Section
      property depth : Int32
      property name : String
      property scalars : Array(String)
      property sections : Array(String)
      getter parent : Section?

      # :nodoc:
      getter data : Hash(String, Value)

      def initialize(@parent : Section?, @depth : Int32, @name : String = "")
        @data = Hash(String, Value).new
        @scalars = [] of String
        @sections = [] of String
      end

      def []=(key : String, value : String)
        unless @data.has_key?(key)
          @scalars << key
        end
        @data[key] = value.as(Value)
      end

      def []=(key : String, value : Array(String))
        unless @data.has_key?(key)
          @scalars << key
        end
        @data[key] = value.as(Value)
      end

      def [](key : String) : Value
        @data[key]
      end

      def get(key : String, default : String) : String
        val = @data[key]?
        if val.nil?
          default
        elsif val.is_a?(String)
          val
        else
          default
        end
      end

      def has_key?(key : String) : Bool
        @data.has_key?(key)
      end

      def size : Int32
        @data.size
      end

      def section(name : String) : Section
        val = @data[name]?
        if val.is_a?(Section)
          val
        else
          raise KeyError.new("No section named '#{name}'")
        end
      end

      def add_section(name : String) : Section
        sect = Section.new(parent: self, depth: @depth + 1, name: name)
        @sections << name
        @data[name] = sect.as(Value)
        sect
      end

      # Type conversion methods matching Python configobj API

      def as_bool(key : String) : Bool
        val = @data[key]
        if val.is_a?(String)
          result = BOOLS[val.downcase]?
          if result.nil?
            raise ValueError.new("Value \"#{val}\" is neither True nor False")
          end
          result
        else
          raise ValueError.new("Value is not a string")
        end
      end

      def as_int(key : String) : Int32
        val = @data[key]
        if val.is_a?(String)
          val.to_i
        else
          raise ArgumentError.new("Value is not a string")
        end
      end

      def as_float(key : String) : Float64
        val = @data[key]
        if val.is_a?(String)
          val.to_f
        else
          raise ArgumentError.new("Value is not a string")
        end
      end

      def as_list(key : String) : Array(String)
        val = @data[key]
        case val
        when Array(String)
          val
        when String
          [val]
        else
          [] of String
        end
      end

      # Convert this section's scalar key-value pairs to a Hash(String, String).
      # Only includes string values (not subsections or arrays).
      # Useful for passing configuration to interface constructors.
      def to_string_hash : Hash(String, String)
        result = Hash(String, String).new
        @scalars.each do |key|
          val = @data[key]?
          result[key] = val.as(String) if val.is_a?(String)
        end
        result
      end

      # Write this section's content as config lines
      def write_lines(indent_type : String = "    ") : Array(String)
        out = [] of String
        indent = indent_type * @depth

        @scalars.each do |key|
          val = @data[key]
          case val
          when Array(String)
            if val.empty?
              out << "#{indent}#{key} = ,"
            else
              quoted_vals = val.map { |v| needs_quoting?(v) ? "\"#{v}\"" : v }
              out << "#{indent}#{key} = #{quoted_vals.join(", ")}"
            end
          when String
            out << "#{indent}#{key} = #{val}"
          end
        end

        @sections.each do |sect_name|
          sect = @data[sect_name]
          if sect.is_a?(Section)
            brackets_open = "[" * sect.depth
            brackets_close = "]" * sect.depth
            out << "#{indent}#{brackets_open}#{sect_name}#{brackets_close}"
            out.concat(sect.write_lines(indent_type))
          end
        end

        out
      end

      private def needs_quoting?(val : String) : Bool
        val.includes?(",") || val.includes?("#") || val.includes?("\"") || val.includes?("'") || val.includes?(" ")
      end
    end

    # Root-level fields
    getter root : Section
    delegate :[], :[]=, :has_key?, :size, :scalars, :sections, :section,
      :add_section, :as_bool, :as_int, :as_float, :as_list, :depth,
      :get, to: @root
    property filename : String?

    def initialize
      @root = Section.new(parent: nil, depth: 0)
      @filename = nil
    end

    def initialize(lines : Array(String))
      @root = Section.new(parent: nil, depth: 0)
      @filename = nil
      parse(lines)
    end

    def self.from_file(path : String) : ConfigObj
      lines = File.read_lines(path)
      config = new(lines)
      config.filename = path
      config
    end

    def write(path : String? = nil)
      target = path || @filename
      raise ArgumentError.new("No filename specified") if target.nil?

      lines = @root.write_lines
      File.write(target, lines.join("\n") + "\n")
    end

    # Section marker regex: matches [section], [[section]], etc.
    SECTION_RE = /^\s*((?:\[\s*)+)((?:".*?")|(?:'.*?')|(?:[^'"\s].*?))((?:\s*\])+)\s*(?:#.*)?$/

    # Key = value regex
    KEYWORD_RE = /^\s*((?:".*?")|(?:'.*?')|(?:[^'"=].*?))\s*=\s*(.*)$/

    private def parse(lines : Array(String))
      current_section = @root

      lines.each do |line|
        stripped = line.strip

        # Skip blank lines and comment-only lines
        next if stripped.empty? || stripped.starts_with?("#")

        # Check for section marker
        section_match = SECTION_RE.match(line)
        if section_match
          open_brackets = section_match[1]
          sect_name_raw = section_match[2]
          close_brackets = section_match[3]

          cur_depth = open_brackets.count('[')
          close_depth = close_brackets.count(']')

          if cur_depth != close_depth
            raise NestingError.new("Mismatched brackets in section marker: #{line}")
          end

          sect_name = unquote(sect_name_raw.strip)

          # Navigate to the correct parent
          parent = find_parent(current_section, cur_depth)

          new_section = Section.new(parent: parent, depth: cur_depth, name: sect_name)
          parent.sections << sect_name
          # Store using internal hash bypass
          parent.data[sect_name] = new_section.as(Value)
          current_section = new_section
          next
        end

        # Check for key = value
        kv_match = KEYWORD_RE.match(line)
        if kv_match
          key = unquote(kv_match[1].strip)
          raw_value = kv_match[2]

          value = handle_value(raw_value)
          case value
          when String
            current_section[key] = value
          when Array(String)
            current_section[key] = value
          end
          next
        end

        # Line is neither section nor key=value — skip (configobj stores errors)
      end
    end

    private def find_parent(current : Section, target_depth : Int32) : Section
      if target_depth == current.depth + 1
        # New section is a child of current
        return current
      elsif target_depth == current.depth
        # Sibling — parent is current's parent
        p = current.parent
        return p.nil? ? @root : p
      elsif target_depth < current.depth
        # Walk back up to find the right parent
        sect = current
        while sect.depth >= target_depth
          p = sect.parent
          break if p.nil?
          sect = p
        end
        return sect
      else
        # target_depth > current.depth + 1 — nesting too deep
        raise NestingError.new("Section nested too deeply")
      end
    end

    private def unquote(value : String) : String
      if value.size >= 2 && ((value[0] == '"' && value[-1] == '"') || (value[0] == '\'' && value[-1] == '\''))
        value[1..-2]
      else
        value
      end
    end

    private def handle_value(raw : String) : String | Array(String)
      # Strip inline comment (not inside quotes)
      value, _comment = split_comment(raw)

      value = value.strip

      # Check for empty list (single comma)
      if value == ","
        return [] of String
      end

      # Check for list values (contains unquoted comma)
      if has_unquoted_comma?(value)
        return parse_list(value)
      end

      # Single value — unquote if needed
      unquote(value)
    end

    private def split_comment(raw : String) : {String, String}
      in_single_quote = false
      in_double_quote = false
      i = 0

      while i < raw.size
        ch = raw[i]
        if ch == '\'' && !in_double_quote
          in_single_quote = !in_single_quote
        elsif ch == '"' && !in_single_quote
          in_double_quote = !in_double_quote
        elsif ch == '#' && !in_single_quote && !in_double_quote
          # Check for space before # (convention) or beginning
          return {raw[0...i], raw[i..]}
        end
        i += 1
      end

      {raw, ""}
    end

    private def has_unquoted_comma?(value : String) : Bool
      in_single_quote = false
      in_double_quote = false

      value.each_char do |ch|
        if ch == '\'' && !in_double_quote
          in_single_quote = !in_single_quote
        elsif ch == '"' && !in_single_quote
          in_double_quote = !in_double_quote
        elsif ch == ',' && !in_single_quote && !in_double_quote
          return true
        end
      end

      false
    end

    private def parse_list(value : String) : Array(String)
      items = [] of String
      current = String::Builder.new
      in_single_quote = false
      in_double_quote = false

      value.each_char do |ch|
        if ch == '\'' && !in_double_quote
          in_single_quote = !in_single_quote
          current << ch
        elsif ch == '"' && !in_single_quote
          in_double_quote = !in_double_quote
          current << ch
        elsif ch == ',' && !in_single_quote && !in_double_quote
          item = current.to_s.strip
          items << unquote(item) unless item.empty?
          current = String::Builder.new
        else
          current << ch
        end
      end

      # Handle last item
      remainder = current.to_s.strip
      items << unquote(remainder) unless remainder.empty?

      items
    end
  end
end
