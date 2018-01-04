require "html/pipeline"
require "jekyll"

require "digest"
require "open3"
require "securerandom"
require "set"

module Jekyll
  class Mathifier
    BODY_START_TAG = "<body".freeze

    MATH_TAG_REGEX = /<script[^>]*type="math\/tex/i

    class << self

      def extractInlineStyles(parsed_doc)
        inline_styles = {}
        svg_tags = parsed_doc.css("svg[style]")
        for svg_tag in svg_tags do
          inline_style = svg_tag["style"]
          digest = Digest::MD5.hexdigest(inline_style)
          inline_styles[digest] = inline_style

          digest_class = "mathjax-inline-#{digest}"
          svg_tag["class"] = "#{svg_tag["class"] || ""} #{digest_class}"
          svg_tag.remove_attribute("style")
        end
        return inline_styles
      end

      def hashStyleTag(style_tag)
        csp_digest = "'sha256-#{Digest::SHA256.base64digest(style_tag.content)}'"
        style_tag.add_previous_sibling("<!-- #{csp_digest} -->")
        @@config["csp_hashes"].add(csp_digest)
      end

      def compileStyleElement(parsed_doc, inline_styles)
        style_content = ""
        inline_styles.each do |digest, inline_style|
          style_content += ".mathjax-inline-#{digest}{#{inline_style}}"
        end
        style_tag = parsed_doc.at_css("head").add_child("<style>#{style_content}</style>")[0]
        hashStyleTag(style_tag)
      end

      def run_mjpage(doc)
        mathified = ""
        exit_status = 0
        Open3.popen2("node_modules/mathjax-node-page/bin/mjpage") {|i,o,t|
          i.print doc.output
          i.close
          o.each {|line|
            mathified += line
          }
          exit_status = t.value
        }
        return mathified unless exit_status != 0
        Jekyll.logger.abort_with "mathjax_csp:", "Failed to execute 'node_modules/mathjax-node-page/mjpage'"
      end

      def mathify(doc, config)
        @@config ||= config

        return unless MATH_TAG_REGEX.match?(doc.output)
        Jekyll.logger.info "Rendering math:", doc.relative_path

        mjpage_output = run_mjpage(doc)
        parsed_doc = Nokogiri::HTML::Document.parse(mjpage_output)
        last_child = parsed_doc.at_css("head").last_element_child()
        if last_child.name == "style"
          if @@config["strip_css"]
            Jekyll.logger.warn "Removed static CSS:",  "Remember to <link> in external stylesheet"
            last_child.remove
          else
            hashStyleTag(last_child)
          end
        else
          Jekyll.logger.abort_with "mathjax_csp:", "No mathjax-node-page inline CSS found"
        end

        inline_styles = extractInlineStyles(parsed_doc)
        compileStyleElement(parsed_doc, inline_styles)
        doc.output = parsed_doc.to_html
      end

      def mathable?(doc)
        (doc.is_a?(Jekyll::Page) || doc.write?) &&
          doc.output_ext == ".html" || (doc.permalink && doc.permalink.end_with?("/"))
      end
    end
  end

  class MathJaxSourcesTag < Liquid::Tag

    def initialize(tag_name, text, tokens)
      super
    end

    def render(context)
      config = context.registers[:site].config["mathjax_csp"]
      config["second_pass_docs"].add(context.registers[:page]["path"])
      return config["mathjax_sources_marker"]
    end
  end

  class SourceMarkerReplacer

    class << self

      def replace(file_name, config)
        contents = File.read(file_name)
        new_contents = contents.gsub(config["mathjax_sources_marker"], config["final_source_list"])
        File.open(file_name, "w") {|file| file.puts new_contents }
      end
    end
  end
end

Liquid::Template.register_tag('mathjax_sources', Jekyll::MathJaxSourcesTag)

Jekyll::Hooks.register [:site], :after_init do |site|
  config = site.config["mathjax_csp"] || {}
  config["csp_hashes"] ||= []
  config["csp_hashes"] = Set.new(config["csp_hashes"])
  config["second_pass_docs"] ||= []
  config["second_pass_docs"] = Set.new(config["second_pass_docs"])
  config["mathjax_sources_marker"] = "'mathjax-sources-marker-#{SecureRandom.hex()}'"
  site.config["mathjax_csp"] = config
end

Jekyll::Hooks.register [:documents], :post_render do |doc|
  Jekyll::Mathifier.mathify(doc, doc.site.config["mathjax_csp"]) if Jekyll::Mathifier.mathable?(doc)
end

Jekyll::Hooks.register [:site], :post_write do |site, payload|
  config = site.config["mathjax_csp"]
  config["final_source_list"] = config["csp_hashes"].to_a().join(" ")
  if config["second_pass_docs"].empty?()
    Jekyll.logger.warn "mathjax_csp:", "Add the following to the style-src part of your CSP:"
    Jekyll.logger.warn "mathjax_csp:", config["final_source_list"]
  else
    for relative_path in config["second_pass_docs"]
      Jekyll.logger.info "Adding CSP sources:", relative_path
      absolute_path = File.join(site.config["destination"], relative_path)
      Jekyll::SourceMarkerReplacer.replace(absolute_path, config)
    end
  end
end
