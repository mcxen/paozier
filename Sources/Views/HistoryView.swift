import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    var onSelect: (String) -> Void

    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $tab) {
                    Text(L("历史")).tag(0)
                    Text(L("书签")).tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                Spacer()
                if tab == 0 {
                    Button(L("清空历史")) { dataManager.clearHistory() }
                        .controlSize(.small)
                }
                Button(L("关闭")) { dismiss() }
                    .controlSize(.small)
            }
            .padding(12)
            .background(.bar)

            Divider()

            if tab == 0 {
                List(dataManager.history) { item in
                    Button {
                        onSelect(item.query)
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.query)
                                    .font(.callout)
                                HStack {
                                    Text(historyMetaText(item))
                                    Text(item.date, style: .relative)
                                }
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            } else {
                List(dataManager.bookmarks) { bm in
                    HStack {
                        Button {
                            onSelect(bm.query)
                        } label: {
                            HStack {
                                Image(systemName: "bookmark.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bm.name).font(.callout)
                                    Text(bm.query).font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button { dataManager.removeBookmark(id: bm.id) } label: {
                            Image(systemName: "trash").font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    private func historyMetaText(_ item: SearchHistoryItem) -> String {
        let countText = LF("%d 结果", item.resultCount)
        guard let duration = item.duration else { return countText }
        if duration < 1 {
            return "\(countText) · \(String(format: "%.0fms", max(duration, 0) * 1000))"
        }
        if duration < 10 {
            return "\(countText) · \(String(format: "%.1fs", duration))"
        }
        return "\(countText) · \(String(format: "%.0fs", duration))"
    }
}
