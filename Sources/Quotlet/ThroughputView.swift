import Charts
import SwiftUI

/// 独立的一秒时钟只更新速度区域，不触发额度 API 或整页刷新。
struct ThroughputView: View {
    @EnvironmentObject private var store: Store
    let snapshot: LocalSnapshot
    var isLoading = false
    @AppStorage("throughputSeconds") private var seconds = 60
    @State private var selected: Date?
    @State private var hoveredFraction: Double? = Snapshot.throughputCursorFraction
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = Fmt.tz
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let speed = Throughput(snapshot: snapshot, now: context.date)
            let range = [60, 120, 300].contains(seconds) ? seconds : 60
            let points = speed.points(seconds: range)
            let readings = speed.readings
            let recent = readings.contains(where: \.hasRecentResponse)
            let current = readings.reduce(0) { $0 + $1.speed }
            let partial = readings.contains(where: \.isPartial)
            let cursor = hoveredFraction.map { context.date.addingTimeInterval(Double(range) * ($0 - 1)) } ?? selected
            let focus = cursor.flatMap { date in points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) } }
            let peak = points.map(\.total).max() ?? 0

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 10) {
                    SpeedOrb(speed: current, active: speed.generating > 0, diameter: 44)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(isLoading ? "—" : speedText(current, partial: partial))
                            .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                        Text("tok/s").font(Theme.caption).foregroundStyle(Theme.text2)
                    }
                    .accessibilityLabel(L("全部 AI 总吞吐", "Total AI throughput", ja: "全 AI の合計スループット", ko: "전체 AI 처리량"))
                    .help(isLoading ? L("正在读取本机日志…", "Reading local logs…", ja: "ログを読み込み中…", ko: "로컬 로그를 읽는 중…") : status(speed, recent: recent))
                    Spacer(minLength: 0)
                    menuBarSourcePicker
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(L("峰值 ", "Peak ", ja: "ピーク ", ko: "최고 ") + Fmt.speed(peak) + " tok/s")
                        .font(.system(size: 10.5).monospacedDigit())
                    Spacer(minLength: 4)
                    ChipPicker(options: [
                        (60, L("1 分", "1m", ja: "1 分", ko: "1분")),
                        (120, L("2 分", "2m", ja: "2 分", ko: "2분")),
                        (300, L("5 分", "5m", ja: "5 分", ko: "5분"))
                    ], selection: $seconds, compact: true)
                }
                .foregroundStyle(Theme.text2)
                chart(points, focus: focus, peak: peak)
                HStack(alignment: .top, spacing: 8) {
                    ForEach(readings) { reading in
                        sourceReading(reading)
                    }
                }
            }
            .foregroundStyle(Theme.text)
            .help(L("只计算输出 token（含推理），包含首 token 等待时间，并行请求相加。生成中的 Codex / Claude 按同来源、同模型最近 5 次回复估算；没有样本时显示 —。Gemini 仅在回复完成后计入曲线。日志 2 分钟无活动后停止估算。",
                    "Output tokens including reasoning, with time to first token; concurrent requests add up. In-flight Codex / Claude requests use the last 5 responses from the same source and model; — means no samples. Gemini appears after completion. Estimates expire after 2 minutes without log activity.",
                    ja: "推論を含む出力トークン。最初のトークンまでの待ち時間を含み、並列リクエストは合算。Codex / Claude の生成中は同ソース・モデルの直近 5 応答から推定。Gemini は完了後に反映。ログ更新が 2 分間なければ推定を停止。",
                    ko: "추론을 포함한 출력 토큰과 첫 토큰 대기 시간을 측정하며 병렬 요청은 합산합니다. Codex / Claude 생성 중에는 같은 소스와 모델의 최근 응답 5개로 추정합니다. Gemini는 완료 후 반영되며 2분간 로그 활동이 없으면 추정이 만료됩니다."))
        }
        .onChange(of: seconds) { _, _ in
            selected = nil
            hoveredFraction = nil
        }
    }

    private func speedText(_ value: Double, partial: Bool) -> String {
        if partial && value == 0 { return "—" }
        return (partial ? "≥" : "") + Fmt.speed(value)
    }

    private var menuBarSourcePicker: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(L("状态栏来源", "Menu bar source", ja: "メニューバー", ko: "메뉴 막대 소스"))
                .font(.system(size: 9.5)).foregroundStyle(Theme.text2)
            Menu {
                Picker(L("状态栏来源", "Menu bar source", ja: "メニューバーのソース", ko: "메뉴 막대 소스"), selection: $store.menuBarSource) {
                    Text("Claude").tag(Source.claude)
                    Text("Codex").tag(Source.codex)
                    Text("Gemini").tag(Source.gemini)
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 5) {
                    Text(store.menuBarSource == .claude ? "Claude" : store.menuBarSource.title)
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Theme.hover))
                .contentShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L("选择顶部菜单栏显示的额度来源。总吞吐始终汇总全部 AI。",
                    "Choose the quota source in the menu bar. Throughput always includes all AI sources.",
                    ja: "メニューバーの使用枠ソースを選択。スループットは全 AI を合算します。",
                    ko: "메뉴 막대의 한도 소스를 선택합니다. 처리량은 모든 AI 소스를 합산합니다."))
        }
        .frame(width: 86, alignment: .trailing)
        .padding(.top, 1)
    }

    private func sourceReading(_ reading: Throughput.Reading) -> some View {
        HStack(spacing: 4) {
            Circle().fill(sourceColor(reading.source)).frame(width: 4, height: 4)
                .accessibilityHidden(true)
            Text(reading.source == .claude ? "Claude" : reading.source.title)
                .font(.system(size: 10.5, weight: .medium))
            Text(isLoading || !reading.detected ? "—" : speedText(reading.speed, partial: reading.isPartial))
                .font(.system(size: 10.5).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help((reading.source == .claude ? "Claude" : reading.source.title) + " · "
              + speedText(reading.speed, partial: reading.isPartial) + " tok/s · " + sourceStatus(reading))
        .accessibilityElement(children: .combine)
        .accessibilityValue(speedText(reading.speed, partial: reading.isPartial) + " tok/s")
    }

    private func sourceColor(_ source: Source) -> Color {
        switch source {
        case .claude: return Theme.data
        case .codex: return Theme.codex
        case .gemini: return Theme.gemini
        }
    }

    private func sourceStatus(_ reading: Throughput.Reading) -> String {
        if isLoading { return L("读取中", "Loading", ja: "読み込み中", ko: "읽는 중") }
        if !reading.detected { return L("未检测到", "Not detected", ja: "未検出", ko: "감지되지 않음") }
        if reading.isPartial { return L("生成中 · 待测", "Generating · pending", ja: "生成中 · 計測待ち", ko: "생성 중 · 측정 대기") }
        if reading.isEstimated { return L("生成中 · 估算", "Generating · est.", ja: "生成中 · 推定", ko: "생성 중 · 추정") }
        if reading.tools > 0 { return L("工具 \(reading.tools)", "Tools \(reading.tools)", ja: "ツール \(reading.tools)", ko: "도구 \(reading.tools)") }
        if reading.hasRecentResponse { return L("刚完成 · 实测", "Finished · measured", ja: "完了 · 実測", ko: "완료 · 측정") }
        if reading.source == .gemini { return L("完成后更新", "Updates on completion", ja: "完了後に更新", ko: "완료 후 업데이트") }
        return L("待机", "Idle", ja: "待機", ko: "대기")
    }

    private func status(_ speed: Throughput, recent: Bool) -> String {
        if speed.generating > 0 || speed.tools > 0 {
            return L("生成 \(speed.generating) · 工具 \(speed.tools)", "Generating \(speed.generating) · Tools \(speed.tools)", ja: "生成 \(speed.generating) · ツール \(speed.tools)", ko: "생성 \(speed.generating) · 도구 \(speed.tools)")
                + (speed.generating > 0 ? L(" · 估算", " · estimated", ja: " · 推定", ko: " · 추정") : "")
        }
        return recent ? L("刚完成 · 实测", "Just finished · measured", ja: "完了 · 実測", ko: "완료 · 측정")
            : L("待机 · 等待新回复", "Idle · waiting for a response", ja: "待機 · 応答待ち", ko: "대기 · 새 응답 기다리는 중")
    }

    private func hoverLabel(_ point: Throughput.Point) -> some View {
        HStack(spacing: 6) {
            Text(Self.clock.string(from: point.date))
                .foregroundStyle(Theme.text2)
            Text(Fmt.speed(point.total) + " tok/s")
                .fontWeight(.semibold)
                .foregroundStyle(Theme.text)
            if point.estimated > 0 {
                Text(L("估算", "Est.", ja: "推定", ko: "추정"))
                    .foregroundStyle(Theme.text2)
            }
        }
        .font(.system(size: 10).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 6)
    }

    private func chart(_ points: [Throughput.Point], focus: Throughput.Point?, peak: Double) -> some View {
        Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Time", point.date), y: .value("tok/s", point.total))
                    .foregroundStyle(LinearGradient(colors: [Theme.throughput.opacity(0.18), Theme.throughput.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", point.date), y: .value("tok/s", point.measured), series: .value("Series", "measured"))
                    .foregroundStyle(Theme.throughput).lineStyle(StrokeStyle(lineWidth: 1.4))
                if point.estimated > 0 {
                    LineMark(x: .value("Time", point.date), y: .value("tok/s", point.total), series: .value("Series", "estimated"))
                        .foregroundStyle(Theme.throughput).lineStyle(StrokeStyle(lineWidth: 1.4, dash: [3, 3]))
                }
            }
            if let focus {
                RuleMark(x: .value("Time", focus.date)).foregroundStyle(Theme.marker)
                PointMark(x: .value("Time", focus.date), y: .value("tok/s", focus.total))
                    .foregroundStyle(Theme.throughput).symbolSize(22)
            }
        }
        .chartXScale(domain: points.first!.date...points.last!.date)
        .chartYScale(domain: 0...max(50, (peak * 1.15 / 50).rounded(.up) * 50))
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3])).foregroundStyle(Theme.divider)
                AxisValueLabel { if let n = value.as(Double.self) { Text(Fmt.speed(n)).font(.system(size: 9)).foregroundStyle(Theme.text2) } }
            }
        }
        .chartXAxis(.hidden)
        .chartXSelection(value: $selected)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Color.clear.contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                if let frame = proxy.plotFrame {
                                    let rect = geometry[frame]
                                    hoveredFraction = rect.contains(location) && rect.width > 0
                                        ? min(1, max(0, Double((location.x - rect.minX) / rect.width))) : nil
                                    selected = nil
                                }
                            case .ended:
                                hoveredFraction = nil
                                selected = nil
                            }
                        }
                    if let focus, let frame = proxy.plotFrame,
                       let x = proxy.position(forX: focus.date) {
                        let rect = geometry[frame]
                        let width = min(rect.width, focus.estimated > 0 ? 166.0 : 138.0)
                        // 提示框固定在图底，并在左右边缘收进绘图区，不遮住相邻来源和刻度。
                        hoverLabel(focus)
                            .frame(width: width, height: 24)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.group))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.divider, lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
                            .position(x: min(rect.maxX - width / 2, max(rect.minX + width / 2, rect.minX + x)),
                                      y: rect.maxY - 12)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .environment(\.timeZone, Fmt.tz)
        .frame(height: 56)
        .help("")
        .accessibilityLabel(L("输出吞吐速度曲线", "Output throughput chart", ja: "出力スループットグラフ", ko: "출력 처리량 차트"))
    }
}

private struct SpeedOrb: View {
    let speed: Double
    let active: Bool
    var diameter: CGFloat = 72
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var fill: Double { min(1, max(0, speed / 400)) }
    private var symbol: String {
        if speed <= 0 { return active ? "ellipsis" : "moon.zzz" }
        if speed < 30 { return "figure.walk" }
        if speed < 80 { return "bicycle" }
        if speed < 180 { return "car.side" }
        if speed < 350 { return "tram" }
        return "airplane"
    }

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Theme.group, Theme.surface, Theme.track.opacity(0.6)], center: .init(x: 0.35, y: 0.25), startRadius: 1, endRadius: diameter * 5 / 6))
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 3)
            ForEach(0..<36) { index in
                Capsule().fill(Double(index) / 36 < fill ? Theme.throughput : Theme.track)
                    .frame(width: diameter * 2.5 / 72, height: diameter * 5 / 72)
                    .offset(y: -diameter * 31 / 72)
                    .rotationEffect(.degrees(-140 + Double(index) * 8))
            }
            Image(systemName: symbol)
                .font(.system(size: diameter / 3, weight: .light))
                .foregroundStyle(speed > 0 ? Theme.throughput : Theme.text2)
                .contentTransition(.symbolEffect(.replace))
            Circle().fill(active ? Theme.live : Theme.marker).frame(width: 3, height: 3).offset(y: diameter * 23 / 72)
        }
        .frame(width: diameter, height: diameter)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: speed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("速度仪表", "Speed gauge", ja: "速度メーター", ko: "속도계"))
        .accessibilityValue(Fmt.speed(speed) + " tok/s")
    }
}
