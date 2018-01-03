require "jekyll"
require "digest"
require "html/pipeline"

module Jekyll
  class Mathifier
    BODY_START_TAG = "<body".freeze

    MATH_TAG_REGEX = /<script[^>]*type="math\/tex/i

    class << self

      def addInlineStyle(svg_tag, inline_styles)
        inline_style = svg_tag["style"]
        Jekyll.logger.warn "inline style: " + inline_style
        digest = Digest::MD5.hexdigest(inline_style)
        inline_styles[digest] = inline_style

        digest_class = "mathjax-inline-#{digest}"
        svg_tag["class"] = digest_class
        svg_tag.remove_attribute("style")
        Jekyll.logger.warn "new class: " + digest_class
      end

      def compileStyleElement(parsed_doc, inline_styles)
        style_content = ""
        inline_styles.each do |digest, inline_style|
          style_content += ".mathjax-inline-#{digest}{#{inline_style}}"
        end
        style_tag = parsed_doc.at_css("head").add_child("<style>#{style_content}</style>")[0]

        csp_digest = "'sha256-#{Digest::SHA256.base64digest(style_content)}''"
        style_tag.add_previous_sibling("<!-- #{csp_digest} -->")
      end

      def mathify(doc)
        Jekyll.logger.warn "Mathify called"
        return unless MATH_TAG_REGEX.match?(doc.output)
        parsed_doc = Nokogiri::HTML::Document.parse(doc.output)
        inline_styles = {}
        math_tags = parsed_doc.css("script[type='math/tex'], script[type='math/tex; mode=display']")
        for math_tag in math_tags do
          Jekyll.logger.warn "math: " + math_tag.content
          escaped_tag_content = math_tag.content.gsub(/'/, "\x27")
          inline = math_tag['type'].include?("mode=display") ? "" : "--inline"
          svg_outer_html = `node_modules/mathjax-node-cli/bin/tex2svg #{inline} '#{escaped_tag_content}'`
          svg_tag = math_tag.add_next_sibling(svg_outer_html)[0]
          addInlineStyle(svg_tag, inline_styles)
        end
        compileStyleElement(parsed_doc, inline_styles)
        doc.output = parsed_doc.to_html
      end

      def mathable?(doc)
        (doc.is_a?(Jekyll::Page) || doc.write?) &&
          doc.output_ext == ".html" || (doc.permalink && doc.permalink.end_with?("/"))
      end

    end
  end
end

Jekyll::Hooks.register [:documents], :post_render do |doc|
  Jekyll.logger.warn "Hook called"
  Jekyll::Mathifier.mathify(doc) if Jekyll::Mathifier.mathable?(doc)
end
