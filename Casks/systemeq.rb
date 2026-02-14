cask "systemeq" do
  version "1.0.0"
  sha256 :no_check # Update with actual SHA256 after first release

  url "https://github.com/denyszamorniak/SystemEQ-for-Mac/releases/download/v#{version}/SystemEQ-v#{version}.dmg"
  name "SystemEQ for Mac"
  desc "System-wide equalizer for macOS with AutoEQ support"
  homepage "https://github.com/denyszamorniak/SystemEQ-for-Mac"

  depends_on macos: ">= :ventura"

  app "SystemEQ for Mac.app"

  zap trash: [
    "~/Library/Application Support/SystemEQ",
    "~/Library/Preferences/com.denzam.SystemEQ.plist",
    "~/Library/Caches/com.denzam.SystemEQ",
  ]
end
