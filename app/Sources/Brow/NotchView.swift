import AppKit
import SwiftUI

extension Color {
    static let browAccent = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let browGreen = Color(red: 0.36, green: 0.82, blue: 0.53)
    static let browBlue = Color(red: 0.40, green: 0.63, blue: 1.0)
    static let dim = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.07)
}

/// Black shape that grows out of the notch: concave "ears" at the top edge,
/// rounded corners at the bottom.
struct NotchShape: Shape {
    var top: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(top, bottom) }
        set { top = newValue.first; bottom = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + top, y: r.minY + top), control: CGPoint(x: r.minX + top, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + top, y: r.maxY - bottom))
        p.addQuadCurve(to: CGPoint(x: r.minX + top + bottom, y: r.maxY), control: CGPoint(x: r.minX + top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top - bottom, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - top, y: r.maxY - bottom), control: CGPoint(x: r.maxX - top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top, y: r.minY + top))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - top, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// The brow mark: a raised brow over an eye (the camera in the notch).
struct BrowGlyph: View {
    var size: CGFloat = 16

    var body: some View {
        Canvas { ctx, s in
            let w = s.width
            var brow = Path()
            brow.move(to: CGPoint(x: w * 0.10, y: w * 0.40))
            brow.addQuadCurve(to: CGPoint(x: w * 0.92, y: w * 0.22), control: CGPoint(x: w * 0.38, y: w * -0.04))
            ctx.stroke(brow, with: .color(.browAccent), style: StrokeStyle(lineWidth: w * 0.15, lineCap: .round))
            let ring = CGRect(x: w * 0.30, y: w * 0.50, width: w * 0.40, height: w * 0.40)
            ctx.stroke(Path(ellipseIn: ring), with: .color(.white), lineWidth: w * 0.11)
            ctx.fill(Path(ellipseIn: ring.insetBy(dx: w * 0.12, dy: w * 0.12)), with: .color(.white))
        }
        .frame(width: size, height: size)
    }
}

struct StatusDot: View {
    var state: SessionState
    var size: CGFloat = 8
    /// Only visible dots pulse: a running animation redraws every frame.
    var pulse = false

    var color: Color {
        switch state {
        case .working: .browBlue
        case .waiting: .browAccent
        case .done: .browGreen
        }
    }

    var body: some View {
        let dot = Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background(Circle().fill(color.opacity(0.35)).frame(width: size * 2, height: size * 2).blur(radius: 3))
        if pulse && state == .working {
            dot.phaseAnimator([false, true]) { dot, faded in
                dot.opacity(faded ? 0.3 : 1)
            } animation: { _ in .easeInOut(duration: 0.8) }
        } else {
            dot
        }
    }
}

struct PillButton: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, primary: primary)
    }

    private struct Pill: View {
        let configuration: Configuration
        let primary: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(primary ? Color.black : Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(primary ? Color.browAccent : Color.white.opacity(0.12), in: Capsule())
                .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.7 : 1)
        }
    }
}

private let relative: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.locale = Locale(identifier: "uk_UA")
    f.unitsStyle = .short
    return f
}()

struct NotchRoot: View {
    let notch: NotchGeometry
    @Environment(SessionStore.self) private var store
    @State private var collapse: DispatchWorkItem?
    /// Natural height of the open content, measured even while closed, so the
    /// shape can spring straight to its final size.
    @State private var openHeight: CGFloat = 300

    private let wing: CGFloat = 46
    private let openWidth: CGFloat = 600

    private var open: Bool { store.expanded }
    private var size: CGSize {
        open ? CGSize(width: openWidth, height: openHeight)
             : CGSize(width: notch.width + 2 * wing + 16, height: notch.height)
    }
    private var shape: NotchShape { NotchShape(top: open ? 14 : 8, bottom: open ? 26 : 12) }

    // One black shape that only changes size; both contents live inside it and
    // cross-fade, so nothing is rebuilt mid-animation.
    var body: some View {
        ZStack(alignment: .top) {
            shape
                .fill(Color.black)
                .shadow(color: .black.opacity(open ? 0.4 : 0), radius: 14, y: 8)
            ZStack(alignment: .top) {
                collapsed
                    .opacity(open ? 0 : 1)
                    .animation(.easeOut(duration: open ? 0.08 : 0.2), value: open)
                expanded
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { openHeight = $0 }
                    .opacity(open ? 1 : 0)
                    .scaleEffect(open ? 1 : 0.94, anchor: .top)
                    .animation(open ? .easeOut(duration: 0.22).delay(0.06) : .easeOut(duration: 0.1), value: open)
                    .allowsHitTesting(open)
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onHover(perform: hover)
        .onTapGesture { if !open { store.expanded = true } }
        .contextMenu { NotchMenu() }
        .animation(.spring(response: 0.4, dampingFraction: 0.84), value: open)
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: openHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    private func hover(_ inside: Bool) {
        collapse?.cancel()
        if inside {
            store.pinned = false
            store.expanded = true
            return
        }
        guard !store.pinned else { return }
        let work = DispatchWorkItem {
            store.expanded = false
            store.selectedID = nil
        }
        collapse = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private var collapsed: some View {
        HStack(spacing: 0) {
            BrowGlyph(size: 15)
                .frame(width: wing)
            Color.clear.frame(width: notch.width)
            HStack(spacing: 5) {
                if store.waitingCount > 0 {
                    StatusDot(state: .waiting, size: 7)
                    Text("\(store.waitingCount)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                } else if !store.sessions.isEmpty {
                    StatusDot(state: store.sessions.contains { $0.state == .working } ? .working : .done, size: 7)
                }
            }
            .frame(width: wing)
        }
        .frame(height: notch.height)
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                BrowGlyph(size: 16)
                Text("brow")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer(minLength: notch.width)
                Text(store.waitingCount == 0 ? "усе спокійно" : "чекають: \(store.waitingCount)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(store.waitingCount == 0 ? Color.dim : Color.browAccent)
            }
            .padding(.horizontal, 10)
            .frame(height: notch.height)

            Group {
                if let session = store.selected {
                    SessionDetail(session: session)
                        .id(session.id)
                } else {
                    SessionList()
                }
            }
            .transition(.opacity)
            .animation(.easeOut(duration: 0.18), value: store.selectedID)
            .padding(.top, 8)

            if let toast = store.toast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.browGreen)
                    Text(toast).lineLimit(1).foregroundStyle(.white)
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.faint, in: Capsule())
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 16)
        .padding(.horizontal, 14)
        .frame(width: openWidth)
        .animation(.easeOut(duration: 0.2), value: store.toast)
    }
}

/// Right-click menu: settings, hook setup, quit.
struct NotchMenu: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        @Bindable var prefs = store.prefs
        Toggle("Тримати сесію для відповіді з нотча", isOn: $prefs.holdReplies)
        Picker("Чекати на відповідь", selection: $prefs.holdMinutes) {
            ForEach([5, 10, 20, 30], id: \.self) { Text("\($0) хв").tag($0) }
        }
        Divider()
        if prefs.isAppBundle {
            Toggle("Запускати під час входу", isOn: Binding(get: { prefs.launchAtLogin }, set: { prefs.launchAtLogin = $0 }))
        }
        if HookInstaller.isInstalled() {
            Button("Відключити від усіх сесій Claude…") { HookInstaller.uninstall() }
        } else {
            Button("Підключити до всіх сесій Claude…") { HookInstaller.install() }
        }
        Divider()
        Button("Вийти з brow") {
            NSApp.terminate(nil)
        }
    }
}

struct SessionList: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        VStack(spacing: 4) {
            if store.sessions.isEmpty {
                Text("Поки немає сесій. Вони з'являться, щойно Claude щось зробить.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
            ForEach(store.sessions) { session in
                SessionRow(session: session)
                    .onTapGesture { store.select(session) }
            }
        }
    }
}

struct SessionRow: View {
    var session: Session
    @Environment(SessionStore.self) private var store
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StatusDot(state: session.state, pulse: store.expanded)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(session.project)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Image(systemName: session.client.symbol)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.dim)
                    Text(session.title)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.dim)
                        .lineLimit(1)
                    Spacer()
                    if let tag = session.tag, session.state != .working {
                        Text(tag)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.browAccent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.browAccent.opacity(0.15), in: Capsule())
                    }
                    Text(Date.now.timeIntervalSince(session.updated) < 5
                         ? "щойно" : relative.localizedString(for: session.updated, relativeTo: .now))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dim)
                }
                Text(session.questions.first?.text ?? session.lastMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(hovered ? Color.faint : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}

struct SessionDetail: View {
    var session: Session
    @Environment(SessionStore.self) private var store
    @State private var fullMessage = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { store.select(nil) } label: {
                    Label("Усі сесії", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.dim)
                Spacer()
                Button { store.open(session) } label: {
                    Label("Відкрити", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.dim)
            }
            .font(.system(size: 12, weight: .medium))

            HStack(spacing: 8) {
                StatusDot(state: session.state, pulse: store.expanded)
                Text(session.project).font(.system(size: 15, weight: .bold))
                Text(session.title).font(.system(size: 13)).foregroundStyle(Color.dim)
                Spacer()
                Label(session.client.name, systemImage: session.client.symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dim)
            }
            .foregroundStyle(.white)

            if session.lastMessage != SessionStore.newSessionText {
                message
            }

            let canReply = store.canReply(session)
            if !session.questions.isEmpty {
                QuestionCard(session: session, questions: session.questions, enabled: canReply)
            } else if let wrapUp = session.wrapUp, canReply {
                WrapUpCard(session: session, wrapUp: wrapUp)
            }
            if let command = session.command {
                CommandCard(session: session, command: command)
            }

            if canReply {
                HStack(spacing: 8) {
                    TextField(session.questions.isEmpty ? "Написати Claude…" : "Своя відповідь…", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .onSubmit(send)
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(draft.isEmpty ? Color.dim : Color.browAccent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.faint, in: RoundedRectangle(cornerRadius: 12))
            } else if session.state != .working {
                Text("Сесія не чекає на відповідь з нотча. Відповісти можна в \(session.client == .desktop ? "програмі Claude" : "терміналі").")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dim)
            }
        }
        .padding(.horizontal, 10)
    }

    private var message: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.lastMessage)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(fullMessage ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
            if session.lastMessage.count > 140 {
                Button(fullMessage ? "Згорнути" : "Розгорнути") { fullMessage.toggle() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.browAccent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.faint, in: RoundedRectangle(cornerRadius: 12))
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        store.send(text, to: session)
    }
}

struct QuestionCard: View {
    var session: Session
    var questions: [Question]
    var enabled: Bool
    @Environment(SessionStore.self) private var store
    /// Picked labels per question, used when there is more than one question
    /// or several answers are allowed; a single plain question sends on click.
    @State private var picked: [String: Set<String>] = [:]

    private var sendsOnClick: Bool { questions.count == 1 && !questions[0].multiSelect }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(questions, id: \.self) { question in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(question.header.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.browAccent)
                        Text(question.text)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    ForEach(question.options, id: \.self) { option in
                        optionButton(question, option)
                    }
                }
            }
            if enabled && !sendsOnClick {
                Button("Відправити") { submit() }
                    .buttonStyle(PillButton(primary: true))
                    .disabled(questions.contains { picked[$0.text, default: []].isEmpty })
            }
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
    }

    private func optionButton(_ question: Question, _ option: QuestionOption) -> some View {
        let isPicked = picked[question.text, default: []].contains(option.label)
        return Button {
            if sendsOnClick {
                store.answer([question.text: option.label], to: session)
            } else if question.multiSelect {
                picked[question.text, default: []].formSymmetricDifference([option.label])
            } else {
                picked[question.text] = [option.label]
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    if !option.detail.isEmpty {
                        Text(option.detail).font(.system(size: 11)).foregroundStyle(Color.dim)
                    }
                }
                Spacer()
                Image(systemName: sendsOnClick ? "chevron.right" : (isPicked ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 12))
                    .foregroundStyle(isPicked ? Color.browAccent : Color.dim)
            }
            .padding(10)
            .background(Color.white.opacity(isPicked ? 0.16 : 0.09), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func submit() {
        let answers = questions.reduce(into: [String: String]()) { result, question in
            let chosen = picked[question.text, default: []]
            result[question.text] = question.options.map(\.label).filter(chosen.contains).joined(separator: ", ")
        }
        store.answer(answers, to: session)
    }
}

struct WrapUpCard: View {
    var session: Session
    var wrapUp: WrapUp
    @Environment(SessionStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let ask = wrapUp.ask {
                Text(ask).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            }
            HStack(spacing: 8) {
                ForEach(Array(wrapUp.actions.enumerated()), id: \.element) { index, action in
                    Button(action.label) { store.send(action.message, to: session) }
                        .buttonStyle(PillButton(primary: index == 0))
                }
            }
        }
    }
}

struct CommandCard: View {
    var session: Session
    var command: String
    @Environment(SessionStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("$ " + command)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.browGreen)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 8) {
                Button { store.runCommand(of: session) } label: {
                    Label("Запустити в Ghostty", systemImage: "play.fill")
                }
                .buttonStyle(PillButton(primary: true))
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    store.showToast("Скопійовано")
                } label: {
                    Label("Копіювати", systemImage: "doc.on.doc")
                }
                .buttonStyle(PillButton())
            }
        }
    }
}
