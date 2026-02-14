//
//  NSAlert+Extension.swift
//  SystemEQ for Mac
//
//  Created by Assistant on 28/12/25.
//

import AppKit

extension NSAlert {
    static func show(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
