class Ses < Formula
  desc "Speech Event Stream CLI"
  homepage "https://github.com/rioriost/homebrew-ses"
  url "https://github.com/rioriost/homebrew-ses/releases/download/v0.0.2/ses-0.0.2-macos.tar.gz"
  sha256 "c321a4354f3a7691820c34e4064841543fdd162928cb4e3a1bcbe9b6f158d822"
  version "0.0.2"

  def install
    bin.install "ses"
  end
end
