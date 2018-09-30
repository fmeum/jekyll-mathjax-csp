# jekyll-mathjax-csp

Render math on the server using [MathJax-node](https://github.com/mathjax/MathJax-node), while maintaining a strict [Content Security Policy (CSP)](https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP) without `'unsafe-inline'`.

While MathJax is well equipped to render beautiful math in a browser, letting it run in the client has two distinctive disadvantages: It is quite CPU-intensive and crucially relies on inline `style` attributes and elements. This Jekyll plugin aims to resolve both issues at once by rendering formulas to SVG images on the server, extracting all generated `style` attributes into a single `<style>` element in the head of the page and computing a hash over its content that can then be added as a CSP `style-src`.

The plugin runs the output of Jekyll's markdown parser [kramdown](http://kramdown.gettalong.org/) through the CLI converter `mjpage` offered by the npm package [`mathjax-node-page`](https://github.com/pkra/mathjax-node-page) and thus behaves exactly as client-side MathJax in SVG rendering mode would.

## Usage

1. Install the npm package `mathjax-node-page` from your top-level Jekyll directory:

   ```bash
   npm init -f # only if you don't have a package.json yet
   npm install mathjax-node-page@2.X
   ```

2. Install `jekyll-mathjax-csp`:

   ```bash
   gem install jekyll-mathjax-csp
   ```

3. Ensure that your `_config.yml` contains the following settings:

   ```yaml
   plugins:
     - jekyll-mathjax-csp

   exclude:
     - node_modules
     - package.json
     - package-lock.json
   ```

4. Add the `{% mathjax_csp_sources %}` Liquid tag where you want the CSP `'sha256-...'` hashes for `<style>` elements to be emitted. Don't forget to add the YAML front matter (two lines of `---`) to such files. If you specify your CSP in a different way, add the `style-src` sources the plugins prints to the console during build.

5. Include beautiful math in your posts!

## Dependencies

* `mathjax-node-page` (npm): 2.0+
* `html-pipeline`: 2.3+
* `jekyll`: 3.0+

## Configuration

The following fields can be set in `_config.yml`; their default values are given in the sample below.

```yaml
mathjax_csp:
  linebreaks: false
  single_dollars: false
  format: AsciiMath,TeX,MathML
  font: TeX
  semantics: false
  notexthints: false
  output: SVG
  eqno: none
  ex_size: 6
  width: 100
  extensions: ""
  font_url: "https://cdnjs.cloudflare.com/ajax/libs/mathjax/2.7.2/fonts/HTML-CSS"
  strip_css: false
```
'mathjax-node-page' adds a fixed inline stylesheet to every page containing math. If you want to serve this stylesheet as an external `.css`, you can advise the plugin to strip it from the output by adding the following lines to your `_config.yml`:

```yaml
mathjax_csp:
  strip_css: true
```

Configuration for 'mathjax-node-page' is also available:

| Key              | Description                                                  | Default                                                      |
| ---------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| `linebreaks`     | Perform automatic line-breaking                              | `false`                                                      |
| `single_dollars` | Allow single-dollar delimiters for inline math               | `false`                                                      |
| `format`         | Input format(s) to look for                                  | `AsciiMath,TeX,MathML`                                       |
| `font`           | Web font to use in SVG output                                | `TeX`                                                        |
| `semantics`      | For TeX or Asciimath source and MathML output, add input in `<semantics>` tag | `false`                                                      |
| `notexthints`    | For TeX input and MathML output, don't add TeX-specific classes | `false`                                                      |
| `output`         | Output format: SVG, CommonHTML, or MML                       | `SVG`                                                        |
| `eqno`           | Equation number style (none, AMS, or all)                    | `none`                                                       |
| `ex_size`        | Ex-size, in pixels                                           | `6`                                                          |
| `width`          | Width of equation container in `ex`. Used for line-breaking  | `100`                                                        |
| `extensions`     | Extra MathJax extensions (e.g. `Safe,Tex/noUndefined`)       | `""`                                                         |
| `font_url`       | URL to use for web fonts                                     | `https://cdnjs.cloudflare.com/ajax/libs/mathjax/2.7.2/fonts/HTML-CSS` |

## Local testing

If you want to try out your CSP locally, you can specify headers in your `_config.yml`:

```yaml
webrick:
  headers:
    Content-Security-Policy: >-
      default-src 'none'; script-src ...
```

It is unfortunately not possible to have Liquid tags in `_config.yml`, so you will have to update your CSP manually. Don't forget to restart `jekyll` for it to pick up the config changes.

## License

MIT