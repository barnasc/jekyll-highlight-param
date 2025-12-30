# frozen_string_literal: true

module Jekyll
  module Tags
    class HighlightBlockParam < Liquid::Block
      include Liquid::StandardFilters

      # The regular expression syntax checker. Start with the language specifier.
      # Follow that by zero or more space separated options that take one of three
      # forms: name, name=value, or name="<quoted list>"
      #
      # <quoted list> is a space-separated list of numbers
      # 
      # Both the language specifier and the options can be passed as liquid variables,
      # please consult the documentation at https://github.com/UriShX/jekyll-highlight-param/blob/master/README.md#usage.
      PARAM_SYNTAX = %r!(\w+([.]\w+)*)!x.freeze
      LANG_SYNTAX = %r!([a-zA-Z0-9.+#_-]+)!x.freeze
      OPTIONS_SYNTAX = %r!(\s+\w+(=(\w+|"([0-9]+\s)*[0-9]+")?)*)!.freeze
      VARIABLE_SYNTAX = %r!
        ^(
          \{\{\s*
          (?<lang_var>#{PARAM_SYNTAX})
          \s*\}\}|
          (?<lang>#{LANG_SYNTAX})
        )
        \s*
        ((?<fault1>[}]+\s*|)
        (
          \{\{\s*
          (?<params_var>(#{PARAM_SYNTAX}))
          \s*\}\}|
          (?<params>(#{OPTIONS_SYNTAX}+))
        )
        (?<fault2>.*))?
      !mx.freeze

      def isNilOrEmpty(var)
        if var.nil?
          return true
        elsif var.strip.empty?
          return true
        else
          return false
        end
      end

      def initialize(tag_name, markup, tokens)
        super
        markup  = markup.strip
        @matched = markup.match(VARIABLE_SYNTAX)
        # print @matched.captures.to_s + "\n"
        if !@matched or !isNilOrEmpty(@matched["fault1"]) or !isNilOrEmpty(@matched["fault2"])
          raise SyntaxError, <<~MSG
            Syntax Error in tag '#{tag_name}' while parsing the following markup:

            #{markup}

            Valid syntax: #{tag_name} <lang> [linenos]
                      \tOR: #{tag_name} {{ lang_variable }} [linenos]
                      \tOR: #{tag_name} <lang> {{ [linenos_variable(s)] }}
                      \tOR: #{tag_name} {{ lang_variable }} {{ [linenos_variable(s)] }}
          MSG
        end
      end

      LEADING_OR_TRAILING_LINE_TERMINATORS = %r!\A(\n|\r)+|(\n|\r)+\z!.freeze

      def render(context)
        prefix = context["highlighter_prefix"] || ""
        suffix = context["highlighter_suffix"] || ""
        code = super.to_s.gsub(LEADING_OR_TRAILING_LINE_TERMINATORS, "")

        if @matched["lang_var"]
          @lang = context[@matched["lang_var"]].downcase
          @lang.match(LANG_SYNTAX)
          unless $& == @lang
            raise ArgumentError, <<~MSG
              Language characters can only include Alphanumeric and the following characters, without spaces: . + # _ -
              Your passed language variable: #{@lang}
              MSG
          end
        elsif @matched["lang"]
          @lang = @matched["lang"].downcase
        else
          raise SyntaxError, <<~MSG
            Unknown Syntax Error in tag 'highlight_param'.
            Please review tag documentation.
            MSG
        end

        # puts @lang

        if @matched["params_var"]
          @highlight_options = parse_options(@matched["params_var"])
        elsif @matched["params"]
          @highlight_options = parse_options(@matched["params"])
        else
          @highlight_options = parse_options("")
        end

        # puts @highlight_options

        output =
          case context.registers[:site].highlighter
          when "rouge"
            render_rouge(code)
          when "pygments"
            render_pygments(code, context)
          else
            render_codehighlighter(code)
          end

        rendered_output = add_code_tag(output)
        prefix + rendered_output + suffix
      end

      private

      OPTIONS_REGEX = %r!(?:\w="[^"]*"|\w=\w|\w)+!.freeze

      def parse_options(input)
        options = {}
        return options if isNilOrEmpty(input)

        # Split along 3 possible forms -- key="<quoted list>", key=value, or key
        input.scan(OPTIONS_REGEX) do |opt|
          key, value = opt.split("=")
          # If a quoted list, convert to array
          if value&.include?('"')
            value.delete!('"')
            value = value.split
          end
          options[key.to_sym] = value || true
        end

        options[:linenos] = "inline" if options[:linenos] == true
        options
      end

      def render_pygments(code, _context)
        Jekyll.logger.warn "Warning:", "Highlight Tag no longer supports rendering with Pygments."
        Jekyll.logger.warn "", "Using the default highlighter, Rouge, instead."
        render_rouge(code)
      end

      def render_rouge(code)
        require "rouge"
        formatter = ::Rouge::Formatters::HTMLLegacy.new(
          :line_numbers => @highlight_options[:linenos],
          :wrap         => false,
          :css_class    => "highlight",
          :gutter_class => "gutter",
          :code_class   => "code"
        )
        if LANG_SYNTAX.match?(@lang)
          lexer = ::Rouge::Lexer.find_fancy(@lang, code) || Rouge::Lexers::PlainText
        else
          raise SyntaxError, <<~MSG
          Can't find language variable #{@matched["lang_var"]}
          MSG
        end
        formatter.format(lexer.lex(code))
      end

      def render_codehighlighter(code)
        h(code).strip
      end

      def add_code_tag(code)
        code_attributes = [
          "class=\"highlight language-#{@lang.to_s.tr("+", "-")}\"",
          "data-lang=\"#{@lang}\"",
        ].join(" ")
        "<div #{code_attributes}>"\
        "#{code.chomp}</div>"
      end
    end
  end
end

Liquid::Template.register_tag("highlight_param", Jekyll::Tags::HighlightBlockParam)
