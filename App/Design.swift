import SwiftUI
import UIKit

enum Ink {
    static func tone(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((rgb >> 16) & 255)/255, green: CGFloat((rgb >> 8) & 255)/255,
                           blue: CGFloat(rgb & 255)/255, alpha: 1)
        })
    }
    static let paper = tone(0xF8F7F1, 0x151A17)
    static let card = tone(0xFFFEFA, 0x202722)
    static let text = tone(0x152B24, 0xF1F3E7)
    static let green = tone(0x275744, 0xA6D4B4)
    static let muted = tone(0x5C695E, 0xAFBCAD)
    static let rule = tone(0xD7DBCF, 0x37453C)
    static let pale = tone(0xE4EBDE, 0x2B3A30)
    static let highlight = tone(0xDFEAC4, 0x394F37)
    static let amber = tone(0x805B25, 0xE2C493)
}
struct Brand: View {
    var body: some View {
        HStack(spacing: 9) {
            Text("L").font(.custom("Baskerville-Italic", fixedSize: 22)).foregroundStyle(Color.white)
                .frame(width: 30, height: 30).background(Color(red: 0.13, green: 0.28, blue: 0.22), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            Text("Lexora").font(.custom("Baskerville-SemiBold", size: 27)).foregroundStyle(Ink.text).fixedSize()
        }.fixedSize()
    }
}
struct SectionLine: View {
    let title: String
    var detail: String = ""
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                heading.fixedSize()
                Spacer(minLength: 0)
                if !detail.isEmpty { caption.fixedSize() }
            }
            VStack(alignment: .leading, spacing: 4) {
                heading
                if !detail.isEmpty { caption }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var heading: some View { Text(title).font(.headline).foregroundStyle(Ink.text) }
    private var caption: some View { Text(detail).font(.caption).foregroundStyle(Ink.muted) }
}
extension View {
    func paperCard(_ radius: CGFloat = 17) -> some View {
        background(Ink.card, in: RoundedRectangle(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(Ink.rule, lineWidth: 0.7) }
    }
}

struct PassageRow: View {
    @Environment(\.dynamicTypeSize) private var type
    let item: Reading
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: item.text == Featured.text ? "leaf" : "doc.text")
                .foregroundStyle(Ink.green).frame(width: 40, height: 46).background(Ink.pale, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.body.weight(.medium)).foregroundStyle(Ink.text)
                    .lineLimit(type.isAccessibilitySize ? nil : 2)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) {
                        Text(item.origin)
                        Text("·").accessibilityHidden(true)
                        date
                    }.fixedSize()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.origin)
                        date
                    }
                }.font(.caption).foregroundStyle(Ink.muted)
            }
            .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Ink.muted)
        }.contentShape(Rectangle())
    }
    private var date: Text { Text(item.lastRead.formatted(date: .abbreviated, time: .omitted)) }
}
