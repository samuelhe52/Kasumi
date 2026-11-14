import Foundation
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import CoreText

public struct Typography: Codable, Equatable, Sendable {
    public var size: Double = 16
    public var lineSpacing: Double = 1.7
    public var latinFamily = "New York"
    public var hanFamily = "Songti SC"
    public var codeFamily = ""
    public var alignment: ParagraphAlignment = .justified
    public var paragraphIndent = false
    public var hangingPunctuation = true
    public var narrowMeasureRagged = true
    public var narrowMeasureEm: Double = 20
    public var widthLimit: Double = 960
    public var limitWidth = true
    public var dark = false
    public var mermaidEnabled = true
    public var profileValues = BuiltinProfiles.all[0].effective
    public var lightThemeID = "mono-light"
    public var darkThemeID = "mono-dark"
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case size, lineSpacing, latinFamily, hanFamily, codeFamily, alignment, paragraphIndent, hangingPunctuation, narrowMeasureRagged, narrowMeasureEm, widthLimit, limitWidth, dark, mermaidEnabled, profileValues, lightThemeID, darkThemeID
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        size = try values.decodeIfPresent(Double.self, forKey: .size) ?? size
        lineSpacing = try values.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? lineSpacing
        latinFamily = try values.decodeIfPresent(String.self, forKey: .latinFamily) ?? latinFamily
        hanFamily = try values.decodeIfPresent(String.self, forKey: .hanFamily) ?? hanFamily
        codeFamily = try values.decodeIfPresent(String.self, forKey: .codeFamily) ?? codeFamily
        alignment = try values.decodeIfPresent(ParagraphAlignment.self, forKey: .alignment) ?? alignment
        paragraphIndent = try values.decodeIfPresent(Bool.self, forKey: .paragraphIndent) ?? paragraphIndent
        hangingPunctuation = try values.decodeIfPresent(Bool.self, forKey: .hangingPunctuation) ?? hangingPunctuation
        narrowMeasureRagged = try values.decodeIfPresent(Bool.self, forKey: .narrowMeasureRagged) ?? narrowMeasureRagged
        narrowMeasureEm = try values.decodeIfPresent(Double.self, forKey: .narrowMeasureEm) ?? narrowMeasureEm
        widthLimit = try values.decodeIfPresent(Double.self, forKey: .widthLimit) ?? widthLimit
        limitWidth = try values.decodeIfPresent(Bool.self, forKey: .limitWidth) ?? limitWidth
        dark = try values.decodeIfPresent(Bool.self, forKey: .dark) ?? dark
        mermaidEnabled = try values.decodeIfPresent(Bool.self, forKey: .mermaidEnabled) ?? mermaidEnabled
        profileValues = try values.decodeIfPresent(ProfileValues.self, forKey: .profileValues) ?? profileValues
        lightThemeID = try values.decodeIfPresent(String.self, forKey: .lightThemeID) ?? lightThemeID
        darkThemeID = try values.decodeIfPresent(String.self, forKey: .darkThemeID) ?? darkThemeID
    }
    public var documentTheme: DocumentTheme { DocumentThemeCatalog.resolved(id: dark ? darkThemeID : lightThemeID, dark: dark) }
    public var textColor: PlatformColor { documentTheme.color("text")! }
    public var headingColor: PlatformColor { documentTheme.color("heading") ?? textColor }
    public var paperColor: PlatformColor { documentTheme.color("paper")! }
    public var secondaryColor: PlatformColor { documentTheme.color("secondary_text")! }
    public var ruleColor: PlatformColor { documentTheme.color("rule")! }
    public var hanScale: Double { profileValues.resolved(.hanScale).number! }
    public var latinScale: Double { profileValues.resolved(.latinScale).number! }
    public var codeScale: Double { profileValues.resolved(.codeScale).number! }
    public var hanBaseline: Double { profileValues.resolved(.hanBaseline).number! }
    public var headingHanBaseline: Double { profileValues.resolved(.headingHanBaseline).number! }
    public var scriptScale: Double { profileValues.resolved(.scriptScale).number! }
    public func headingSize(_ level: Int) -> Double {
        (size * headingScale(level)).rounded(.toNearestOrAwayFromZero)
    }
    public var mathOptions: MathProfileOptions {
        MathProfileOptions(fontName: profileValues.resolved(.mathFont).string!,
                           radicalGap: profileValues.resolved(.mathRadicalGap).number!,
                           fractionBarOverhang: profileValues.resolved(.mathFracBarOverhang).number!)
    }
    public var printBodySize: Double { profileValues.resolved(.printBodySize).number! }
    public var superscriptShift: Double { profileValues.resolved(.superscriptShift).number! }
    public var paraSpaceBefore: Double { profileValues.resolved(.paraSpaceBefore).number! }
    public var paraSpaceAfter: Double { profileValues.resolved(.paraSpaceAfter).number! }
    public var paraSpaceBetween: Double {
        profileValues[.paraSpaceBetween]?.number ?? (paragraphIndent ? 0 : paraSpaceAfter)
    }
    public var firstLineIndent: Double { profileValues[.firstLineIndent]?.number ?? (paragraphIndent ? 2 : 0) }
    public var indentFirstParagraph: Bool { profileValues[.paraSeparation]?.string == "indent" || (profileValues[.paraSeparation] == nil && paragraphIndent) }
    public var headingSpaceBefore: Double { profileValues.resolved(.headingSpaceBefore).number! }
    public var headingSpaceAfter: Double { profileValues.resolved(.headingSpaceAfter).number! }
    public func headingScale(_ level: Int) -> Double {
        if case .numbers(let values) = profileValues.resolved(.headingScale), values.count == 6 {
            return min(4, max(0.5, values[min(5,max(0,level-1))]))
        }
        return [1.6,1.5,1.4,1.3,1.2,1.1][min(5,max(0,level-1))]
    }
    public func headingWeight(_ level: Int) -> PlatformFont.Weight {
        guard case .strings(let weights)=profileValues.resolved(.headingWeight), weights.count==6,
              weights.allSatisfy({["regular","medium","semibold","bold"].contains($0)}) else { return .semibold }
        switch weights[min(5,max(0,level-1))] {case "regular":return .regular;case "medium":return .medium;case "bold":return .bold;default:return .semibold}
    }
    public func applying(_ values: ProfileValues) -> Typography {
        var result=self; result.profileValues=values
        result.size=values.resolved(.baseSize).number!
        let latin=values[.latinFamily]?.string ?? ""
        let han=values[.hanFamily]?.string ?? ""
        result.latinFamily=latin.isEmpty ? "New York" : latin
        result.hanFamily=han.isEmpty ? "Songti SC" : han
        result.codeFamily=values[.codeFamily]?.string ?? ""
        result.lineSpacing=values.resolved(.lineSpacing).number!
        result.paragraphIndent=values.resolved(.paraSeparation).string == "indent"
        result.hangingPunctuation=values.resolved(.hangingPunctuation).flag!
        result.narrowMeasureRagged=values.resolved(.autoRaggedNarrow).flag!
        result.narrowMeasureEm=values.resolved(.autoRaggedMeasureEm).number!
        switch values.resolved(.bodyAlign).string {case "left":result.alignment = .leading;case "center":result.alignment = .centered;default:result.alignment = .justified}
        return result
    }

    public func font(size: Double? = nil, strong: Bool = false, emphasis: Bool = false, code: Bool = false, cjk: Bool = false, weight: PlatformFont.Weight? = nil, heading: Bool = false) -> PlatformFont {
        _ = try? DocumentFonts.registerBundledFonts()
        let requestedSize = (size ?? self.size) * (code ? codeScale : cjk ? hanScale : latinScale)
        // Code font sizes round to nearest, ties away from zero, after scaling.
        let pointSize = code ? requestedSize.rounded(.toNearestOrAwayFromZero) : requestedSize
        let desiredWeight = weight ?? (strong ? PlatformFont.Weight.bold : .regular)
        if cjk,let face=CJKFontFace.resolve(family:hanFamily,strong:strong,emphasis:emphasis,heading:heading,
            italic:profileValues.resolved(.cjkItalicFace).string!,heavy:profileValues.resolved(.cjkStrongFace).string!),
            let font=PlatformFonts.named(face.name,size:pointSize) { return font }
        let base: PlatformFont
        if code { base = PlatformFonts.named( codeFamily, size: pointSize) ?? .monospacedSystemFont(ofSize: pointSize, weight: .regular) }
        else if cjk { base = PlatformFonts.named( hanFamily, size: pointSize) ?? .systemFont(ofSize: pointSize) }
        else if latinFamily == "New York" {
            let descriptor = PlatformFont.systemFont(ofSize: pointSize, weight: desiredWeight).fontDescriptor.withDesign(.serif) ?? PlatformFont.systemFont(ofSize: pointSize, weight: desiredWeight).fontDescriptor
            #if canImport(AppKit)
            base = PlatformFont(descriptor: descriptor, size: pointSize) ?? .systemFont(ofSize: pointSize)
            #else
            base = PlatformFont(descriptor: descriptor, size: pointSize)
            #endif
        } else if ["SF Pro", "SF Pro Text"].contains(latinFamily) { base = .systemFont(ofSize: pointSize, weight: desiredWeight) }
        else {
            // Custom families select regular below bold; traits choose real
            // bold/italic faces through Core Text rather than a font manager.
            let regular = PlatformFonts.named(latinFamily, size: pointSize) ?? .systemFont(ofSize: pointSize)
            base = desiredWeight >= .bold ? PlatformFonts.applying(.traitBold, to: regular) : regular
        }
        var traits: CTFontSymbolicTraits = []
        if strong { traits.insert(.traitBold) }
        if emphasis && !cjk { traits.insert(.traitItalic) }
        return PlatformFonts.applying(traits, to: base)
    }

    public func attributed(_ runs: [InlineRun], size: Double? = nil, heading: Bool = false, code: Bool = false, headingLevel: Int? = nil, baseURL: URL? = nil, imageMaxWidth: CGFloat = 960) -> NSAttributedString {
        let output = NSMutableAttributedString(string: "")
        func append(_ text: NSAttributedString, base: PlatformFont, han: PlatformFont? = nil, punctuation: PlatformFont? = nil, run: InlineRun, isCode: Bool) {
            let piece = NSMutableAttributedString(attributedString: text)
            let metadata = ParagraphRunStyle(baseFont: base, hanFont: han, punctuationFont: punctuation,
                                             flags: run.paragraphFlags | (isCode ? 4 : 0), isCode: isCode)
            piece.addAttribute(.kasumiParagraphRun, value: metadata, range: NSRange(location: 0, length: piece.length))
            output.append(piece)
        }
        let pointSize = size ?? self.size
        let theme=documentTheme
        let foreground=heading ? (theme.color("heading") ?? textColor) : theme.color("text")!
        for run in runs {
            let isCode = code || run.traits.contains(.code)
            let isFootnote = run.traits.contains(.footnote)
            // Native footnote references have source flag0x10, within the
            // context builder's rounded script mask0x610.
            let runSize = (isFootnote ? (pointSize * scriptScale).rounded(.toNearestOrAwayFromZero) : pointSize) * (isCode && !code ? 0.88 : 1)
            let isStrong = (heading && headingLevel == nil) || run.traits.contains(.strong)
            let base = font(size: runSize, strong: isStrong, emphasis: run.traits.contains(.emphasis) || run.traits.contains(.math), code: isCode, weight: headingLevel.map(headingWeight))
            if run.traits.contains(.image), !isCode {
                if let source = run.imageSource, let image = DocumentImageStore.shared.image(for: source, baseURL: baseURL) {
                    append(ImageAttachment(image: image, maximumWidth: imageMaxWidth, altText: run.text).attributed(link: run.destination), base: base, run: run, isCode: isCode)
                } else {
                    var attributes: [NSAttributedString.Key: Any] = [
                        .font: font(size: pointSize), .foregroundColor: secondaryColor,
                        .kasumiSemanticText: run.text
                    ]
                    if let destination = run.destination { attributes[.link] = destination }
                    append(NSAttributedString(string: run.text.isEmpty ? "Image unavailable" : "Image unavailable: \(run.text)", attributes: attributes), base: base, run: run, isCode: isCode)
                }
                continue
            }
            if run.traits.contains(.math), !isCode {
                let attachment = MathAttachment(source: run.text, size: pointSize, display: false, options: mathOptions)
                let piece = NSMutableAttributedString(attributedString: attachment.attributed(color: foreground, fallbackFont: font(size: pointSize * 0.88, code: true)))
                if let destination = run.destination { piece.addAttribute(.link, value: destination, range: NSRange(location: 0, length: piece.length)) }
                append(piece, base: base, run: run, isCode: isCode)
                continue
            }
            var attributes: [NSAttributedString.Key: Any] = [
                .font: base, .foregroundColor: run.traits.contains(.link) ? (theme.color("link") ?? foreground) : isCode ? (theme.color("inline_code") ?? foreground) : foreground
            ]
            if run.traits.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if run.traits.contains(.highlight) { attributes[.backgroundColor] = theme.color("mark_background") ?? DocumentColor(red: 1, green: 0.8, blue: 0, alpha: 0.45).nsColor }
            if let destination = run.destination { attributes[.link] = destination }
            if isFootnote { attributes[.baselineOffset] = pointSize * superscriptShift }
            let displayed = run.footnoteDisplay ?? run.text
            let piece = NSMutableAttributedString(string: displayed, attributes: attributes)
            var selectedHan: PlatformFont?, selectedPunctuation: PlatformFont?
            if !isCode {
                var offset = 0
                var resolvedHan: (font: PlatformFont, trim: Double)?
                for character in displayed {
                    let length = String(character).utf16.count
                    if CJKFontRole.usesHanFont(character) {
                        if resolvedHan == nil {
                            let hanFont = font(size: runSize, strong: isStrong || heading, emphasis: run.traits.contains(.emphasis), cjk: true, heading: heading)
                            let face = CJKFontFace.resolve(family:hanFamily,strong:isStrong || heading,emphasis:run.traits.contains(.emphasis),heading:heading,italic:profileValues.resolved(.cjkItalicFace).string!,heavy:profileValues.resolved(.cjkStrongFace).string!)
                            resolvedHan = (hanFont, face?.name == hanFont.fontName ? face!.baselineDelta : 0)
                        }
                        let han = resolvedHan!
                        let punctuation = CJKFontRole.punctuationFont(for: character, family: hanFamily, hanFont: han.font, enabled: profileValues.resolved(.cjkPunctFace).string == "simsong")
                        selectedHan = han.font
                        if let punctuation { selectedPunctuation = punctuation }
                        let trim = punctuation == nil ? han.trim : -0.055
                        piece.addAttributes([.font: punctuation ?? han.font, .baselineOffset: base.pointSize * ((heading ? headingHanBaseline : hanBaseline) + trim)], range: NSRange(location: offset, length: length))
                    }
                    offset += length
                }
            }
            if isCode && !code && profileValues.resolved(.codeCapsule).flag! {
                let capsule = InlineCodeCapsule(color: theme.color("code_capsule_background")!, font: base, padding: profileValues.resolved(.codeCapsulePad).number!)
                append(capsule.attributed(piece), base: base, han: selectedHan, punctuation: selectedPunctuation, run: run, isCode: isCode)
            } else { append(piece, base: base, han: selectedHan, punctuation: selectedPunctuation, run: run, isCode: isCode) }
        }
        return output
    }
}

public struct ParagraphLayout {
    public let attributed: NSAttributedString
    public let lines: [ShapedLine]
    public let height: CGFloat
    public var autoRagged = false
    public var diagnostics: [String] = []
}

public enum ParagraphTypesetter {
    public static func layout(_ attributed: NSAttributedString, width: CGFloat, fontSize: CGFloat, lineSpacing: CGFloat = 1.7, alignment: ParagraphAlignment = .justified, indent: CGFloat = 0, verbatim: Bool = false, profileValues: ProfileValues? = nil, outerWidth: CGFloat? = nil, baseEm: CGFloat? = nil) -> ParagraphLayout {
        guard attributed.length > 0, width > 0 else { return ParagraphLayout(attributed: attributed, lines: [], height: 0) }
        // RTL text keeps Core Text's visual ordering; the paragraph engine does
        // not implement bidi painting yet.
        let hasRTL = attributed.string.unicodeScalars.contains { (0x0590...0x08ff).contains($0.value) || (0xfb1d...0xfdff).contains($0.value) || (0xfe70...0xfefc).contains($0.value) }
        if !verbatim && !hasRTL {
            return MeasuredParagraphTypesetter.layout(attributed, width: width, fontSize: fontSize, lineSpacing: lineSpacing,
                                                       alignment: alignment, indent: indent, profileValues: profileValues, outerWidth: outerWidth, baseEm: baseEm)
        }
        var legacyAlignment = alignment, legacyAutoRagged = false
        if !verbatim && alignment == .justified {
            let options = profileValues.map(ParagraphProfileOptions.init(values:)) ?? .init()
            let input = ParagraphShaper.shape(attributed, fallbackSize: fontSize)
            let total = input.clusters.reduce(Float(0)) { $0 + $1.advance }
            let code = input.clusters.reduce(Float(0)) { $0 + (input.metrics[$1.run].isCode ? $1.advance : 0) }
            let codeRagged = options.raggedCodeFraction > 0 && total > 0 && code / total >= options.raggedCodeFraction
            legacyAutoRagged = !codeRagged && options.autoRaggedNarrow && Float(outerWidth ?? width) < Float(baseEm ?? fontSize) * options.autoRaggedMeasureEm
            if codeRagged || legacyAutoRagged { legacyAlignment = .leading }
        }
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        func measure(_ range: NSRange) -> Double {
            guard range.length > 0 else { return 0 }
            return CTLineGetTypographicBounds(CTTypesetterCreateLine(typesetter, CFRange(location: range.location, length: range.length)), nil, nil, nil)
        }
        let ranges: [NSRange]
        if verbatim {
            let ns = attributed.string as NSString
            var rows: [NSRange] = [], start = 0
            while start < ns.length {
                let line = ns.lineRange(for: NSRange(location: start, length: 0))
                var end = NSMaxRange(line)
                while end > start && (ns.character(at: end - 1) == 10 || ns.character(at: end - 1) == 13) { end -= 1 }
                var cursor = start
                if cursor == end { rows.append(NSRange(location: start, length: 0)) }
                while cursor < end {
                    let suggested = CTTypesetterSuggestLineBreak(typesetter, cursor, Double(width))
                    let count = min(end - cursor, suggested > 0 ? suggested : ns.rangeOfComposedCharacterSequence(at: cursor).length)
                    rows.append(NSRange(location: cursor, length: count)); cursor += count
                }
                start = NSMaxRange(line)
            }
            ranges = rows
        } else {
            ranges = ParagraphBreaker.ranges(in: attributed.string, width: Double(width), fontSize: Double(fontSize), alignment: legacyAlignment, firstLineIndent: Double(indent), measure: measure)
        }
        var lines: [ShapedLine] = [], y: CGFloat = 0
        for (index, range) in ranges.enumerated() {
            var line = range.length == 0
                ? CTLineCreateWithAttributedString(NSAttributedString(string: ""))
                : CTTypesetterCreateLine(typesetter, CFRange(location: range.location, length: range.length))
            let leadingInset = index == 0 ? indent : 0
            let available = width - leadingInset
            let nextOffset = index + 1 < ranges.count ? ranges[index + 1].location : attributed.length
            let gap = (attributed.string as NSString).substring(with: NSRange(location: NSMaxRange(range), length: max(0, nextOffset - NSMaxRange(range))))
            if legacyAlignment == .justified, index < ranges.count - 1, !gap.contains("\n"),
               let justified = CTLineCreateJustifiedLine(line, 1, Double(available)) { line = justified }
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let used = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            let baseline = y + max(ascent, fontSize)
            let offset: CGFloat = legacyAlignment == .centered ? max(0, (available - used) / 2) : legacyAlignment == .trailing ? max(0, available - used) : 0
            lines.append(ShapedLine(range: range, line: line, origin: CGPoint(x: leadingInset + offset, y: baseline), ascent: ascent, descent: descent, width: used))
            y = max(y + fontSize * lineSpacing, baseline + descent + leading)
        }
        return ParagraphLayout(attributed: attributed, lines: lines, height: y, autoRagged: legacyAutoRagged, diagnostics: hasRTL && !verbatim ? ["nativeBidiPaintingUnverified"] : [])
    }
}
