import AppKit

/// The core cascades declarations before interpreting them. Keeping raw values
/// is important: an invalid later value resets a property to its native default.
struct MermaidStyle {
    private var declarations: [String: String] = [:]

    static func validateFlow(_ source:String,line:Int) throws {
        if source.contains(where:{"()\"'".contains($0)}) {throw MermaidError.syntax(line:line)}
    }
    static func validateState(_ source:String,line:Int) throws {
        if source.contains("\"") || source.contains("'") {throw MermaidError.unsupported(line:line)}
        let re=try NSRegularExpression(pattern:"([A-Za-z-]+)\\s*\\(")
        for match in re.matches(in:source,range:NSRange(source.startIndex...,in:source)) {
            guard let range=Range(match.range(at:1),in:source),["rgb","rgba","hsl","hsla"].contains(source[range].lowercased()) else {throw MermaidError.unsupported(line:line)}
        }
    }

    mutating func apply(_ source: String) {
        // A comma belongs to a dash list or CSS color unless another property
        // name and colon follow it. Unknown properties are deliberately ignored.
        guard let re = try? NSRegularExpression(pattern: "(?:^|,)\\s*([A-Za-z-]+)\\s*:") else { return }
        let matches = re.matches(in:source,range:NSRange(source.startIndex...,in:source))
        let supported: Set<String> = ["fill","stroke","color","stroke-width","stroke-dasharray","font-weight"]
        for (i, match) in matches.enumerated() {
            guard let keyRange = Range(match.range(at:1),in:source) else { continue }
            let key=source[keyRange].lowercased()
            guard supported.contains(key) else { continue }
            let start=match.range.location+match.range.length
            let end=i+1<matches.count ? matches[i+1].range.location : source.utf16.count
            guard let range=Range(NSRange(location:start,length:end-start),in:source) else { continue }
            declarations[key]=source[range].trimmingCharacters(in:.whitespacesAndNewlines)
        }
    }
    mutating func merge(_ other: Self) { declarations.merge(other.declarations) { _,new in new } }
    /// State diagrams merge already-validated style values, unlike flowcharts'
    /// raw CSS cascade. Invalid later values leave an earlier class value intact.
    mutating func applyValidated(_ source: String) {
        var parsed=Self();parsed.apply(source)
        for (key,raw) in parsed.declarations {
            var value=raw
            let valid:Bool
            switch key {
            case "fill","stroke","color":
                if let normalized=Self.stateColor(value) {value=normalized;valid=true} else {valid=false}
            case "stroke-width":valid=Self.width(value) != nil
            case "font-weight":valid=["normal","lighter","bold","bolder"].contains(value.lowercased()) || Int(value) != nil
            case "stroke-dasharray":
                let pieces=value.split(whereSeparator:{$0=="," || $0.isWhitespace}),numbers=pieces.compactMap {Double($0)}
                valid=value.lowercased()=="none" || (!pieces.isEmpty && numbers.count==pieces.count && numbers.allSatisfy({$0.isFinite && $0>=0}))
            default:valid=false
            }
            if valid {declarations[key]=value}
        }
    }
    /// State's CSS tokenizer accepts space-separated color functions. Its
    /// comma-separated forms reach the style compiler as invalid split values.
    private static func stateColor(_ source:String) -> String? {
        if MermaidStyleColor.recognizes(source) {return source}
        let raw=source.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        guard let open=raw.firstIndex(of:"("),raw.hasSuffix(")") else {return nil}
        let name=String(raw[..<open]),body=String(raw[raw.index(after:open)..<raw.index(before:raw.endIndex)])
        guard ["rgb","rgba","hsl","hsla"].contains(name),!body.contains(",") else {return nil}
        let parts=body.replacingOccurrences(of:"/",with:" / ").split(whereSeparator:\.isWhitespace).map(String.init)
        guard parts.count==3 || (parts.count==5 && parts[3]=="/") else {return nil}
        func scalar(_ s:String)->Double? {Double(s.replacingOccurrences(of:"%",with:""))}
        func clamp(_ x:Double,_ maxValue:Double)->Double {min(maxValue,max(0,x))}
        let alpha:Double
        if parts.count==5 {guard let a=scalar(parts[4]),a.isFinite else {return nil};alpha=clamp(a/(parts[4].hasSuffix("%") ? 100:1),1)} else {alpha=1}
        let rgb:[Double]
        if name.hasPrefix("rgb") {
            var values:[Double]=[]
            for part in parts.prefix(3) {guard let value=scalar(part),value.isFinite else {return nil};values.append(clamp(value/(part.hasSuffix("%") ? 100:255),1))};rgb=values
        } else {
            guard parts[1].hasSuffix("%"),parts[2].hasSuffix("%"),let h=Double(parts[0].replacingOccurrences(of:"deg",with:"")),let sat=scalar(parts[1]),let light=scalar(parts[2]),[h,sat,light].allSatisfy(\.isFinite) else {return nil}
            let s=clamp(sat/100,1),l=clamp(light/100,1),a=s*min(l,1-l)
            let hue=(h.truncatingRemainder(dividingBy:360)+360).truncatingRemainder(dividingBy:360)
            rgb=[0.0,8.0,4.0].map { n in let k=(n+hue/30).truncatingRemainder(dividingBy:12);return l-a*max(-1,min(1,min(k-3,9-k))) }
        }
        return "#"+(rgb+[alpha]).map {String(format:"%02x",Int(($0*255).rounded()))}.joined()
    }
    var bold: Bool {
        let value=declarations["font-weight"]?.lowercased() ?? ""
        return value=="bold" || value=="bolder" || (Int(value).map { $0>=600 } ?? false)
    }
    func role(group: Bool = false) -> Int { bold ? (group ? 9:8):(group ? 7:6) }
    private func selection(_ key: String, channel: MermaidStyleColor.Channel) -> MermaidStyleColor.Selection? {
        declarations[key].map { MermaidStyleColor.parse($0,channel:channel) }
    }
    private func resolve(_ selected: MermaidStyleColor.Selection?, dark: Bool, fallback: NSColor?, palette: MermaidPalette) -> NSColor? {
        switch selected {
        case nil,.themeDefault:return fallback
        case .transparent:return nil
        case .tint(let value):return palette.color(tint:value)
        }
    }
    func fill(dark: Bool, fallback: NSColor?, palette: MermaidPalette? = nil) -> NSColor? { resolve(selection("fill",channel:.fill),dark:dark,fallback:fallback,palette:palette ?? MermaidPalette(dark:dark)) }
    func stroke(dark: Bool, fallback: NSColor, palette: MermaidPalette? = nil) -> NSColor? { resolve(selection("stroke",channel:.stroke),dark:dark,fallback:fallback,palette:palette ?? MermaidPalette(dark:dark)) }
    func text(dark: Bool, node: Bool = true, palette: MermaidPalette? = nil) -> NSColor? {
        let palette = palette ?? MermaidPalette(dark:dark)
        if node,case let .tint(tint)=selection("fill",channel:.fill), (tint<=24 && tint%3==0) || tint==26 { return palette.color(tint:27) }
        return resolve(selection("color",channel:.text),dark:dark,fallback:nil,palette:palette)
    }
    private static func width(_ value: String) -> CGFloat? {
        guard let number=Double(value.lowercased().replacingOccurrences(of:"px",with:"").trimmingCharacters(in:.whitespaces)),number.isFinite,number>=0 else { return nil }
        return number
    }
    private var numericWidth: CGFloat? {declarations["stroke-width"].flatMap(Self.width)}
    var nodeWidth: CGFloat {
        if let width=numericWidth { return width<=1 ? 1:width<=2 ? 2:4 }
        if case .tint = selection("fill",channel:.fill) { return 2 }
        return 1
    }
    func edgeWidth(default value: CGFloat) -> CGFloat { numericWidth.map { min(4,max(1,$0.rounded())) } ?? value }
    func dash(default value: [CGFloat] = []) -> [CGFloat] {
        guard let raw=declarations["stroke-dasharray"] else { return value }
        let pieces=raw.split(whereSeparator:{$0=="," || $0.isWhitespace})
        let numbers=pieces.compactMap { Double($0) }
        guard numbers.count==pieces.count,let first=numbers.first,numbers.allSatisfy({$0.isFinite && $0>=0}),numbers.contains(where:{$0>0}) else { return [] }
        return first<=2 ? [2,2]:[5,5]
    }
}
