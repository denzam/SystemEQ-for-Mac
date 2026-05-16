cask "systemeq" do
  version "1.0.2"
  sha256 "fed47f8fb08421883a3e4ddac0b16f7cb5d8727cab44630dc232d9585330c857"

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
