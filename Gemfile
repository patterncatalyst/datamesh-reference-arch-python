source "https://rubygems.org"

# GitHub Pages uses a pinned set of gems. Keep this in sync with the
# version GitHub Pages currently runs:
#   https://pages.github.com/versions/
gem "jekyll", "~> 4.3"
gem "kramdown-parser-gfm"
gem "rouge"

group :jekyll_plugins do
  gem "jekyll-feed"     # generates /feed.xml automatically
  gem "jekyll-sitemap"  # generates /sitemap.xml automatically
  gem "jekyll-seo-tag"  # provides {% seo %} — used in _layouts/default.html
end

# Local `jekyll serve` on Ruby 3+ needs webrick explicitly
gem "webrick", "~> 1.8"
