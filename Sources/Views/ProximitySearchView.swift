import SwiftUI

struct ProximitySearchView: View {
    @Binding var isActive: Bool
    @Binding var term1: String
    @Binding var term2: String
    @Binding var distance: Double
    var onSearch: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "arrow.left.and.right")
                    .foregroundStyle(.orange)
                    .font(.callout)
                Text(L("邻近搜索"))
                    .font(.callout.weight(.medium))
                Spacer()
                Toggle("", isOn: $isActive)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            if isActive {
                HStack(spacing: 8) {
                    TextField(L("词语 1"), text: $term1)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                    Text("↔")
                        .foregroundStyle(.secondary)
                    TextField(L("词语 2"), text: $term2)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                }

                VStack(spacing: 4) {
                    HStack {
                        Text(L("词距"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(LF("%d 词", Int(distance)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $distance, in: 1...50, step: 1)
                        .tint(.orange)
                }

                Button {
                    onSearch()
                } label: {
                    Label(L("搜索"), systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
                .disabled(term1.isEmpty || term2.isEmpty)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.2)))
    }
}
