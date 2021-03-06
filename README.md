# jekyll-mathjax-csp

Render math on the server using the [MathJax 3 node API](https://github.com/mathjax/MathJax-demos-node), while maintaining a strict [Content Security Policy (CSP)](https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP) without `'unsafe-inline'`.

While MathJax is well equipped to render beautiful math in a browser, letting it run in the client has two distinctive disadvantages: It is quite CPU-intensive and crucially relies on inline `style` attributes and elements. This Jekyll plugin aims to resolve both issues at once by rendering formulas to SVG images on the server, extracting all generated `style` attributes into a single `<style>` element in the head of the page and computing a hash over its content that can then be added as a CSP `style-src`.

The plugin runs the output of Jekyll's markdown parser [kramdown](http://kramdown.gettalong.org/) through the [MathJax 3 node API](https://github.com/mathjax/MathJax-demos-node) and thus behaves exactly as client-side MathJax in SVG rendering mode would.

## Usage

1. Install the npm packages `mathjax-full` and `yargs` from your top-level Jekyll directory:

   ```bash
   npm init -f # only if you don't have a package.json yet
   npm install mathjax-full yargs
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

* `mathjax-full` (npm): 3.0+
* `yargs` (npm): 16.1.0+
* `html-pipeline`: 2.3+
* `jekyll`: 3.0+

## Configuration

MathJax adds a fixed inline stylesheet to every page containing math. If you want to serve this stylesheet as an external `.css`, you can advise the plugin to strip it from the output by adding the following lines to your `_config.yml`:

```yaml
mathjax_csp:
  strip_css: true
```

Other configuration options for MathJax are also available:

| Key              | Description                                    | Default |
| ---------------- | ---------------------------------------------- | ------- |
| `em_size`        | Em-size, in pixels                             | `12`    |
| `ex_size`        | Ex-size, in pixels                             | `6`     |
| `single_dollars` | Allow single-dollar delimiters for inline math | `false` |
| `output`         | Output format: `SVG` or `CommonHTML`           | `SVG`   |


## Local testing

If you want to try out your CSP locally, you can specify headers in your `_config.yml`:

```yaml
webrick:
  headers:
    Content-Security-Policy: >-
      default-src 'none'; script-src ...
```

It is unfortunately not possible to have Liquid tags in `_config.yml`, so with this approach, you will have to update your CSP manually. Don't forget to restart `jekyll` for it to pick up the config changes.

Another possibility is using a [`meta` tag with `http-equiv`](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta#attr-http-equiv), placed in your pages' `<head>` element:

```html
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src ...">
```

Note that this cannot be used with frame-ancestors, report-uri, or sandbox.

## License

MIT
