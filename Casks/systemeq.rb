cask "systemeq" do
  version "1.0.7"
  sha256 "c0d1a7046bea8debae14c4d2d6df6cb7b8be018a3c212680db9640a28561cdb4"

  url "https://github.com/denzam/SystemEQ-for-Mac/releases/download/v#{version}/SystemEQ-v#{version}.dmg"
  name "SystemEQ for Mac"
  desc "System-wide equalizer for macOS with AutoEQ support"
  homepage "https://github.com/denzam/SystemEQ-for-Mac"

  depends_on macos: ">= :ventura"

  app "SystemEQ for Mac.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/SystemEQ for Mac.app"]
  end

  zap trash: [
    "~/Library/Application Support/SystemEQ",
    "~/Library/Preferences/com.denzam.SystemEQ.plist",
    "~/Library/Caches/com.denzam.SystemEQ",
  ]
end
