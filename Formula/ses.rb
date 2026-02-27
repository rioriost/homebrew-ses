class Ses < Formula
  desc "Speech Event Stream CLI"
  homepage "https://github.com/rioriost/homebrew-ses"
  url "https://github.com/rioriost/homebrew-ses/releases/download/v0.0.1/ses-0.0.1-macos.tar.gz"
  sha256 "2a515471c67421b981e20e70e498579a902fa7736939a701149a87e4334cacce"
  version "0.0.1"

  def install
    bin.install "ses"
  end
end

