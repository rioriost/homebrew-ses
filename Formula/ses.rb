class Ses < Formula
  desc "Speech Event Stream CLI"
  homepage "https://github.com/rioriost/homebrew-ses"
  url "https://github.com/rioriost/homebrew-ses/releases/download/v0.0.3/ses-0.0.3-macos.tar.gz"
  sha256 "14d8ee0c19f1af056933a9693cf1e4622b6ce0aff5f64b5d3fcd1e0897494d8d"
  version "0.0.3"

  def install
    bin.install "ses"
  end
end
