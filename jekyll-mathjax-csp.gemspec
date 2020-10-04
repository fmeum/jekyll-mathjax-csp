Gem::Specification.new do |s|
  s.name = "jekyll-mathjax-csp"
  s.description = "Server-side MathJax rendering for Jekyll with a strict CSP"
  s.summary = "Server-side MathJax & CSP for Jekyll"
  s.version = "2.0.0"
  s.author = "Fabian Henneke"
  s.email = "fabian@hen.ne.ke"
  s.homepage = "https://github.com/FabianHenneke/jekyll-mathjax-csp"

  s.license = "MIT"
  s.files = [
    "lib/jekyll-mathjax-csp.rb",
    "bin/mathjaxify",
  ]
  s.extra_rdoc_files = ["README.md"]
  s.executables = ["mathjaxify"]
  s.bindir = "bin"

  s.add_dependency "html-pipeline", "~> 2.12"
  s.add_dependency "jekyll", ">= 3.0", "< 5.0"
end
