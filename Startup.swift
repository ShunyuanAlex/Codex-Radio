import Foundation
import Combine
import ServiceManagement

struct StartupPreferences {
    static let broadcastKey="autoBroadcastAtLaunchV1"
    static let volumeKey="playbackVolumeV1"
    var autoBroadcast:Bool
    var volume:Double
    static func load(from defaults:UserDefaults)->Self {
        let stored=(defaults.object(forKey:volumeKey) as? NSNumber)?.doubleValue ?? 0.18
        return Self(autoBroadcast:defaults.bool(forKey:broadcastKey),volume:normalizedVolume(stored))
    }
    static func normalizedVolume(_ value:Double)->Double{value.isFinite ? min(0.5,max(0,value)) : 0.18}
    func shouldEnableBroadcast(consent:Bool,configured:Bool,voicesReady:Bool)->Bool {
        autoBroadcast && consent && configured && voicesReady
    }
}

enum LoginItemState:Equatable {
    case off,on,approval,unavailable
    var requested:Bool{self == .on || self == .approval}
    var title:String {
        switch self{case .off:return "未启用";case .on:return "登录时自动启动";case .approval:return "等待系统允许";case .unavailable:return "登录项不可用"}
    }
}
protocol LoginItemService {
    var state:LoginItemState{get}
    func register()throws
    func unregister()throws
}
struct SystemLoginItemService:LoginItemService {
    var state:LoginItemState {
        switch SMAppService.mainApp.status {
        case .notRegistered:return .off
        case .enabled:return .on
        case .requiresApproval:return .approval
        case .notFound:return .unavailable
        @unknown default:return .unavailable
        }
    }
    func register()throws{try SMAppService.mainApp.register()}
    func unregister()throws{try SMAppService.mainApp.unregister()}
}
final class LoginItemController:ObservableObject {
    @Published private(set) var state:LoginItemState
    @Published private(set) var message=""
    private let service:LoginItemService
    let installed:Bool
    init(service:LoginItemService=SystemLoginItemService(),installed:Bool=LoginItemController.installedLocation) {
        self.service=service;self.installed=installed;state=service.state
    }
    static var installedLocation:Bool {
        let app=Bundle.main.bundleURL.standardizedFileURL.path
        let personal=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path+"/"
        return app.hasPrefix("/Applications/") || app.hasPrefix(personal)
    }
    func refresh(){state=service.state;if state == .on{message=""}}
    func setEnabled(_ enabled:Bool) {
        message="";refresh()
        guard !enabled || installed else{message="请先将 Radio 安装到应用程序文件夹，再开启登录启动。";return}
        do {
            if enabled && !state.requested{try service.register()}
            else if !enabled && state.requested{try service.unregister()}
        }catch{message="macOS 未能更新登录项：\(error.localizedDescription)"}
        state=service.state
    }
    func openSystemSettings(){SMAppService.openSystemSettingsLoginItems()}
}
