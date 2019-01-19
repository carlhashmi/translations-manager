require_relative 'locale_file_walker'

module TranslationsManager
  class LocaleFileCleaner < LocaleFileWalker
    def initialize(filename)
      @filename = filename
      @tree = { children: {} }
      @anchors = {}
    end

    def clean
      stream = parse_stream(@filename)
      handle_stream(stream)
      remove_empty_nodes(@tree)
      rewrite_values(@tree)

      stream.to_yaml(nil, line_width: -1)
    end

    def clean!
      write_yaml(clean, @filename)
    end

    protected

    def handle_value(node, parents)
      super
      subtree(parents)[:value] = node
    end

    def handle_scalar(node, depth, parents)
      super
      subtree(parents)[:scalar] = node
    end

    def handle_mapping(node, depth, parents)
      super
      subtree(parents)[:mapping] = node
      @anchors[node.anchor] = node if node.anchor
    end

    def handle_alias(node, depth, parents)
      super
      subtree(parents)[:alias] = node
    end

    def subtree(parents)
      nodes = @tree

      parents.each do |p|
        nodes = nodes[:children]
        nodes[p] = { children: {} } unless nodes.key?(p)
        nodes = nodes[p]
      end

      nodes
    end

    def remove_empty_nodes(parent)
      parent[:children].dup.each do |key, child|
        remove_empty_nodes(child)

        # remove keys that do not have any sub-keys with existing translations
        if child[:children].empty? && child[:scalar] && child[:mapping]
          parent[:children].delete(key)
          parent[:mapping].children.delete(child[:scalar])
          parent[:mapping].children.delete(child[:mapping])

          if anchor = child[:mapping].anchor
            @anchors.delete(anchor)
          end
        end

        # remove empty translations
        if child[:scalar] && child[:value] && child[:value].value.empty?
          parent[:children].delete(key)
          parent[:mapping].children.delete(child[:scalar])
          parent[:mapping].children.delete(child[:value])
        end

        # remove aliases that point to non-existent anchors
        if child[:alias] && !@anchors.key?(child[:alias].anchor)
          parent[:children].delete(key)
          parent[:mapping].children.delete(child[:scalar])
          parent[:mapping].children.delete(child[:alias])
        end
      end
    end

    def rewrite_values(parent)
      parent[:children].each do |_, child|
        rewrite_values(child)

        if child[:scalar] && value = child[:value]&.value
          value = unindent(value)
          value = replace_duplicate_linebreaks(value)
          child[:value].value = value
        end
      end
    end

    def unindent(value)
      lines = value.split("\n")
      return value unless lines.size > 1

      indentation = lines
        .reject(&:empty?)
        .map { |s| s[/^[ ]+/]&.length || 0 }
        .min

      indentation > 0 ? value.gsub(/^#{' ' * indentation}/, '') : value
    end

    def replace_duplicate_linebreaks(value)
      value.gsub(/\n{3,}/, "\n\n")
        .gsub(/\A\n\n|\n\n\z/, "\n")
    end

    def write_yaml(yaml, filename)
      File.open(filename, 'w') do |file|
        file.write(yaml)
      end
    end
  end
end
