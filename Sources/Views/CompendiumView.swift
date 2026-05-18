import SwiftUI

struct CompendiumView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "doc.text.image")
                    .foregroundStyle(.blue)
                TextField(L("报告名称"), text: $dataManager.compendium.name)
                    .textFieldStyle(.plain)
                    .font(.headline)
                Spacer()
                Text(LF("%d 条摘录", dataManager.compendium.entries.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(L("导出")) { dataManager.exportCompendiumToFile() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button(L("关闭")) { dismiss() }
                    .controlSize(.small)
            }
            .padding(12)
            .background(.bar)

            Divider()

            if dataManager.compendium.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 32, weight: .thin))
                        .foregroundStyle(.quaternary)
                    Text(L("搜索时点击「添加到报告」收集摘录"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(dataManager.compendium.entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "doc.fill")
                                    .foregroundStyle(.blue)
                                    .font(.caption)
                                Text(entry.fileName)
                                    .font(.callout.weight(.medium))
                                Spacer()
                                Text(entry.addedAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Text(entry.excerpt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                            Text(LF("搜索: %@", entry.query))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                        .contextMenu {
                            Button(L("移除")) { dataManager.removeFromCompendium(id: entry.id) }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
