import SwiftUI
import TalkToMyMacCore

/// Editable per-million-token prices for one remote model, used for the cost estimates on
/// the Instrumentation tab.
@available(macOS 26.0, *)
struct PriceEditor: View {
    let model: FormattingModel
    @Bindable var settings: FormattingSettings

    var body: some View {
        if let price = settings.price(for: model) {
            priceField("Input price", value: price.inputPerMillion) { $0.inputPerMillion = $1 }
            priceField("Cached input price", value: price.cachedInputPerMillion) { $0.cachedInputPerMillion = $1 }
            priceField("Output price", value: price.outputPerMillion) { $0.outputPerMillion = $1 }
            if let listPrice = settings.listPrice(for: model), price != listPrice {
                Button("Reset to List Price") { settings.resetPrice(for: model) }
            }
        }
    }

    private func priceField(_ label: String, value: Double,
                            update: @escaping (inout TokenPrice, Double) -> Void) -> some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField(label, value: Binding(
                    get: { value },
                    set: { newValue in
                        guard var price = settings.price(for: model), newValue >= 0 else { return }
                        update(&price, newValue)
                        settings.setPrice(price, for: model)
                    }
                ), format: .currency(code: "USD").precision(.fractionLength(2...4)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                Text("per 1M tokens")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
