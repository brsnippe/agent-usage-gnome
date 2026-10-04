import AgentUsageCore
import AppKit
import SwiftUI

/// Everything the panel shows. The app fills it from the records; the
/// snapshots fill it from samples.
struct PanelState {
    var providers: [AgentRecord] = []
    var selectedID = ""
    /// The row under the pointer, and the details it puts in the footer.
    var hoveredRow: String?
    var hoverText: String?
    var running: UpdateRequest?
    var newRelease: String?
    /// The open button's tooltip; nil hides the button.
    var launchHint: String?
    /// The open button opens a desktop app rather than a terminal.
    var launchOpensApp = false
    /// Something that just went wrong, like a terminal that isn't installed.
    var notice: String?
    var pythonMissing = false
    var now = Date()

    var selected: AgentRecord? { providers.first { $0.id == selectedID } }
}

struct PanelActions {
    var refresh: () -> Void = {}
    var openAgent: () -> Void = {}
    var openSettings: () -> Void = {}
    var select: (String) -> Void = { _ in }
    var footer: () -> Void = {}
    /// A problem card's sign-in button, for the agent with this id.
    var signIn: (String, SignInAction) -> Void = { _, _ in }
    var signInHint: (SignInAction) -> String = { "Runs \($0.command.joined(separator: " "))" }
}

final class PanelModel: ObservableObject {
    @Published var state = PanelState()
    /// The visible height when the panel scrolls, or nil to show all of it.
    @Published var viewport: CGFloat?
    var actions = PanelActions()

    func hover(_ row: String, text: String?, inside: Bool) {
        if inside {
            state.hoveredRow = row
            state.hoverText = text
        } else if state.hoveredRow == row {
            state.hoveredRow = nil
            state.hoverText = nil
        }
    }
}

/// The panel in its window: the content, scrolling once it's taller than the
/// screen allows, inside Omarchy's square border.
struct PanelWindowView: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        Group {
            if let viewport = model.viewport {
                ScrollView(.vertical) {
                    PanelContent(model: model)
                }
                .frame(height: viewport)
            } else {
                PanelContent(model: model)
            }
        }
        .frame(width: Theme.panelWidth)
        .background(Theme.background)
        .overlay(Rectangle().strokeBorder(Theme.foreground, lineWidth: 1))
    }
}

struct PanelContent: View {
    @ObservedObject var model: PanelModel

    private var state: PanelState { model.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let record = state.selected {
                Hero(record: record, model: model)
                if state.providers.count > 1 {
                    Tabs(model: model)
                }
                notices
                if let problem = record.problem {
                    RecordProblem(record: record, problem: problem, model: model)
                }
                sections(record)
                Footer(model: model, record: record)
            } else {
                notices
                Text(Panel.emptyText)
                    .foregroundColor(Theme.dim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
        }
        .padding(Theme.padding)
        .frame(width: Theme.panelWidth, alignment: .leading)
        .font(Theme.font(10))
        .foregroundColor(Theme.foreground)
    }

    @ViewBuilder private var notices: some View {
        if let notice = state.notice {
            ProblemCard(text: notice)
        }
        if state.pythonMissing {
            ProblemCard(text: Panel.noPythonText)
        }
    }

    @ViewBuilder private func sections(_ record: AgentRecord) -> some View {
        let balance = record.balance
        let limits = record.limitWindows
        if balance != nil || !limits.isEmpty {
            Separator()
        }
        if let balance {
            BalanceSection(balance: balance)
        }
        if !limits.isEmpty {
            LimitsSection(record: record, limits: limits, model: model)
        }
        let days = record.recentDays
        if !days.isEmpty {
            Separator()
            DaysSection(record: record, days: days, model: model)
        }
        let today = record.todayModelRows
        if !today.isEmpty {
            Separator()
            ModelsSection(title: "TODAY BY MODEL", key: "today", rows: today.map { (name: $0.name, total: $0.total, detail: $0.detail) }, model: model)
        }
        let models = record.modelRows
        if !models.isEmpty {
            Separator()
            ModelsSection(title: "ALL TIME BY MODEL", key: "all", rows: models.map { (name: $0.name, total: $0.total, detail: $0.detail) }, model: model)
        }
    }
}

// --------------------------------------------------------------- pieces

struct Separator: View {
    var body: some View {
        Rectangle().fill(Theme.foreground.opacity(0.15)).frame(height: 1)
    }
}

/// A track with a fill: the limit meters, the day bars, and the share bar
/// behind each model row. `pill` rounds the ends; the model rows stay square.
struct Bar: View {
    var value: Double
    var color = Theme.foreground
    var fillAlpha = 1.0
    var trackAlpha = 0.14
    var pill = true

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                shape.fill(Theme.foreground.opacity(trackAlpha))
                if value > 0 {
                    shape.fill(color.opacity(fillAlpha)).frame(width: geometry.size.width * Usage.clamp(value))
                }
            }
        }
    }

    private var shape: AnyShape {
        pill ? AnyShape(Capsule()) : AnyShape(Rectangle())
    }
}

/// What's wrong and what to do about it, with buttons when there's a fix to
/// run.
struct ProblemCard<Buttons: View>: View {
    var text: String
    @ViewBuilder var buttons: Buttons

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(Theme.font(8.5))
                .foregroundColor(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            buttons
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Theme.urgent.opacity(0.10))
        .overlay(Rectangle().strokeBorder(Theme.urgent.opacity(0.35), lineWidth: 1))
    }
}

extension ProblemCard where Buttons == EmptyView {
    init(text: String) {
        self.init(text: text) { EmptyView() }
    }
}

/// An agent's problem card, with its sign-in buttons when that's the fix.
struct RecordProblem: View {
    var record: AgentRecord
    var problem: String
    @ObservedObject var model: PanelModel

    var body: some View {
        let actions = record.signInActions
        if actions.isEmpty {
            ProblemCard(text: problem)
        } else {
            ProblemCard(text: problem) {
                HStack(spacing: 8) {
                    ForEach(actions, id: \.label) { action in
                        CardButton(label: action.label, hint: model.actions.signInHint(action), model: model) {
                            model.actions.signIn(record.id, action)
                        }
                    }
                }
            }
        }
    }
}

/// A button on a card, framed like the tabs.
struct CardButton: View {
    var label: String
    var hint: String
    @ObservedObject var model: PanelModel
    var action: () -> Void

    private var hovered: Bool { model.state.hoveredRow == "card-\(label)" }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.font(8.5))
                .lineLimit(1)
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .foregroundColor(Theme.foreground)
                .background(hovered ? Theme.foreground.opacity(0.08) : Color.clear)
                .overlay(Rectangle().strokeBorder(Theme.foreground.opacity(hovered ? 1 : 0.35), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(hint)
        .onHover { model.hover("card-\(label)", text: hint, inside: $0) }
    }
}

struct PanelSection<Content: View>: View {
    var title: String
    var stale = false
    var hint: String?
    @ObservedObject var model: PanelModel
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.font(8, bold: true))
                .tracking(1)
                .foregroundColor(stale ? Theme.stale : Theme.dim)
                .onHover { inside in
                    if let hint {
                        model.hover("title-\(title)", text: hint, inside: inside)
                    }
                }
            content
        }
    }
}

struct Hero: View {
    var record: AgentRecord
    @ObservedObject var model: PanelModel

    var body: some View {
        HStack(spacing: 12) {
            let logo = Assets.logo(record.id)
            Image(nsImage: logo.image)
                .renderingMode(logo.template ? .template : .original)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(Theme.foreground)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name).font(Theme.font(12))
                Text(record.heroMeta.uppercased())
                    .font(Theme.font(8, bold: true))
                    .tracking(1.5)
                    .foregroundColor(Theme.dim)
            }
            Spacer(minLength: 0)
            ActionButton(symbol: "arrow.clockwise", hint: "Refresh now (r)", model: model, action: model.actions.refresh)
            if let hint = model.state.launchHint {
                ActionButton(symbol: model.state.launchOpensApp ? "macwindow" : "terminal", hint: hint, model: model, action: model.actions.openAgent)
            }
            ActionButton(symbol: "gearshape", hint: "Settings", model: model, action: model.actions.openSettings)
        }
    }
}

struct ActionButton: View {
    var symbol: String
    var hint: String
    @ObservedObject var model: PanelModel
    var action: () -> Void

    private var hovered: Bool { model.state.hoveredRow == "action-\(symbol)" }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundColor(hovered ? Theme.foreground : Theme.dim)
                .background(hovered ? Theme.foreground.opacity(0.08) : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(hint)
        .onHover { model.hover("action-\(symbol)", text: hint, inside: $0) }
    }
}

struct Tabs: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(model.state.providers, id: \.id) { record in
                let checked = record.id == model.state.selectedID
                let hovered = model.state.hoveredRow == "tab-\(record.id)"
                Button {
                    model.actions.select(record.id)
                } label: {
                    Text(record.name)
                        .font(Theme.font(9))
                        .lineLimit(1)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(checked || hovered ? Theme.foreground : Theme.dim)
                        .background(checked ? Theme.foreground.opacity(0.14) : Color.clear)
                        .overlay(Rectangle().strokeBorder(
                            checked ? Theme.foreground : Theme.foreground.opacity(hovered ? 0.7 : 0.35), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { model.hover("tab-\(record.id)", text: nil, inside: $0) }
            }
        }
    }
}

struct ValueRow: View {
    var title: String
    var value: String
    var alarming: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            Text(value)
                .font(Theme.font(8.5))
                .foregroundColor(alarming ? Theme.urgent : Theme.foreground)
        }
    }
}

struct BalanceSection: View {
    var balance: Balance

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BALANCE").font(Theme.font(8, bold: true)).tracking(1).foregroundColor(Theme.dim)
            ValueRow(title: "Prepaid credits", value: Usage.formatMoney(balance.remaining, currency: balance.currency), alarming: balance.alarming)
            // The meter shows what is left: a prepaid account drains toward empty.
            if balance.funded > 0 {
                Bar(value: balance.remaining / balance.funded, color: balance.alarming ? Theme.urgent : Theme.foreground).frame(height: 5)
            }
            if !balance.detail.isEmpty {
                Text(balance.detail).font(Theme.font(8.5)).foregroundColor(Theme.dim)
            }
        }
    }
}

struct LimitsSection: View {
    var record: AgentRecord
    var limits: [LimitWindow]
    @ObservedObject var model: PanelModel

    var body: some View {
        let stale = record.limitsStale
        PanelSection(title: record.limitsTitle(), stale: stale, hint: stale ? record.limitsNote : nil, model: model) {
            ForEach(Array(limits.enumerated()), id: \.offset) { _, window in
                VStack(alignment: .leading, spacing: 6) {
                    ValueRow(title: window.title, value: Panel.percentText(window.percent), alarming: window.alarming)
                    Bar(value: window.percent, color: window.alarming ? Theme.urgent : Theme.foreground).frame(height: 5)
                    let reset = Panel.resetText(window.resetsAt, now: model.state.now)
                    if !reset.isEmpty {
                        Text(reset).font(Theme.font(8.5)).foregroundColor(Theme.dim)
                    }
                }
            }
        }
    }
}

struct DaysSection: View {
    var record: AgentRecord
    var days: [UsageDay]
    @ObservedObject var model: PanelModel

    var body: some View {
        let values = Panel.dayBarValues(days)
        PanelSection(title: "TOKENS BY DAY", model: model) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                let isToday = Panel.isToday(day, now: model.state.now)
                let row = "day-\(index)"
                let lit = isToday || model.state.hoveredRow == row
                HStack(spacing: 0) {
                    Text(isToday ? "Today" : Usage.dayName(day.date))
                        .font(Theme.font(8.5, bold: isToday))
                        .foregroundColor(lit ? Theme.foreground : Theme.dim)
                        .frame(minWidth: 52, alignment: .leading)
                    Bar(value: values[index], fillAlpha: isToday ? 1 : 0.55)
                        .frame(height: 5)
                        .padding(.leading, 8)
                        .padding(.trailing, 10)
                    Text(Usage.formatTokens(day.tokens))
                        .font(Theme.font(8.5, bold: true))
                        .foregroundColor(lit ? Theme.foreground : Theme.dim)
                        .frame(minWidth: 52, alignment: .trailing)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onHover { model.hover(row, text: record.dayDetail(day, isToday: isToday), inside: $0) }
            }
        }
    }
}

/// One section of model rows: the bar fills behind each row, scaled to the
/// heaviest model so the top row is always full.
struct ModelsSection: View {
    var title: String
    var key: String
    var rows: [(name: String, total: Int, detail: String)]
    @ObservedObject var model: PanelModel

    var body: some View {
        let values = Panel.modelBarValues(rows.map { $0.total })
        PanelSection(title: title, model: model) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                let id = "\(key)-\(index)"
                HStack {
                    Text(row.name).font(Theme.font(9)).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Usage.formatTokens(row.total))
                        .font(Theme.font(9, bold: true))
                        .foregroundColor(model.state.hoveredRow == id ? Theme.foreground : Theme.dim)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Bar(value: values[index], fillAlpha: 0.14, trackAlpha: 0.05, pill: false))
                .contentShape(Rectangle())
                .onHover { model.hover(id, text: row.detail, inside: $0) }
            }
        }
    }
}

/// The bottom line. With a new release out it says so, and opens the
/// settings, where the Update button is.
struct Footer: View {
    @ObservedObject var model: PanelModel
    var record: AgentRecord

    var body: some View {
        let state = model.state
        let text = Panel.footerText(hover: state.hoverText, running: state.running, record: record, newRelease: state.newRelease)
        let release = state.newRelease != nil && state.hoverText == nil
        Text(text.isEmpty ? " " : text)
            .font(Theme.font(8.5))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundColor(release ? (state.hoveredRow == "footer" ? Theme.foreground : Theme.stale) : Theme.dim)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onHover { model.hover("footer", text: nil, inside: $0 && release) }
            .onTapGesture {
                if release {
                    model.actions.footer()
                }
            }
    }
}
