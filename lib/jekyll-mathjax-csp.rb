# coding: utf-8
# Server-side, CSP-aware math rendering for Jekyll using MathJax's node API
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
require "set"

module Jekyll

  # Run Jekyll documents through MathJax's node engine, transform style attributes into inline style
  # tags and compute their hashes
  class Mathifier
    MATH_TAG_REGEX = /(<script[^>]*type="math\/tex|\\\[.*\\\]|\\\(.*\\\))/im

    FIELDS = {
      "em_size" => "--em",
      "ex_size" => "--ex",
      "single_dollars" => "--singleDollars",
      "output" => "--output",
    }

    class << self
      attr_accessor :csp_hashes

      # Extract all style attributes from SVG and container elements and replace them with a new
      # CSS class with a deterministic name
      def extractStyleAttributes(parsed_doc)
        style_attributes = {}
        styled_tags = parsed_doc.css("svg[style],mjx-container[style]")
        for styled_tag in styled_tags do
          style_attribute = styled_tag["style"]
          digest = Digest::MD5.hexdigest(style_attribute)[0..15]
          style_attributes[digest] = style_attribute

          digest_class = "mathjax-inline-#{digest}"
          styled_tag["class"] = "#{styled_tag["class"] || ""} #{digest_class}"
          styled_tag.remove_attribute("style")
        end
        return style_attributes
      end

      # Compute a CSP hash source (using SHA256)
      def hashStyleTag(style_tag)
        csp_digest = "'sha256-#{Digest::SHA256.base64digest(style_tag.content)}'"
        style_tag.add_previous_sibling("<!-- #{csp_digest} -->")
        @csp_hashes.add(csp_digest)
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

      # Run the MathJax node backend on a JSON input containing an file: HTML map
      def run_mathjaxify(config, input)
        mathified = ""
        exit_status = 0
        command = "node #{Gem.bin_path("jekyll-mathjax-csp", "mathjaxify")}"

        FIELDS.each do |name, flag|
          unless config[name].nil?
            if [true, false].include? config[name]
              command << " " << flag
            else
              command << " " << flag << " " << config[name].to_s
            end
          end
        end

        node_path = Dir.pwd + "/node_modules"
        Jekyll.logger.info "mathjax_csp:", "starting node #{command}"
        mathified, status = Open3.capture2({"NODE_PATH" => node_path}, command, stdin_data: input)
        return mathified unless status != 0
        Jekyll.logger.abort_with "mathjax_csp:", "Failed to execute 'bin/mathjaxify'"
      end

      # Render math in batch for all documents
      def mathify(docs, config)
        docs = docs.select { |d| Jekyll::Mathifier.mathable?(d) } # can be mathified?
                   .select { |d| MATH_TAG_REGEX.match?(d.output) } # needs mathifying?
                   .reduce({}) { |h, d| h.merge!(d.path => d) } # use #path to identify a doc
        return if docs.empty?

        Jekyll.logger.info "mathjax_csp:", "Found #{docs.length} documents."

        docs.each do |path, doc|
          Jekyll.logger.info "Checking math:", path
          parsed_doc = Nokogiri::HTML::Document.parse(doc.output)
          # Ensure that all styles we pick up weren't present before MathJax ran
          unless parsed_doc.css("svg[style],mjx-container[style]").empty?
            Jekyll.logger.error "mathjax_csp:", "Inline style on <svg> or <mjx-container> element present"
            Jekyll.logger.error "", "before rendering math due to misconfiguration or server-side"
            Jekyll.logger.abort_with "", "style injection."
          end
        end

        mathjaxify_input = docs.reduce({}) { |h, (path, doc)| h.merge!(path => doc.output) }
                               .to_json
        mathified_docs = JSON.parse(run_mathjaxify(config, mathjaxify_input))

        mathified_docs.each do |path, mathified_html|
          parsed_doc = Nokogiri::HTML::Document.parse(mathified_html)
          last_child = parsed_doc.at_css("head").last_element_child()
          if last_child.name == "style"
            # Set strip_css to true in _config.yml if you load the styles MathJax adds to the head
            # from an external *.css file
            if config["strip_css"]
              Jekyll.logger.info "", "Remember to <link> in external stylesheet!"
              last_child.remove
            else
              hashStyleTag(last_child)
            end
          end

          style_attributes = extractStyleAttributes(parsed_doc)
          compileStyleElement(parsed_doc, style_attributes)
          docs[path].output = parsed_doc.to_html
        end

        Jekyll.logger.info "mathjax_csp:", "Mathified #{mathified_docs.length} documents."
      end

      def mathable?(doc)
        (doc.is_a?(Jekyll::Page) || doc.write?) &&
          doc.output_ext == ".html" || (doc.permalink && doc.permalink.end_with?("/"))
      end
    end
  end

  # Register the page with the {% mathjax_csp_sources %} Liquid tag for the second pass and
  # temporarily emit a placeholder, later to be replaced by the list of MathJax-related CSP hashes
  class MathJaxSourcesTag < Liquid::Tag

    class << self
      attr_accessor :final_source_list, :second_pass, :second_pass_docs, :unrendered_docs
    end

    def initialize(tag_name, text, tokens)
      super
    end

    def render(context)
      page = context.registers[:page]
      if self.class.second_pass
        return self.class.final_source_list
      else
        self.class.second_pass_docs.add(page["path"])
        # Placeholder (hash corresponds to the empty script element)
        return "'sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU='"
      end
    end
  end
end

Liquid::Template.register_tag("mathjax_csp_sources", Jekyll::MathJaxSourcesTag)

# Set up plugin config
Jekyll::Hooks.register :site, :pre_render do |site|
  # A set of CSP hash sources to be added as style sources; populated automatically
  Jekyll::Mathifier.csp_hashes = Set.new([])
  # This is the first pass (mathify & collect hashes), the second pass (insert hashes into CSP
  # rules) is triggered manually
  Jekyll::MathJaxSourcesTag.second_pass = false
  # A set of Jekyll documents to which the hash sources should be added; populated automatically
  Jekyll::MathJaxSourcesTag.second_pass_docs = Set.new([])
  # The original file content of documents
  Jekyll::MathJaxSourcesTag.unrendered_docs = {}
end

# Keep original (Markdown) content of documents around for the second rendering pass
Jekyll::Hooks.register [:documents, :pages], :pre_render do |doc|
  Jekyll::MathJaxSourcesTag.unrendered_docs[doc.relative_path] = doc.content
end

# Replace math blocks with SVG renderings using mathjaxify and collect inline styles in a
# single <style> element
Jekyll::Hooks.register :site, :post_render do |site|
  Jekyll::Mathifier.mathify(site.posts.docs + site.pages, site.config["mathjax_csp"] || {})
end

# Run over all documents with {% mathjax_sources %} Liquid tags again and insert the list of CSP
# hash sources coming from MathJax styles
Jekyll::Hooks.register :site, :post_render do |site, payload|
  Jekyll::MathJaxSourcesTag.second_pass = true
  Jekyll::MathJaxSourcesTag.final_source_list = Jekyll::Mathifier.csp_hashes.to_a().join(" ")
  if Jekyll::MathJaxSourcesTag.second_pass_docs.empty?()
    Jekyll.logger.info "mathjax_csp:", "Add the following to the style-src part of your CSP:"
    Jekyll.logger.info "", Jekyll::MathJaxSourcesTag.final_source_list
  else
    second_pass_docs_str = Jekyll::MathJaxSourcesTag.second_pass_docs.to_a().join(" ")
    Jekyll.logger.info "Adding CSP sources:", second_pass_docs_str
    rerender = proc { |docs, uses_absolute_path|
      docs.each do |doc|
        relative_path = uses_absolute_path ? doc.relative_path : doc.path
        if Jekyll::MathJaxSourcesTag.second_pass_docs.include?(relative_path)
          # Rerender the page
          doc.content = Jekyll::MathJaxSourcesTag.unrendered_docs[relative_path]
          doc.output = Jekyll::Renderer.new(site, doc, payload).run()
          doc.trigger_hooks(:post_render)
        end
      end
    }
    rerender.call(site.pages, false)
    rerender.call(site.docs_to_write, true)
  end
end
