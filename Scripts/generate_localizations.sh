#!/bin/bash

# Localizations Generator for SystemEQ
# This script extracts all localization keys and updates .strings files

echo "🌍 Generating localization files..."

# Find all Swift files and extract NSLocalizedString keys
find "SystemEQ for Mac" -name "*.swift" -type f | while read file; do
    echo "Processing: $file"
    
    # Extract keys from NSLocalizedString calls
    grep -o 'NSLocalizedString(@"[^"]*"' "$file" | sed 's/NSLocalizedString(@"//; s/"//' >> temp_keys.txt
    
    # Extract keys from LocalizationKey enum usage
    grep -o '\.localized\([^)]*\)' "$file" | sed 's/\.localized(//; s/)//' >> temp_keys.txt
done

# Remove duplicates and sort
sort -u temp_keys.txt > all_keys.txt
rm temp_keys.txt

echo "Found $(wc -l < all_keys.txt) unique keys"

# Update English strings file (master)
echo "Updating English strings file..."
cat > "SystemEQ for Mac/Resources/Localizations/en.lproj/Localizable.strings" << 'EOF'
/* 
  Localizable.strings
  SystemEQ for Mac

  Created by Localization Generator
  Copyright © 2025 SystemEQ. All rights reserved.
*/
EOF

# Add all keys with empty values (to be filled by translators)
while read key; do
    echo "\"$key\" = \"\";" >> "SystemEQ for Mac/Resources/Localizations/en.lproj/Localizable.strings"
done < all_keys.txt

# Copy to other languages
echo "Copying to other languages..."
cp "SystemEQ for Mac/Resources/Localizations/en.lproj/Localizable.strings" \
   "SystemEQ for Mac/Resources/Localizations/it.lproj/Localizable.strings"

cp "SystemEQ for Mac/Resources/Localizations/en.lproj/Localizable.strings" \
   "SystemEQ for Mac/Resources/Localizations/uk.lproj/Localizable.strings"

# Clean up
rm all_keys.txt

echo "✅ Localization files generated!"
echo ""
echo "Next steps:"
echo "1. Translate the values in each .strings file"
echo "2. Run 'xcodebuild -exportLocalizations' to validate"
echo "3. Test with different languages in the app"
