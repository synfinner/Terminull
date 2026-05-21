import AppKit
import SwiftTerm

enum ClickableTerminalCursorMovement {
    static func shouldHandle(
        clickCount: Int,
        modifierFlags: NSEvent.ModifierFlags,
        isAlternateScreen: Bool,
        isMouseReportingActive: Bool,
        clickedRow: Int,
        cursorRow: Int
    ) -> Bool {
        clickCount == 1
            && modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
            && !isAlternateScreen
            && !isMouseReportingActive
            && clickedRow == cursorRow
    }

    static func arrowBytes(fromColumn: Int, toColumn: Int, applicationCursor: Bool) -> [UInt8] {
        let distance = toColumn - fromColumn
        guard distance != 0 else {
            return []
        }

        let sequence: [UInt8]
        if distance < 0 {
            sequence = applicationCursor ? [0x1b, 0x4f, 0x44] : [0x1b, 0x5b, 0x44]
        } else {
            sequence = applicationCursor ? [0x1b, 0x4f, 0x43] : [0x1b, 0x5b, 0x43]
        }

        return Array(repeating: sequence, count: abs(distance)).flatMap { $0 }
    }

    static func movementBytes(
        fromColumn: Int,
        toColumn: Int,
        columnCount: Int,
        applicationCursor: Bool
    ) -> [UInt8] {
        let maxColumn = max(0, columnCount - 1)
        if toColumn <= 0 {
            return [0x01]
        }
        if toColumn >= maxColumn {
            return [0x05]
        }

        return arrowBytes(
            fromColumn: fromColumn,
            toColumn: toColumn,
            applicationCursor: applicationCursor
        )
    }

    static func targetColumn(
        clickedColumn: Int,
        columnCount: Int,
        contentRange: ClosedRange<Int>?
    ) -> Int {
        let maxColumn = max(0, columnCount - 1)
        let clampedColumn = min(max(clickedColumn, 0), maxColumn)

        guard let contentRange else {
            return clampedColumn
        }

        if clickedColumn <= contentRange.lowerBound {
            return 0
        }
        if clickedColumn > contentRange.upperBound {
            return maxColumn
        }

        return clampedColumn
    }
}

final class ClickableLocalProcessTerminalView: LocalProcessTerminalView {
    private var mouseMonitor: Any?

    deinit {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
    }

    func installClickableCursorMonitor() {
        guard mouseMonitor == nil else {
            return
        }

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard self?.handleCursorClick(event) == true else {
                return event
            }
            return nil
        }
    }

    private func handleCursorClick(_ event: NSEvent) -> Bool {
        guard event.window === window, let targetColumn = cursorTargetColumn(for: event) else {
            return false
        }

        let bytes = ClickableTerminalCursorMovement.movementBytes(
            fromColumn: terminal.buffer.x,
            toColumn: targetColumn,
            columnCount: terminal.cols,
            applicationCursor: terminal.applicationCursor
        )
        if !bytes.isEmpty {
            send(bytes)
        }
        window?.makeFirstResponder(self)
        return true
    }

    private func cursorTargetColumn(for event: NSEvent) -> Int? {
        guard process?.running == true, terminal.cols > 0 else {
            return nil
        }

        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point), !caretFrame.isEmpty else {
            return nil
        }

        let rowHeight = max(1, caretFrame.height)
        let cursorRow = Int((bounds.height - caretFrame.midY) / rowHeight)
        let clickedRow = Int((bounds.height - point.y) / rowHeight)
        guard ClickableTerminalCursorMovement.shouldHandle(
            clickCount: event.clickCount,
            modifierFlags: event.modifierFlags,
            isAlternateScreen: terminal.isCurrentBufferAlternate,
            isMouseReportingActive: allowMouseReporting && terminal.mouseMode != .off,
            clickedRow: clickedRow,
            cursorRow: cursorRow
        ) else {
            return nil
        }

        let width = max(1, caretFrame.width)
        let clickedColumn = Int(point.x / width)
        return ClickableTerminalCursorMovement.targetColumn(
            clickedColumn: clickedColumn,
            columnCount: terminal.cols,
            contentRange: visibleContentRange(for: cursorRow)
        )
    }

    private func visibleContentRange(for row: Int) -> ClosedRange<Int>? {
        guard let line = terminal.getLine(row: row) else {
            return nil
        }

        let maxColumn = min(line.count, terminal.cols) - 1
        guard maxColumn >= 0 else {
            return nil
        }

        var firstColumn: Int?
        var lastColumn: Int?
        for column in 0...maxColumn where line.hasContent(index: column) {
            if firstColumn == nil {
                firstColumn = column
            }
            lastColumn = column
        }

        guard let firstColumn, let lastColumn else {
            return nil
        }
        return firstColumn...lastColumn
    }
}
