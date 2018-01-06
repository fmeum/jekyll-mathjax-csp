# Server-side, CSP-aware math rendering for Jekyll using mathjax-node-page
#
# The MIT License (MIT)
# =====================
#
# Copyright © 2018 Fabian Henneke
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation
# files (the “Software”), to deal in the Software without
# restriction, including without limitation the rights to use,
# copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following
# conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.

require "html/pipeline"
require "jekyll"

require "digest"
require "open3"
require "securerandom"
require "set"

module Jekyll

  # Run Jekyll documents through mathjax-node-page, transform style attributes into inline style
  # tags and compute their hashes
  class Mathifier

    BODY_START_TAG = "<body".freeze
    MATH_TAG_REGEX = /<script[^>]*type="math\/tex/i

    class << self

      # Extract all style attributes from SVG elements and replace them by a new CSS class with a
      # deterministic name
      def extractStyleAttributes(parsed_doc)
        style_attributes = {}
        svg_tags = parsed_doc.css("svg[style]")
        for svg_tag in svg_tags do
          style_attribute = svg_tag["style"]
          digest = Digest::MD5.hexdigest(style_attribute)
          style_attributes[digest] = style_attribute

          digest_class = "mathjax-inline-#{digest}"
          svg_tag["class"] = "#{svg_tag["class"] || ""} #{digest_class}"
          svg_tag.remove_attribute("style")
        end
        return style_attributes
      end

      # Compute a CSP hash source (using SHA256)
      def hashStyleTag(style_tag)
        csp_digest = "'sha256-#{Digest::SHA256.base64digest(style_tag.content)}'"
        style_tag.add_previous_sibling("<!-- #{csp_digest} -->")
        @@config["csp_hashes"].add(csp_digest)
      end

      # Compile all style attributes into CSS classes in a single <style> element in the head
      def compileStyleElement(parsed_doc, style_attributes)
        style_content = ""
        style_attributes.each do |digest, style_attribute|
          style_content += ".mathjax-inline-#{digest}{#{style_attribute}}"
        end
        style_tag = parsed_doc.at_css("head").add_child("<style>#{style_content}</style>")[0]
        hashStyleTag(style_tag)
      end

      # Run mathjax-node-page on a String containing an HTML doc
      def run_mjpage(output)
        mathified = ""
        exit_status = 0
        Open3.popen2("node_modules/mathjax-node-page/bin/mjpage") {|i,o,t|
          i.print output
          i.close
          o.each {|line|
            mathified.concat(line)
          }
          exit_status = t.value
        }
        return mathified unless exit_status != 0
        Jekyll.logger.abort_with "mathjax_csp:", "Failed to execute 'node_modules/mathjax-node-page/mjpage'"
      end

      # Render math
      def mathify(doc, config)
        @@config ||= config

        return unless MATH_TAG_REGEX.match?(doc.output)
        Jekyll.logger.info "Rendering math:", doc.relative_path
        parsed_doc = Nokogiri::HTML::Document.parse(doc.output)
        # Ensure that all styles we pick up weren't present before mjpage ran
        unless parsed_doc.css("svg[style]").empty?()
          Jekyll.logger.abort_with "mathjax_csp:", "Inline style on <svg> element present before running 'mjpage'"
          Jekyll.logger.abort_with "", "This signals a misconfiguration or a server-side style injection."
        end

        mjpage_output = run_mjpage(doc.output)
        parsed_doc = Nokogiri::HTML::Document.parse(mjpage_output)
        last_child = parsed_doc.at_css("head").last_element_child()
        if last_child.name == "style"
          # Set strip_css to true in _config.yml if you load the styles mjpage adds to the head
          # from an external *.css file
          if @@config["strip_css"]
            Jekyll.logger.info "", "Remember to <link> in external stylesheet!"
            last_child.remove
          else
            hashStyleTag(last_child)
          end
        else
          Jekyll.logger.abort_with "mathjax_csp:", "No mathjax-node-page inline CSS found"
        end

        style_attributes = extractStyleAttributes(parsed_doc)
        compileStyleElement(parsed_doc, style_attributes)
        doc.output = parsed_doc.to_html
      end

      def mathable?(doc)
        (doc.is_a?(Jekyll::Page) || doc.write?) &&
          doc.output_ext == ".html" || (doc.permalink && doc.permalink.end_with?("/"))
      end
    end
  end

  # Register the page with the {% mathjax_sources %} Liquid tag for the second pass and temporarily
  # emit a placeholder, later to be replaced by the list of MathJax-related CSP hashes
  class MathJaxSourcesTag < Liquid::Tag

    def initialize(tag_name, text, tokens)
      super
    end

    def render(context)
      config = context.registers[:site].config["mathjax_csp"]
      if config["second_pass"]
        return config["final_source_list"]
      else
        config["second_pass_docs"].add(context.registers[:page]["path"])
        # Leave Liquid tag in place for second pass
        return "{% mathjax_sources %}"
      end
    end
  end
end

Liquid::Template.register_tag('mathjax_sources', Jekyll::MathJaxSourcesTag)

# Set up plugin config
Jekyll::Hooks.register [:site], :after_init do |site|
  config = site.config["mathjax_csp"] || {}
  # A set of CSP hash sources to be added as style sources; populated automatically
  config["csp_hashes"] ||= []
  config["csp_hashes"] = Set.new(config["csp_hashes"])
  # This is the first pass (mathify & collect hashes), the second pass (insert hashes into CSP
  # rules) is triggered manually
  config["second_pass"] = false
  # A set of Jekyll documents to which the hash sources should be added; populated automatically
  config["second_pass_docs"] ||= []
  config["second_pass_docs"] = Set.new(config["second_pass_docs"])
  site.config["mathjax_csp"] = config
end

# Replace math blocks with SVG renderings using mathjax-node-page and collect inline styles in a
# single <style> element
Jekyll::Hooks.register [:documents], :post_render do |doc|
  if Jekyll::Mathifier.mathable?(doc)
    Jekyll::Mathifier.mathify(doc, doc.site.config["mathjax_csp"])
  end
end

# Run over all documents with {% mathjax_sources %} Liquid tags again and insert the list of CSP
# hash sources coming from MathJax styles
Jekyll::Hooks.register [:site], :post_write do |site, payload|
  site.config["mathjax_csp"]["second_pass"] = true
  config = site.config["mathjax_csp"]
  config["final_source_list"] = config["csp_hashes"].to_a().join(" ")
  if config["second_pass_docs"].empty?()
    Jekyll.logger.warn "mathjax_csp:", "Add the following to the style-src part of your CSP:"
    Jekyll.logger.warn "", config["final_source_list"]
  else
    Jekyll.logger.info "Adding CSP sources:", config["second_pass_docs"].to_a().join(" ")
    site.pages.flatten.each do |page|
      if config["second_pass_docs"].include?(page.path)
        # Rerender the page
        page.output = Jekyll::Renderer.new(site, page, payload).run()
        page.trigger_hooks(:post_render)
        page.write(site.dest)
        page.trigger_hooks(:post_write)
      end
    end
  end
end
