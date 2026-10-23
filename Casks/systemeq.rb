cask "systemeq" do
  version "1.4.6"
  sha256 "378b490354e5746a8cafc20a631d786274f856b96ae994ae19287a491962eb55"

  url "https://github.com/denzam/SystemEQ-for-Mac/releases/download/v#{version}/SystemEQ-v#{version}.dmg"
  name "SystemEQ for Mac"
  desc "System-wide equalizer with AutoEQ support"
  homepage "https://github.com/denzam/SystemEQ-for-Mac"

  depends_on macos: :ventura

  app "SystemEQ for Mac.app"

  zap trash: [
    "~/Library/Application Support/SystemEQ",
    "~/Library/Caches/com.denzam.SystemEQ",
    "~/Library/Preferences/com.denzam.SystemEQ.plist",
  ]
end
