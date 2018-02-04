Gem::Specification.new do |s|
  s.name = "jekyll-mathjax-csp"
  s.summary = "Server-side MathJax rendering for Jekyll with a strict CSP"
  s.version = "0.0.1"
  s.author = "Fabian Henneke"
  s.homepage = "https://github.com/FabianHenneke/jekyll-mathjax-csp"

  s.license = "MIT"
  s.files = ["lib/jekyll-mathjax-csp.rb"]

  s.add_dependency "html-pipeline", "~> 2.3"
  s.add_dependency "jekyll", "~> 3.0"
end
