import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RepairWidgetsBundle: WidgetBundle {
    var body: some Widget { CureLiveActivity() }
}

struct CureLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CureActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .padding(16)
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.attributes.kind.symbol).font(.title3).foregroundStyle(.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.range, countsDown: true)
                        .font(.title2.monospacedDigit().weight(.medium)).multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.stepTitle).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(timerInterval: context.state.range, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(.accentColor)
                }
            } compactLeading: {
                Image(systemName: context.attributes.kind.symbol).foregroundStyle(.tint)
            } compactTrailing: {
                Text(timerInterval: context.state.range, countsDown: true)
                    .monospacedDigit().frame(maxWidth: 48).multilineTextAlignment(.trailing)
            } minimal: {
                Image(systemName: context.attributes.kind.symbol).foregroundStyle(.tint)
            }
        }
    }
}

struct LockScreenView: View {
    let attributes: CureActivityAttributes
    let state: CureActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(attributes.itemName).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            HStack(alignment: .firstTextBaseline) {
                Text(attributes.stepTitle).font(.system(.headline, design: .serif)).lineLimit(2)
                Spacer(minLength: 12)
                Text(timerInterval: state.range, countsDown: true)
                    .font(.title.monospacedDigit().weight(.medium)).multilineTextAlignment(.trailing)
            }
            ProgressView(timerInterval: state.range, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(.accentColor)
        }
    }
}

#if DEBUG
#Preview("Lock Screen", as: .content, using: CureActivityAttributes(itemName: "Leather sneaker", stepTitle: "Press the sole and wait", kind: .cure)) {
    CureLiveActivity()
} contentStates: {
    CureActivityAttributes.ContentState(startedAt: .now, endsAt: .now.addingTimeInterval(600))
}
#endif
