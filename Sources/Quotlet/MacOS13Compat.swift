import Charts
import SwiftUI

extension View {
    @ViewBuilder
    func compatOnChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(macOS 14.0, *) {
            onChange(of: value) { _, newValue in action(newValue) }
        } else {
            onChange(of: value, perform: action)
        }
    }

    @ViewBuilder
    func compatChartXSelection(value: Binding<Date?>) -> some View {
        if #available(macOS 14.0, *) {
            chartXSelection(value: value)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatChartXSelectionWithHover(value: Binding<Date?>) -> some View {
        if #available(macOS 14.0, *) {
            chartXSelection(value: value)
        } else {
            chartOverlay { proxy in
                GeometryReader { geometry in
                    Color.clear.contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                if let plot = proxy.compatPlotRect(in: geometry), plot.contains(location) {
                                    value.wrappedValue = proxy.value(atX: location.x - plot.minX, as: Date.self)
                                } else {
                                    value.wrappedValue = nil
                                }
                            case .ended:
                                value.wrappedValue = nil
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    func compatSymbolReplaceTransition() -> some View {
        if #available(macOS 14.0, *) {
            contentTransition(.symbolEffect(.replace))
        } else {
            self
        }
    }

    @ViewBuilder
    func compatScrollBounceBasedOnSize() -> some View {
        if #available(macOS 13.3, *) {
            scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }
}

extension ChartProxy {
    func compatPlotRect(in geometry: GeometryProxy) -> CGRect? {
        if #available(macOS 14.0, *) {
            guard let anchor = plotFrame else { return nil }
            return geometry[anchor]
        } else {
            return geometry[plotAreaFrame]
        }
    }
}
