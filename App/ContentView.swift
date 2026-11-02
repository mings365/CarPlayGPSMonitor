import SwiftUI
import CoreLocation
import UniformTypeIdentifiers
import Combine

struct GPSSample: Identifiable {
    let id = UUID()
    let received: Date
    let location: CLLocation
    let source: String
    let simulated: String
    let session: String
    var csv: String {
        let c = location.coordinate
        let f = ISO8601DateFormatter()
        return "\(f.string(from: received)),\(f.string(from: location.timestamp)),\(session),\(source),\(simulated),\(c.latitude),\(c.longitude),\(location.horizontalAccuracy),\(location.speed),\(location.course)"
    }
}

@MainActor
final class GPSMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var samples: [GPSSample] = []
    @Published var status = "未开始"
    @Published var running = false
    @Published var session = "未连接CarPlay"
    @Published var keepNonExternalOnly = false
    @Published var authorization = "未知"

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        updateAuthorization()
    }

    var externalCount: Int { samples.filter { $0.source == "EXTERNAL" }.count }
    var nonExternalCount: Int { samples.filter { $0.source == "NON_EXTERNAL" }.count }
    var unknownCount: Int { samples.filter { $0.source == "UNKNOWN" }.count }
    var filteredSamples: [GPSSample] {
        keepNonExternalOnly ? samples.filter { $0.source == "NON_EXTERNAL" } : samples
    }

    func start() {
        guard CLLocationManager.locationServicesEnabled() else {
            status = "请在系统设置中开启定位服务"
            return
        }
        let auth = manager.authorizationStatus
        if auth == .notDetermined {
            status = "请允许精确位置权限，然后再次点击开始"
            manager.requestWhenInUseAuthorization()
            return
        }
        guard auth == .authorizedWhenInUse || auth == .authorizedAlways else {
            status = "请在设置中允许本App使用精确位置"
            return
        }
        running = true
        status = "采集中（请保持本App在前台）"
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        running = false
        status = "已停止"
    }

    func clear() {
        stop()
        samples.removeAll()
        status = "日志已清空"
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorization()
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            status = "定位权限就绪，点击开始采集"
        }
    }

    private func updateAuthorization() {
        switch manager.authorizationStatus {
        case .authorizedAlways: authorization = "始终允许"
        case .authorizedWhenInUse: authorization = "使用App期间允许"
        case .denied: authorization = "拒绝"
        case .restricted: authorization = "受限制"
        case .notDetermined: authorization = "尚未授权"
        @unknown default: authorization = "未知"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard running else { return }
        for location in locations {
            let source: String
            let simulated: String
            if let info = location.sourceInformation {
                source = info.isProducedByAccessory ? "EXTERNAL" : "NON_EXTERNAL"
                simulated = info.isSimulatedBySoftware ? "YES" : "NO"
            } else {
                source = "UNKNOWN"
                simulated = "UNKNOWN"
            }
            samples.append(GPSSample(received: Date(), location: location,
                                     source: source, simulated: simulated, session: session))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "定位错误：\(error.localizedDescription)"
    }

    var csvText: String {
        let header = "received_utc,location_timestamp_utc,mode,source,simulated,latitude,longitude,horizontal_accuracy_m,speed_mps,course_degrees"
        return ([header] + samples.map(\.csv)).joined(separator: "\n") + "\n"
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }
    static var writableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct ContentView: View {
    @StateObject private var monitor = GPSMonitor()
    @State private var exporting = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("状态：\(monitor.status)").font(.subheadline)
                Text("定位权限：\(monitor.authorization)").font(.caption)
                Picker("实验模式", selection: $monitor.session) {
                    Text("手机独立").tag("未连接CarPlay")
                    Text("有线CarPlay").tag("有线CarPlay")
                    Text("无线CarPlay").tag("无线CarPlay")
                }
                .pickerStyle(.menu)
                HStack {
                    countView("外部", monitor.externalCount)
                    Spacer()
                    countView("非外部", monitor.nonExternalCount)
                    Spacer()
                    countView("未知", monitor.unknownCount)
                }
                Toggle("仅显示非外部定位（不影响采集）", isOn: $monitor.keepNonExternalOnly)
                    .font(.caption)
                HStack {
                    Button("开始") { monitor.start() }
                        .buttonStyle(.borderedProminent)
                        .disabled(monitor.running)
                    Button("停止") { monitor.stop() }
                        .buttonStyle(.bordered)
                        .disabled(!monitor.running)
                    Button("清空") { monitor.clear() }
                        .buttonStyle(.bordered)
                    Button("导出CSV") { exporting = true }
                        .buttonStyle(.bordered)
                        .disabled(monitor.samples.isEmpty)
                }
                Text("已采集 \(monitor.samples.count) 条；当前显示 \(monitor.filteredSamples.count) 条")
                    .font(.caption)
                List(monitor.filteredSamples.reversed()) { sample in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(sample.source)  \(sample.received.formatted(date: .omitted, time: .standard))")
                            .font(.system(.caption, design: .monospaced)).bold()
                        Text(String(format: "%.6f, %.6f    ±%.1f m",
                                    sample.location.coordinate.latitude,
                                    sample.location.coordinate.longitude,
                                    sample.location.horizontalAccuracy))
                            .font(.system(size: 11, design: .monospaced))
                        Text("\(sample.session) / 模拟定位：\(sample.simulated)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .listStyle(.plain)
                Text("隐私：数据仅保存在本App内存；退出后可能丢失。请在每次测试后导出CSV。驾车时由乘客操作。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("CarPlay GPS 检测")
            .fileExporter(isPresented: $exporting,
                          document: CSVDocument(text: monitor.csvText),
                          contentType: .commaSeparatedText,
                          defaultFilename: "carplay-gps-log") { result in
                if case .failure(let error) = result {
                    monitor.status = "导出失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func countView(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading) {
            Text("\(value)").font(.title2).monospacedDigit()
            Text(title).font(.caption2)
        }
    }
}
