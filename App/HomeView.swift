import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \Reading.lastRead, order: .reverse) private var recent: [Reading]
    @Environment(\.horizontalSizeClass) private var width
    let onSample: () -> Void
    let onPaste: () -> Void
    let onCompose: () -> Void
    let onSelect: (Reading) -> Void
    let onHistory: () -> Void
    let onAbout: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .lastTextBaseline) {
                            deskTitle.fixedSize()
                            Spacer(minLength: 12)
                            today.fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            deskTitle
                            today
                        }
                    }
                    Rectangle().fill(Ink.green).frame(height: 1)
                }
                FeaturePlate(action: onSample)
                VStack(alignment: .leading, spacing: 12) {
                    SectionLine(title: "开始精读", detail: "英语  →  简体中文")
                    VStack(spacing: 0) {
                        actionRow("粘贴英文", "从剪贴板直接开始阅读", "document.on.clipboard", onPaste)
                        Divider().padding(.leading, 67)
                        actionRow("输入原文", "输入或编辑一段英文", "square.and.pencil", onCompose)
                    }.paperCard()
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionLine(title: "最近阅读")
                        if !recent.isEmpty {
                            Button("全部", action: onHistory).font(.subheadline).fixedSize()
                        }
                    }
                    if recent.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath").foregroundStyle(Ink.muted)
                            Text("读过的文章会保存在这里。").font(.subheadline).foregroundStyle(Ink.muted)
                        }.padding(.vertical, 10)
                    } else {
                        ForEach(recent.prefix(3)) { item in
                            Button { onSelect(item) } label: { PassageRow(item: item) }.buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
            .padding(.horizontal, width == .regular ? 34 : 21).padding(.top, 12).padding(.bottom, 32)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.paper).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Brand() }.sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onAbout) { Image(systemName: "info.circle") }.accessibilityLabel("关于与数据来源")
            }
        }
    }
    private var deskTitle: some View {
        Text("阅读书桌")
            .font(.system(.largeTitle, design: .serif, weight: .bold)).foregroundStyle(Ink.text)
            .accessibilityAddTraits(.isHeader)
    }
    private var today: some View {
        Text(Date.now.formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier: "zh_CN"))))
            .font(.caption).foregroundStyle(Ink.muted)
    }
    private func actionRow(_ title: String, _ subtitle: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol).font(.system(size: 19, weight: .medium)).frame(width: 41, height: 41)
                    .foregroundStyle(Ink.green).background(Ink.pale, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(Ink.text)
                    Text(subtitle).font(.caption).foregroundStyle(Ink.muted)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.subheadline).foregroundStyle(Ink.green)
            }.padding(.horizontal, 15).padding(.vertical, 12).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(title)
    }
}

private struct FeaturePlate: View {
    @Environment(\.horizontalSizeClass) private var size
    @Environment(\.dynamicTypeSize) private var type
    let action: () -> Void
    let cream = Color(red: 0.97, green: 0.94, blue: 0.83)
    let forest = Color(red: 0.11, green: 0.24, blue: 0.16)
    var body: some View {
        Button(action: action) { plate }
            .buttonStyle(.plain)
            .accessibilityLabel("精读选段，达尔文，物种起源")
            .accessibilityIdentifier("featuredReading")
    }
    private var plate: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "leaf").font(.caption)
                Text("经典选读").font(.caption.weight(.semibold))
            }
            Spacer(minLength: 18)
            Text("On the Origin").font(.custom("Baskerville", size: size == .regular ? 51 : 36, relativeTo: .title))
            Text("of Species").font(.custom("Baskerville-Italic", size: size == .regular ? 51 : 36, relativeTo: .title))
            Text("达尔文《物种起源》 · 1859").font(.caption.weight(.medium)).padding(.top, 8)
            Spacer(minLength: 20)
            HStack(spacing: 8) { Text("精读选段"); Image(systemName: "arrow.right") }
                .font(.caption.weight(.bold)).padding(.horizontal, 13).padding(.vertical, 8)
                .foregroundStyle(.white).background(forest, in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(size == .regular ? 26 : 19)
        .frame(minHeight: size == .regular ? 268 : 227, alignment: .leading)
        .foregroundStyle(forest)
        .background {
            GeometryReader { geo in
                ZStack(alignment: .trailing) {
                    cream
                    Image("Fern").resizable().scaledToFill()
                        .frame(width: geo.size.width * 0.53, height: geo.size.height, alignment: .center)
                        .clipped().blendMode(.multiply)
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.14), .init(color: .black, location: 0.55)], startPoint: .leading, endPoint: .trailing))
                        .opacity(type.isAccessibilitySize ? 0.18 : 0.94)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay { RoundedRectangle(cornerRadius: 17).strokeBorder(forest.opacity(0.15), lineWidth: 0.8) }

    }
}
