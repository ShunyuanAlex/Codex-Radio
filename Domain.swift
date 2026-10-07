import Foundation

enum RadioStatus: String, CaseIterable, Codable, Identifiable {
    case reading, searching, editing, testing, delegating, success, complete, retry, waiting, blocked, cancelled, unknown, compacting
    var id: String { rawValue }
    var title: String {
        switch self {
        case .reading: return "发送 / 插入"
        case .searching: return "搜索"
        case .editing: return "修改"
        case .testing: return "处理中"
        case .delegating: return "分派"
        case .success: return "成功"
        case .complete: return "本轮收尾"
        case .retry: return "重试"
        case .waiting: return "等待确认"
        case .blocked: return "工具报错"
        case .cancelled: return "已停止"
        case .unknown: return "工具返回"
        case .compacting: return "压缩上下文"
        }
    }
    var priority: Int {
        switch self { case .blocked,.cancelled: return 3; case .reading,.waiting,.retry,.compacting: return 2; case .complete,.unknown: return 1; default: return 0 }
    }
    var symbol: String {
        switch self {
        case .reading: return "doc.text"
        case .searching: return "magnifyingglass"
        case .editing: return "pencil"
        case .testing: return "checkmark.seal"
        case .delegating: return "arrow.triangle.branch"
        case .success: return "checkmark.circle"
        case .complete: return "flag.checkered"
        case .retry: return "arrow.clockwise"
        case .waiting: return "hand.raised"
        case .blocked: return "exclamationmark.triangle"
        case .cancelled: return "xmark.circle"
        case .unknown: return "questionmark.circle"
        case .compacting: return "arrow.down.right.and.arrow.up.left"
        }
    }
}

struct FlightChannel: Identifiable, Codable {
    var id: String
    var callsignIndex: Int
    var number:Int = -1
    var projectID="unassigned"
    var projectTitle="独立对话"
    var title="正在读取对话标题"
    var updatedAt:Double=0
    var archived=false
    var activity=ConversationActivity()
    var callsign: String { CallsignCatalog.words(for:callsignIndex).joined(separator:" ") + (number>=0 ? " \(number)" : "") }
    var status: RadioStatus = .unknown
    var enabled = true
    var lastMessage = "尚未接入 · 可手动试听"
    var sessionLabel = ""
    static let defaults = (0..<4).map { FlightChannel(id:String(format:"%02d",$0+1),callsignIndex:$0) }
}

enum CallsignCatalog {
    // Existing NATO radiotelephony words, never arbitrary text or synthesized speech.
    static let names = ["Alpha","Bravo","Charlie","Delta","Echo","Foxtrot","Golf","Hotel","India","Juliett","Kilo","Lima","Mike","November","Oscar","Papa","Quebec","Romeo","Sierra","Tango","Uniform","Victor","Whiskey","Xray","Yankee","Zulu"]
    static func words(for index:Int)->[String] {
        guard index>=0 else{return []}
        var n=index, result:[String]=[]
        repeat {result.insert(names[n % names.count],at:0);n=n / names.count - 1} while n>=0
        return result
    }
    static func filenames(for index:Int)->[String] {words(for:index).map{($0=="Alpha" ? "alfa" : $0.lowercased())+".wav"}}
    static let recordingFiles=(0..<26).flatMap{filenames(for:$0)}+(0..<10).map{"digit\($0).wav"}
    static func numberFiles(_ number:Int)->[String] {number>=0 ? String(number).map{"digit\($0).wav"} : []}
}

struct ProjectRegistry:Codable {
    var projectKeys:[String]=[]
    var callsigns:[Int]=[]
    var threadKeys:[String:[String]]=[:]
    // Optional for lossless decoding of the 0.5 registry. Materialized per project.
    var numbers:[String:[String:Int]]?
    mutating func register(project:String,thread:String)->(Int,Int) {
        if !projectKeys.contains(project){var free=0;while callsigns.contains(free){free += 1};projectKeys.append(project);callsigns.append(free)}
        if numbers==nil{numbers=[:]}
        if numbers?[project]==nil{numbers?[project]=Dictionary(uniqueKeysWithValues:(threadKeys[project] ?? []).enumerated().map{($0.element,$0.offset+1)})}
        if !(threadKeys[project] ?? []).contains(thread){threadKeys[project,default:[]].append(thread)}
        if numbers?[project]?[thread]==nil {
            let used=Set(numbers?[project]?.values.map{$0} ?? [])
            var free=1;while used.contains(free){free += 1}
            numbers?[project]?[thread]=free
        }
        return (callsigns[projectKeys.firstIndex(of:project)!],numbers![project]![thread]!)
    }
    mutating func assign(project:String,to value:Int) {
        guard value>=0,value<1000000,let i=projectKeys.firstIndex(of:project) else{return}
        if let other=callsigns.firstIndex(of:value){callsigns[other]=callsigns[i]}
        callsigns[i]=value
    }
    @discardableResult mutating func assignNumber(project:String,thread:String,to value:Int)->Bool {
        guard (0...9999).contains(value),threadKeys[project]?.contains(thread)==true else{return false}
        let previous=register(project:project,thread:thread).1
        if let other=numbers?[project]?.first(where:{$0.value==value && $0.key != thread})?.key{numbers?[project]?[other]=previous}
        numbers?[project]?[thread]=value;return true
    }
}

enum MenuBarAppearance:String,CaseIterable {
    case iconOnly,iconAndText
    static let preferenceKey="menuBarAppearanceV1"
    var title:String{self == .iconOnly ? "仅图标" : "图标 + Radio"}
    var statusItemTitle:String{self == .iconOnly ? "" : " Radio"}
    static func load(from defaults:UserDefaults)->Self {
        defaults.string(forKey:preferenceKey).flatMap(Self.init(rawValue:)) ?? .iconAndText
    }
    func save(to defaults:UserDefaults){defaults.set(rawValue,forKey:Self.preferenceKey)}
}

enum ListeningMode:String,CaseIterable {
    case focus,detail,custom
    var title:String{switch self{case .focus:return "专注";case .detail:return "详细";case .custom:return "自定义"}}
    static let availableSounds:[RadioStatus]=[.reading,.testing,.unknown,.compacting,.complete,.waiting,.cancelled,.blocked]
    static let focusSounds:Set<RadioStatus>=[.complete,.waiting,.cancelled,.blocked]
    static let defaultCustomSounds=focusSounds.union([.compacting])
    static func loadCustomSounds(from defaults:UserDefaults)->Set<RadioStatus> {
        var sounds=defaults.stringArray(forKey:"customSoundsV1").map{Set($0.compactMap{RadioStatus(rawValue:$0)})} ?? defaultCustomSounds
        // Enable the new default once; later user opt-outs survive every restart.
        if !defaults.bool(forKey:"compactionSoundDefaultV1") {
            sounds.insert(.compacting)
            defaults.set(sounds.map(\.rawValue).sorted(),forKey:"customSoundsV1")
            defaults.set(true,forKey:"compactionSoundDefaultV1")
        }
        return sounds
    }
    func accepts(_ status:RadioStatus,custom:Set<RadioStatus>)->Bool {
        switch self{case .focus:return Self.focusSounds.contains(status);case .detail:return true;case .custom:return custom.contains(status)}
    }
}

struct RadioEvent: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var channel: String
    var status: RadioStatus
    var origin = "模拟"
    var receivedAt: Double
}

struct AudioClip: Equatable {
    var file: String
    var start: Double = 0
    var duration: Double
    var pause: Double = 0.035
}

enum SoundPack:String,CaseIterable,Identifiable {
    case boeing,airbus,j11a
    var id:String{rawValue}
    static let preferenceKey="soundPackV1"
    var title:String {
        switch self {case .boeing:return "波音";case .airbus:return "空客";case .j11a:return "歼-11A"}
    }
    var displayCode:String {
        switch self {case .boeing:return "BOEING";case .airbus:return "AIRBUS";case .j11a:return "J-11A"}
    }
    var vehicle:String {
        switch self {case .boeing:return "波音 / 777";case .airbus:return "空客 / A320";case .j11a:return "中国 / 歼-11A"}
    }
    var subtitle:String {
        switch self {
        case .boeing:return "777 · 清脆钟声与蜂鸣提醒"
        case .airbus:return "A320 · 高低钟声与三连警示"
        case .j11a:return "歼-11A · 座舱按键与电子警示"
        }
    }
    var sourceNote:String {
        self == .j11a ? "歼-11A / Su-27SK 模拟器共用素材 · 保留真人呼号" : "飞行模拟器素材改编 · 八类提示 · 保留真人呼号"
    }
    static func load(from defaults:UserDefaults)->Self {
        let stored=defaults.string(forKey:preferenceKey)
        // Replace the withdrawn local preview without resetting other preferences.
        if stored == "ssn775" || stored == "asr33" {Self.j11a.save(to:defaults);return .j11a}
        return stored.flatMap(Self.init(rawValue:)) ?? .airbus
    }
    func save(to defaults:UserDefaults){defaults.set(rawValue,forKey:Self.preferenceKey)}
}

enum SoundMap {
    // Eight separately mastered cues per pack. Source recording excerpts and the
    // reproducible excerpt/envelope/level recipe are included with the source.
    static func cueStatus(_ status:RadioStatus)->RadioStatus {
        switch status {
        case .searching,.editing,.delegating:return .testing
        case .success:return .complete
        case .retry:return .waiting
        default:return status
        }
    }
    static func clips(_ status: RadioStatus,pack:SoundPack = .airbus) -> [AudioClip] {
        [AudioClip(file:"Packs/\(pack.rawValue)/\(cueStatus(status).rawValue).wav",duration:3,pause:0)]
    }
    static func description(_ status: RadioStatus,pack:SoundPack = .airbus) -> String {
        if pack == .j11a {
            switch cueStatus(status) {
            case .reading:return "座舱按键 · 发送指令"
            case .testing:return "单声短铃 · 正在处理"
            case .unknown:return "双短电子音 · 收到工具回执"
            case .compacting:return "高低收束音 · 整理上下文"
            case .complete:return "上行双铃 · 本轮收尾"
            case .waiting:return "间隔低频双提醒 · 需要操作"
            case .cancelled:return "短降调 · 已经停止"
            case .blocked:return "三连座舱警示 · 工具报错"
            default:return ""
            }
        }
        switch cueStatus(status) {
        case .reading:return "短按键 · 发送指令"
        case .testing:return "单声短铃 · 正在处理"
        case .unknown:return "双按键 · 收到工具回执"
        case .compacting:return "高低收束音 · 整理上下文"
        case .complete:return "完整双钟声 · 本轮收尾"
        case .waiting:return "间隔双提醒 · 需要操作"
        case .cancelled:return "断开提示 · 已经停止"
        case .blocked:return "连续三连告警 · 工具报错"
        default:return ""
        }
    }
}

final class RadioQueue {
    struct Pending { var event: RadioEvent; var firstAt: Double; var due: Double }
    var pending: [Pending] = []
    var active: RadioEvent?
    var ordinaryStarts: [Double] = []
    var seen = Set<String>()
    var seenOrder: [String] = []
    var muted = true
    var mode = "focus"
    var customSounds=ListeningMode.defaultCustomSounds
    func accepts(_ status: RadioStatus) -> Bool {
        (ListeningMode(rawValue:mode) ?? .focus).accepts(status,custom:customSounds)
    }
    // Returns true only if current audio must be stopped before the next event.
    @discardableResult func offer(_ event: RadioEvent, at now: Double, force: Bool = false) -> Bool {
        guard !muted, force || accepts(event.status), !seen.contains(event.id) else { return false }
        seen.insert(event.id); seenOrder.append(event.id)
        if seenOrder.count > 1000 { seen.remove(seenOrder.removeFirst()) }
        // Detailed mode retains every accepted event in arrival order, including
        // consecutive calls on one conversation. Explicit mute/stop still clears it.
        if mode == "detail"{pending.append(Pending(event:event,firstAt:now,due:now));return false}
        let high = event.status.priority >= 2
        var preempt = false
        if high {
            pending.removeAll { $0.event.status.priority < event.status.priority }
            if let current = active, event.status.priority > current.status.priority { active = nil; preempt = true }
        }
        if !high, let i = pending.firstIndex(where: {$0.event.channel == event.channel && $0.event.status.priority < 2 && now - $0.firstAt <= 0.30}) {
            if event.status.priority >= pending[i].event.status.priority { pending[i].event = event }
        } else {
            pending.removeAll { $0.event.channel == event.channel && $0.event.status.priority <= event.status.priority }
            pending.append(Pending(event:event,firstAt:now,due:now + (high ? 0 : 0.30)))
        }
        if pending.count > 8 { pending.removeFirst(pending.count - 8) }
        return preempt
    }
    func next(at now: Double) -> RadioEvent? {
        if mode == "detail" {
            guard !muted,active==nil,!pending.isEmpty else{return nil}
            let event=pending.removeFirst().event;active=event;return event
        }
        ordinaryStarts.removeAll { now - $0 >= 1 }
        // Speech is longer than a cue. Keep a small 3-second freshness budget, never an unbounded queue.
        pending.removeAll { now - $0.firstAt > 3 }
        guard !muted, active == nil else { return nil }
        let candidates = pending.indices.filter { pending[$0].due <= now && (pending[$0].event.status.priority >= 2 || ordinaryStarts.count < 2) }
        guard let index = candidates.sorted(by: {
            let a=pending[$0],b=pending[$1]
            return a.event.status.priority == b.event.status.priority ? a.firstAt < b.firstAt : a.event.status.priority > b.event.status.priority
        }).first else { return nil }
        let e = pending.remove(at:index).event
        active=e
        if e.status.priority < 2 { ordinaryStarts.append(now) }
        return e
    }
    func finished(_ id: String) { if active?.id == id { active=nil } }
    func clear() { pending=[]; active=nil }
    func mute(_ value: Bool) { muted=value; if value { clear() } }
}
