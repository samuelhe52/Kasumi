import AppKit

enum MacReaderCommand {
    case showInFinder, copyPath, exportPDF, printDocument
    case find(NSTextFinder.Action)
    case jumpToSelection
    case bold, italic, link
    case heading(Int)
    case code, quote
    case navigator, outline, source, actualSize
    case zoom(Double)
    case moveHeading(Int)
    case selectTab(Int?)

    @MainActor
    func isEnabled(for session: MacReaderSession) -> Bool {
        let canFormat = session.showingSource && session.document.canEdit
        switch self {
        case .showInFinder, .copyPath:
            return session.document.fileURL != nil
        case .exportPDF, .printDocument:
            return session.document.previewIsCurrent && !session.outputInProgress
        case .find(.showReplaceInterface), .bold, .italic, .link, .heading, .code, .quote:
            return canFormat
        case .find, .jumpToSelection, .source, .actualSize:
            return session.document.snapshot != nil
        case .zoom(let delta):
            let size = MacAppearancePreferences().appearance.fontSize
            let limits = ReaderAppearance.fontSizes
            return session.document.snapshot != nil && (delta > 0 ? size < limits.upperBound : size > limits.lowerBound)
        case .moveHeading:
            return !session.outline.isEmpty
        case .selectTab(let index):
            guard let group = session.window?.tabGroup else { return false }
            return index.map { group.windows.indices.contains($0) } ?? !group.windows.isEmpty
        case .navigator, .outline:
            return true
        }
    }

    @MainActor
    func validate(_ item: NSMenuItem, for session: MacReaderSession) -> Bool {
        switch self {
        case .navigator: item.state = MacPane.navigator.isVisible ? .on : .off
        case .outline: item.state = MacPane.outline.isVisible ? .on : .off
        case .source: item.title = session.showingSource ? "Show Reader" : "Show Source"
        default: break
        }
        return isEnabled(for: session)
    }

    @MainActor
    func perform(in session: MacReaderSession) {
        let appearance = MacAppearancePreferences()
        switch self {
        case .showInFinder: session.showInFinder()
        case .copyPath: session.copyPath()
        case .exportPDF: session.outputPDF(printing: false)
        case .printDocument: session.outputPDF(printing: true)
        case .find(let action): session.performFind(action)
        case .jumpToSelection: session.jumpToSelection()
        case .bold: session.source.apply(SourceFormatting.bold)
        case .italic: session.source.apply(SourceFormatting.italic)
        case .link: session.source.apply(SourceFormatting.link)
        case .heading(let level):
            session.source.apply { SourceFormatting.heading(in: $0, selection: $1, level: level) }
        case .code: session.source.apply(SourceFormatting.code)
        case .quote: session.source.apply(SourceFormatting.quote)
        case .navigator: (session.window?.contentViewController as? MacNavigatorSplit)?.toggle(.navigator)
        case .outline: (session.window?.contentViewController as? MacNavigatorSplit)?.toggle(.outline)
        case .source: session.toggleSource()
        case .actualSize: appearance.fontSize = ReaderAppearance.defaultFontSize
        case .zoom(let delta):
            let limits = ReaderAppearance.fontSizes
            appearance.fontSize = min(limits.upperBound, max(limits.lowerBound, appearance.appearance.fontSize + delta))
        case .moveHeading(let step): session.moveHeading(by: step)
        case .selectTab(let index): session.selectTab(index)
        }
    }
}

@MainActor
enum MacMenu {
    static func make(appDelegate: MacAppDelegate) -> NSMenu {
        let main = NSMenu()

        func menu(_ title: String, in parent: NSMenu = main) -> NSMenu {
            let submenu = NSMenu(title: title)
            parent.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = submenu
            return submenu
        }

        @discardableResult
        func item(
            _ title: String, _ action: Selector, _ key: String = "",
            modifiers: NSEvent.ModifierFlags = .command, in menu: NSMenu
        ) -> NSMenuItem {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            return item
        }

        func reader(
            _ title: String, _ command: MacReaderCommand, _ key: String = "",
            modifiers: NSEvent.ModifierFlags = .command, in menu: NSMenu
        ) {
            item(
                title, #selector(MacDocumentWindowController.performReaderCommand(_:)), key,
                modifiers: modifiers, in: menu
            ).representedObject = command
        }

        let application = menu("Kasumi")
        item("About Kasumi", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), in: application)
        item("Open Source Licenses", #selector(MacAppDelegate.showLicenses(_:)), in: application).target = appDelegate
        application.addItem(.separator())
        item("Settings…", #selector(MacAppDelegate.showSettings(_:)), ",", in: application).target = appDelegate
        application.addItem(.separator())
        NSApp.servicesMenu = menu("Services", in: application)
        application.addItem(.separator())
        item("Hide Kasumi", #selector(NSApplication.hide(_:)), "h", in: application)
        item(
            "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h",
            modifiers: [.command, .option], in: application)
        item("Show All", #selector(NSApplication.unhideAllApplications(_:)), in: application)
        application.addItem(.separator())
        item("Quit Kasumi", #selector(NSApplication.terminate(_:)), "q", in: application)

        let file = menu("File")
        item("New Window", #selector(MacDocumentController.newSeparateWindow(_:)), "n", in: file)
        item("New Tab", #selector(MacDocumentWindowController.newWindowForTab(_:)), "t", in: file)
        // AppKit inserts Open Recent next to the standard Open action.
        item("Open…", #selector(NSDocumentController.openDocument(_:)), "o", in: file)
        file.addItem(.separator())
        item("Close", #selector(NSWindow.performClose(_:)), "w", in: file)
        item("Save…", #selector(NSDocument.save(_:)), "s", in: file)
        item("Duplicate", #selector(NSDocument.duplicate(_:)), "s", modifiers: [.command, .shift], in: file)
        item(
            "Save As…", #selector(NSDocument.saveAs(_:)), "s",
            modifiers: [.command, .shift, .option], in: file
        ).isAlternate = true
        item("Rename…", #selector(NSDocument.rename(_:)), in: file)
        item("Move To…", #selector(NSDocument.move(_:)), in: file)
        item("Revert To", #selector(NSDocument.revertToSaved(_:)), in: file)
        file.addItem(.separator())
        reader("Show in Finder", .showInFinder, "r", modifiers: [.command, .option], in: file)
        reader("Copy Path", .copyPath, "c", modifiers: [.command, .option, .shift], in: file)
        item(
            "Paste as New Document", #selector(MacDocumentController.pasteAsNewDocument(_:)), "v",
            modifiers: [.command, .shift], in: file)
        file.addItem(.separator())
        reader("Export as PDF…", .exportPDF, in: file)
        reader("Print…", .printDocument, "p", in: file)

        let edit = menu("Edit")
        item("Undo", Selector(("undo:")), "z", in: edit)
        item("Redo", Selector(("redo:")), "z", modifiers: [.command, .shift], in: edit)
        edit.addItem(.separator())
        item("Cut", #selector(NSText.cut(_:)), "x", in: edit)
        item("Copy", #selector(NSText.copy(_:)), "c", in: edit)
        item("Paste", #selector(NSText.paste(_:)), "v", in: edit)
        item("Select All", #selector(NSText.selectAll(_:)), "a", in: edit)
        edit.addItem(.separator())

        let find = menu("Find", in: edit)
        reader("Find…", .find(.showFindInterface), "f", in: find)
        reader("Find and Replace…", .find(.showReplaceInterface), "f", modifiers: [.command, .option], in: find)
        reader("Find Next", .find(.nextMatch), "g", in: find)
        reader("Find Previous", .find(.previousMatch), "g", modifiers: [.command, .shift], in: find)
        reader("Use Selection for Find", .find(.setSearchString), "e", in: find)
        reader("Jump to Selection", .jumpToSelection, "j", in: find)

        let spelling = menu("Spelling and Grammar", in: edit)
        item("Show Spelling and Grammar", #selector(NSText.showGuessPanel(_:)), ":", in: spelling)
        item("Check Document Now", #selector(NSText.checkSpelling(_:)), ";", in: spelling)
        spelling.addItem(.separator())
        item("Check Spelling While Typing", #selector(NSTextView.toggleContinuousSpellChecking(_:)), in: spelling)
        item("Check Grammar With Spelling", #selector(NSTextView.toggleGrammarChecking(_:)), in: spelling)
        item(
            "Correct Spelling Automatically", #selector(NSTextView.toggleAutomaticSpellingCorrection(_:)), in: spelling)

        let substitutions = menu("Substitutions", in: edit)
        item("Show Substitutions", #selector(NSTextView.orderFrontSubstitutionsPanel(_:)), in: substitutions)
        substitutions.addItem(.separator())
        item("Smart Copy/Paste", #selector(NSTextView.toggleSmartInsertDelete(_:)), in: substitutions)
        item("Smart Quotes", #selector(NSTextView.toggleAutomaticQuoteSubstitution(_:)), in: substitutions)
        item("Smart Dashes", #selector(NSTextView.toggleAutomaticDashSubstitution(_:)), in: substitutions)
        item("Smart Links", #selector(NSTextView.toggleAutomaticLinkDetection(_:)), in: substitutions)
        item("Text Replacement", #selector(NSTextView.toggleAutomaticTextReplacement(_:)), in: substitutions)

        let speech = menu("Speech", in: edit)
        item("Start Speaking", #selector(NSTextView.startSpeaking(_:)), in: speech)
        item("Stop Speaking", #selector(NSTextView.stopSpeaking(_:)), in: speech)
        // AppKit also inserts Dictation and Emoji & Symbols in Edit.

        let format = menu("Format")
        reader("Bold", .bold, "b", in: format)
        reader("Italic", .italic, "i", in: format)
        reader("Link", .link, "k", in: format)
        format.addItem(.separator())
        for level in 1...6 {
            reader("Heading \(level)", .heading(level), String(level), modifiers: [.command, .option], in: format)
        }
        format.addItem(.separator())
        reader("Code", .code, in: format)
        reader("Quote", .quote, in: format)

        let view = menu("View")
        reader("Navigator", .navigator, "s", modifiers: [.command, .control], in: view)
        reader("Outline", .outline, "0", modifiers: [.command, .option], in: view)
        reader("Show Source", .source, "/", in: view)
        view.addItem(.separator())
        reader("Actual Size", .actualSize, "0", in: view)
        reader("Zoom In", .zoom(1), "+", in: view)
        reader("Zoom Out", .zoom(-1), "-", in: view)
        view.addItem(.separator())
        item(
            "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f",
            modifiers: [.command, .control], in: view)

        let go = menu("Go")
        reader(
            "Next Heading", .moveHeading(1), String(UnicodeScalar(NSDownArrowFunctionKey)!),
            modifiers: [.command, .option], in: go)
        reader(
            "Previous Heading", .moveHeading(-1), String(UnicodeScalar(NSUpArrowFunctionKey)!),
            modifiers: [.command, .option], in: go)

        let window = menu("Window")
        item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m", in: window)
        item("Zoom", #selector(NSWindow.performZoom(_:)), in: window)
        let tabs = menu("Select Tab", in: window)
        for index in 1...8 {
            reader("Tab \(index)", .selectTab(index - 1), String(index), in: tabs)
        }
        reader("Last Tab", .selectTab(nil), "9", in: tabs)
        window.addItem(.separator())
        item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), in: window)
        NSApp.windowsMenu = window
        NSApp.helpMenu = menu("Help")
        return main
    }
}
