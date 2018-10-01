Gem::Specification.new do |s|
  s.name = "jekyll-mathjax-csp"
  s.description = "Server-side MathJax rendering for Jekyll with a strict CSP"
  s.summary = "Server-side MathJax & CSP for Jekyll"
  s.version = "1.1.0"
  s.author = "Fabian Henneke"
  s.email = "fabian@henneke.me"
  s.homepage = "https://github.com/FabianHenneke/jekyll-mathjax-csp"

  s.license = "MIT"
  s.files = ["lib/jekyll-mathjax-csp.rb"]
  s.extra_rdoc_files = ["README.md"]

  s.add_dependency "html-pipeline", "~> 2.3"
  s.add_dependency "jekyll", "~> 3.0"
end
