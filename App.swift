import AppKit
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import Carbon

struct RadioProject:Identifiable {
    let id:String
    let title:String
    let callsign:String
    let channels:[FlightChannel]
}

final class RadioStore:NSObject,ObservableObject,AVAudioPlayerDelegate {
    @Published var channels:[FlightChannel]=[]
    @Published var selected=""
    @Published var muted=true
    @Published var volume:Double=0.18
    @Published var mode="focus"
    @Published var customSounds=ListeningMode.defaultCustomSounds
    @Published var menuBarAppearance=MenuBarAppearance.iconAndText
    @Published var soundPack=SoundPack.airbus
    @Published var latestNotice:RadioEvent?
    @Published var pendingCount=0
    @Published var settingsTab="general"
    @Published var autoBroadcast=false
    @Published var weeklyQuotaAlarm=WeeklyQuotaAlertGate.enabled(in:UserDefaults.standard)
    @Published var weeklyQuota:WeeklyQuotaSnapshot?
    @Published var quotaMessage="等待额度读取"
    @Published var quotaBusy=false
    var quotaTimer:Timer?
    var quotaGeneration=UUID()
    let loginItems=LoginItemController()
    @Published var numberDrafts:[String:String]=[:]
    @Published var settingsMessage="编号保存后立即生效；同项目编号已占用时自动互换。"
    @Published var search=""
    @Published var now="待命 · 声音已静音"
    @Published var phase="真人项目呼号 + 对话编号 → 状态音"
    @Published var log:[String]=[]
    @Published var customClips:[String:URL]=[:]
    @Published var voicesReady=false
    @Published var connected=false
    @Published var receivedCount=0
    @Published var connectionLabel="等待实时事件"
    @Published var collapsed=Set<String>()
    @Published var showAudio=false
    @Published var catalogRefreshing=false
    @Published var catalogNote="正在读取最近 7 天的本地对话"
    @Published var codexHome=URL(fileURLWithPath:UserDefaults.standard.string(forKey:"codexHomeV1") ?? ProcessInfo.processInfo.environment["CODEX_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path)
    @Published var integration=IntegrationSnapshot()
    @Published var integrationMessage=""
    @Published var integrationBusy=false
    @Published var metadataAllowed=false
    var voiceDirectory:URL?
    var projects=ProjectRegistry()
    static var eventDirectory:URL {FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/WingRadio/events")}
    let liveReader=LiveEventReader()
    var liveTimer:Timer?
    var catalogTimer:Timer?
    let queue=RadioQueue()
    var player:AVAudioPlayer?
    var ticker:Timer?
    var stageTask:DispatchWorkItem?
    var generation=UUID()
    var activeID:String?
    var onChange:(()->Void)?
    var onOpenSettings:(()->Void)?

    override init() {
        super.init()
        if let data=UserDefaults.standard.data(forKey:"projectRegistryV1"),let saved=try? JSONDecoder().decode(ProjectRegistry.self,from:data),saved.projectKeys.count==saved.callsigns.count,Set(saved.callsigns).count==saved.callsigns.count{projects=saved}
        if let voices=Bundle.main.resourceURL?.appendingPathComponent("Voices"),validateVoices(voices){voiceDirectory=voices;voicesReady=true}
        if let raw=UserDefaults.standard.string(forKey:"listeningModeV2"),let saved=ListeningMode(rawValue:raw){mode=saved.rawValue}
        customSounds=ListeningMode.loadCustomSounds(from:UserDefaults.standard)
        menuBarAppearance=MenuBarAppearance.load(from:UserDefaults.standard)
        soundPack=SoundPack.load(from:UserDefaults.standard)
        let startup=StartupPreferences.load(from:UserDefaults.standard)
        autoBroadcast=startup.autoBroadcast;volume=startup.volume
        if !weeklyQuotaAlarm{quotaMessage="周额度报警已关闭"}
        queue.mode=mode;queue.customSounds=customSounds
        checkIntegration()
        // Existing reviewed installations keep their definitions and consent.
        metadataAllowed=UserDefaults.standard.bool(forKey:"localMetadataConsentV1") || integration.installedEvents>0
        if metadataAllowed{connectEvents(Self.eventDirectory);refreshCatalog()}
        else{catalogNote="完成接入设置后读取本地项目与对话标题"}
        if startup.shouldEnableBroadcast(consent:metadataAllowed,configured:integration.complete,voicesReady:voicesReady){setMuted(false)}
        quotaTimer=Timer.scheduledTimer(withTimeInterval:60,repeats:true){[weak self]_ in self?.refreshQuota()}
        catalogTimer=Timer.scheduledTimer(withTimeInterval:60,repeats:true){[weak self]_ in self?.refreshCatalog()}
    }
    var needsInitialSetup:Bool {
        !metadataAllowed || !integration.complete || (UserDefaults.standard.bool(forKey:"integrationWizardStartedV1") && !UserDefaults.standard.bool(forKey:"integrationVerifiedV1"))
    }
    var integrationLabel:String {
        if !connected{return metadataAllowed ? "监听已断开" : "尚未配置接入"}
        return receivedCount>0 ? "已收到 Codex 事件" : "等待 Codex 事件"
    }
    func checkIntegration(){integration=RadioIntegration.inspect(root:codexHome,home:FileManager.default.homeDirectoryForCurrentUser)}
    func chooseCodexHome() {
        let panel=NSOpenPanel();panel.title="选择 Codex 数据目录（通常为 ~/.codex）";panel.canChooseDirectories=true;panel.canChooseFiles=false;panel.showsHiddenFiles=true;panel.allowsMultipleSelection=false;panel.directoryURL=codexHome.deletingLastPathComponent()
        guard panel.runModal() == .OK,let url=panel.url else{return}
        let selected=url.resolvingSymlinksInPath()
        guard selected != codexHome else{return}
        disconnectEvents();channels=[];latestNotice=nil;receivedCount=0;metadataAllowed=false;codexHome=selected
        UserDefaults.standard.set(selected.path,forKey:"codexHomeV1")
        UserDefaults.standard.set(false,forKey:"localMetadataConsentV1")
        UserDefaults.standard.set(false,forKey:"integrationVerifiedV1")
        checkIntegration();integrationMessage="已选择目录。确认下面的接入范围后继续。"
    }
    func installIntegration() {
        guard !integrationBusy else{return}
        guard !Bundle.main.bundleURL.path.hasPrefix("/Volumes/") && !Bundle.main.bundleURL.path.contains("/AppTranslocation/") else{integrationMessage="请先退出，将应用从 DMG 拖入应用程序文件夹，再从安装位置打开。";return}
        guard let helper=Bundle.main.resourceURL?.appendingPathComponent("../Helpers/CodexRadioHook").standardizedFileURL else{return}
        integrationBusy=true;let root=codexHome
        DispatchQueue.global(qos:.userInitiated).async{[weak self] in
            let result=Result{try RadioIntegration.install(root:root,home:FileManager.default.homeDirectoryForCurrentUser,helper:helper)}
            DispatchQueue.main.async {
                guard let me=self else{return};me.integrationBusy=false
                switch result {
                case .success(let count):
                    me.metadataAllowed=true;UserDefaults.standard.set(true,forKey:"localMetadataConsentV1");UserDefaults.standard.set(true,forKey:"integrationWizardStartedV1")
                    me.checkIntegration();me.connectEvents(Self.eventDirectory);me.refreshCatalog()
                    me.integrationMessage=count>0 ? "已添加 \(count) 项接入配置。下一步需在 Codex 中亲自审查并信任；当前尚未确认授权。" : "现有接入配置完整，未改动。请用新的本地对话事件验证连接。"
                case .failure(let error):me.integrationMessage=error.localizedDescription;me.checkIntegration()
                }
            }
        }
    }
    func setWeeklyQuotaAlarm(_ enabled:Bool) {
        weeklyQuotaAlarm=enabled;UserDefaults.standard.set(enabled,forKey:WeeklyQuotaAlertGate.enabledKey)
        if enabled{refreshQuota()}
        else{quotaGeneration=UUID();weeklyQuota=nil;quotaMessage="周额度报警已关闭";if queue.active?.status.isQuotaAlert == true{stopAll()}}
    }
    func refreshQuota() {
        guard weeklyQuotaAlarm,metadataAllowed,connected,!quotaBusy else{return}
        guard let executable=CodexQuotaClient.executable() else{weeklyQuota=nil;quotaMessage=CodexQuotaClient.Failure.unavailable.localizedDescription;return}
        quotaBusy=true
        let root=codexHome,token=quotaGeneration
        DispatchQueue.global(qos:.utility).async{[weak self] in
            let result=Result{try CodexQuotaClient.read(executable:executable,root:root)}
            DispatchQueue.main.async {
                guard let me=self else{return};me.quotaBusy=false
                guard me.quotaGeneration==token,me.weeklyQuotaAlarm,me.metadataAllowed,me.connected,me.codexHome==root else{return}
                switch result {
                case .success(let quota):
                    me.weeklyQuota=quota
                    guard let quota else{me.quotaMessage="暂无可用的 Codex 周额度数据";return}
                    let formatter=DateFormatter();formatter.dateFormat="M月d日 HH:mm"
                    me.quotaMessage="重置于 \(formatter.string(from:Date(timeIntervalSince1970:quota.resetsAt))) · 每分钟检查"
                    if let alarm=WeeklyQuotaAlertGate.observe(quota,scope:root.standardizedFileURL.path,canPlay:!me.muted && me.volume>0,defaults:UserDefaults.standard){me.enqueueQuotaAlarm(alarm)}
                case .failure(let error):me.weeklyQuota=nil;me.quotaMessage=error.localizedDescription
                }
            }
        }
    }
    func enqueueQuotaAlarm(_ alarm:WeeklyQuotaAlarm,audition:Bool=false) {
        guard !muted,volume>0 else{return}
        let event=RadioEvent(channel:"weekly-quota",status:alarm.status,origin:audition ? "试听" : "周额度",receivedAt:Date().timeIntervalSince1970)
        latestNotice=event
        if queue.offer(event,at:event.receivedAt){cancelAudio()}
        addLog((audition ? "试听 / " : "")+alarm.title)
        ensureTicker();pump()
    }
    func copyHooksReviewCommand() {
        let fm=FileManager.default
        let app=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.openai.codex")
        let candidates=[app?.appendingPathComponent("Contents/Resources/codex-cli/bin/codex"),app?.appendingPathComponent("Contents/Resources/codex"),URL(fileURLWithPath:"/opt/homebrew/bin/codex"),URL(fileURLWithPath:"/usr/local/bin/codex")].compactMap{$0}
        let cli=candidates.first{fm.isExecutableFile(atPath:$0.path)}?.path ?? "codex"
        let command="env CODEX_HOME="+RadioIntegration.quote(codexHome.path)+" "+RadioIntegration.quote(cli)+" -C "+RadioIntegration.quote(FileManager.default.homeDirectoryForCurrentUser.path)
        NSPasteboard.general.clearContents();NSPasteboard.general.setString(command,forType:.string)
        integrationMessage="已复制 CLI 启动命令。在终端粘贴运行，然后输入 /hooks 审查 Radio 的 12 项配置。此按钮不会自动运行或授予信任。"
    }
    func validateVoices(_ directory:URL)->Bool {
        CallsignCatalog.recordingFiles.allSatisfy{name in
            guard let f=try? AVAudioFile(forReading:directory.appendingPathComponent(name)) else{return false}
            let d=Double(f.length)/f.processingFormat.sampleRate;return d>=0.08 && d<=3
        }
    }
    var selectedChannel:FlightChannel?{channels.first{$0.id==selected}}
    var selectedName:String{selectedChannel?.callsign ?? "选择一个对话"}
    var groups:[RadioProject] {
        Dictionary(grouping:channels,by:{$0.projectID}).map{id,items in
            RadioProject(id:id,title:items[0].projectTitle,callsign:CallsignCatalog.words(for:items[0].callsignIndex).joined(separator:" "),channels:items.sorted{$0.number<$1.number})
        }.sorted{a,b in (a.channels.map(\.updatedAt).max() ?? 0)>(b.channels.map(\.updatedAt).max() ?? 0)}
    }
    func saveAssignments(){if let data=try? JSONEncoder().encode(projects){UserDefaults.standard.set(data,forKey:"projectRegistryV1")}}
    func changeProjectCallsign(_ project:String,to value:Int) {
        stopAll();projects.assign(project:project,to:value)
        for i in channels.indices{channels[i].callsignIndex=projects.register(project:channels[i].projectID,thread:channels[i].id).0}
        saveAssignments();phase="项目呼号已保存 · 对话编号保持不变"
    }
    func openSettings(_ tab:String="general"){settingsTab=tab;loginItems.refresh();onOpenSettings?()}
    func setAutoBroadcast(_ enabled:Bool){autoBroadcast=enabled;UserDefaults.standard.set(enabled,forKey:StartupPreferences.broadcastKey)}
    func setMenuBarAppearance(_ value:MenuBarAppearance) {
        menuBarAppearance=value;value.save(to:UserDefaults.standard);onChange?()
    }
    func setSoundPack(_ value:SoundPack) {
        guard value != soundPack else{return}
        stopAll();soundPack=value;value.save(to:UserDefaults.standard)
        now="已切换为\(value.title)声音包";phase="可逐项试听新的提示音"
    }
    func restoreBuiltIn(_ status:RadioStatus) {
        stopAll();customClips[status.rawValue]=nil
    }
    func changeNumber(_ id:String) {
        guard let channel=channels.first(where:{$0.id==id}) else{return}
        let input=(numberDrafts[id] ?? String(channel.number)).trimmingCharacters(in:.whitespacesAndNewlines)
        guard !input.isEmpty,input.utf8.allSatisfy({$0>=48 && $0<=57}),let number=Int(input),(0...9999).contains(number) else{settingsMessage="请输入 0–9999 的整数。";return}
        let other=channels.first{$0.projectID==channel.projectID && $0.id != id && $0.number==number}
        guard projects.assignNumber(project:channel.projectID,thread:id,to:number) else{return}
        stopAll()
        for i in channels.indices where channels[i].projectID==channel.projectID {
            channels[i].number=projects.register(project:channel.projectID,thread:channels[i].id).1
        }
        numberDrafts[id]=nil;if let other{numberDrafts[other.id]=nil}
        saveAssignments();settingsMessage=other==nil ? "已保存：\(channel.title) → \(CallsignCatalog.words(for:channel.callsignIndex).joined(separator:" ")) \(number)" : "已与“\(other!.title)”互换编号。"
    }
    func setCustomSound(_ status:RadioStatus,enabled:Bool) {
        stopAll();if enabled{customSounds.insert(status)}else{customSounds.remove(status)}
        queue.customSounds=customSounds
        UserDefaults.standard.set(customSounds.map(\.rawValue).sorted(),forKey:"customSoundsV1")
    }
    var displayNotice:RadioEvent?{queue.active ?? latestNotice}
    var noticeChannel:FlightChannel?{guard let e=displayNotice else{return nil};return channels.first{$0.id==e.channel}}
    var noticeCaption:String {
        guard let e=displayNotice else{return "等待新的实时提示"}
        if activeID==e.id{return "播报中"}
        if muted{return "已静音"}
        if !queue.accepts(e.status){return "当前模式已过滤"}
        if queue.pending.contains(where:{$0.event.id==e.id}){return "等待播报"}
        return "最近事件"
    }
    func refreshCatalog() {
        guard metadataAllowed,!catalogRefreshing else{return};catalogRefreshing=true
        let root=codexHome
        DispatchQueue.global(qos:.utility).async{[weak self] in
            let result=Result{try ConversationCatalog.read(root:root)}
            DispatchQueue.main.async{
                guard let me=self else{return};me.catalogRefreshing=false
                guard me.metadataAllowed,me.codexHome==root else{return}
                switch result {
                case .success(let records):me.applyCatalog(records)
                case .failure(let error):me.catalogNote=error.localizedDescription
                }
            }
        }
    }
    func applyCatalog(_ records:[CatalogThread]) {
        var old=Dictionary(channels.map{($0.id,$0)},uniquingKeysWith:{a,_ in a})
        var updated:[FlightChannel]=[]
        // Project order follows recent use; first-time numbering follows creation order,
        // then remains stable across title changes, refreshes and restarts.
        let grouped=Dictionary(grouping:records,by:{$0.projectID}).values.sorted{a,b in (a.map(\.updatedAt).max() ?? 0)>(b.map(\.updatedAt).max() ?? 0)}
        for group in grouped {
            for record in group.sorted(by:{$0.createdAt==$1.createdAt ? $0.id<$1.id : $0.createdAt<$1.createdAt}) {
                let assignment=projects.register(project:record.projectID,thread:record.id)
                var channel=old.removeValue(forKey:record.id) ?? FlightChannel(id:record.id,callsignIndex:assignment.0)
                channel.callsignIndex=assignment.0;channel.number=assignment.1
                channel.title=record.title;channel.projectID=record.projectID;channel.projectTitle=record.projectTitle
                channel.updatedAt=max(record.updatedAt,channel.activity.lastAt);channel.archived=record.archived
                channel.sessionLabel=String(record.id.suffix(8));updated.append(channel)
            }
        }
        // A just-created live conversation may reach the hook before metadata is committed.
        updated += old.values.filter{$0.activity.lastAt>Date().timeIntervalSince1970-ConversationCatalog.week}
        channels=updated
        if !channels.contains(where:{$0.id==selected}){selected=groups.first?.channels.first?.id ?? ""}
        saveAssignments()
        let f=DateFormatter();f.dateFormat="HH:mm:ss"
        catalogNote="最近 7 天 · \(groups.count) 个项目 / \(channels.count) 个对话 · \(f.string(from:Date())) 更新"
    }
    func addLog(_ text:String){let f=DateFormatter();f.dateFormat="HH:mm:ss";log.insert("\(f.string(from:Date()))  \(text)",at:0);if log.count>50{log.removeLast()}}
    func connectEvents(_ url:URL) {
        guard metadataAllowed else{openSettings("setup");return}
        stopAll();liveReader.connect(url);connected=true;connectionLabel="等待新的实时事件"
        refreshQuota()
        liveTimer?.invalidate();liveTimer=Timer.scheduledTimer(withTimeInterval:0.15,repeats:true){[weak self]_ in self?.receiveLive()}
        now=muted ? "实时监听已准备 · 当前静音" : "实时监听已准备 · 播报已启用"
    }
    func disconnectEvents(){quotaGeneration=UUID();weeklyQuota=nil;quotaMessage="额度监听已断开";stopAll();liveTimer?.invalidate();liveTimer=nil;liveReader.disconnect();connected=false;connectionLabel="实时监听已断开"}
    func receiveLive() {
        for e in liveReader.poll() {
            guard e.host=="local" else{continue}
            receivedCount += 1;connectionLabel="已收到 \(receivedCount) 个实时事件"
            UserDefaults.standard.set(true,forKey:"integrationVerifiedV1")
            // Every subagent event uses the parent session ID and the same callsign.
            if !channels.contains(where:{$0.id==e.session}) {
                let a=projects.register(project:"unassigned",thread:e.session)
                var c=FlightChannel(id:e.session,callsignIndex:a.0);c.number=a.1;c.title="新对话 · "+String(e.session.suffix(8));c.sessionLabel=String(e.session.suffix(8))
                channels.append(c);if selected.isEmpty{selected=e.session};saveAssignments();refreshCatalog()
            }
            guard let i=channels.firstIndex(where:{$0.id==e.session}) else{continue}
            channels[i].updatedAt=max(channels[i].updatedAt,e.receivedAt)
            let cue=channels[i].activity.receive(e)
            channels[i].lastMessage=channels[i].activity.detail
            if let cue{channels[i].status=cue;submit(channel:e.session,status:cue,eventID:e.id,origin:e.agent == nil ? "实时事件" : "子代理")}
        }
    }
    func setMuted(_ value: Bool) {
        guard value || voicesReady else{phase="缺少真人呼号录音；不会使用合成音替代";return}
        muted=value;queue.mute(value)
        if value { stopAll(); now="已静音 · 队列已清空" }
        else { now=connected ? "已启用 · 等待正式 hook" : "已启用 · 等待手动试听";phase="启用本身不发声" }
        onChange?()
    }
    func setMode(_ value: String) {
        guard ListeningMode(rawValue:value) != nil else{return}
        stopAll();mode=value;queue.mode=value;now="模式已切换"
        UserDefaults.standard.set(value,forKey:"listeningModeV2")
    }
    func setVolume(_ value: Double) { volume=StartupPreferences.normalizedVolume(value);UserDefaults.standard.set(volume,forKey:StartupPreferences.volumeKey);player?.volume=Float(volume) }
    func audition(_ status: RadioStatus) { submit(channel:selected,status:status,force:true,origin:"试听") }
    func submit(channel: String,status: RadioStatus,force: Bool=false,eventID:String=UUID().uuidString,origin:String="试听") {
        guard let index=channels.firstIndex(where:{$0.id==channel}),channels[index].enabled else{return}
        let e=RadioEvent(id:eventID,channel:channel,status:status,origin:origin,receivedAt:Date().timeIntervalSince1970)
        latestNotice=e
        let accepted=force || queue.accepts(status)
        guard !muted else {addLog("\(channels[index].callsign) / \(status.title) · 静音");return}
        if queue.offer(e,at:e.receivedAt,force:force) { cancelAudio();addLog("高优先级抢占") }
        addLog("\(channels[index].callsign) / \(status.title)\(accepted ? "" : " · 模式过滤")")
        ensureTicker();pump()
    }
    func ensureTicker() {
        guard ticker==nil else{return}
        ticker=Timer.scheduledTimer(withTimeInterval:0.05,repeats:true){[weak self]_ in self?.pump()}
    }
    func pump() {
        if let e=queue.next(at:Date().timeIntervalSince1970) { playRecorded(e) }
        pendingCount=queue.pending.count
        if queue.pending.isEmpty && queue.active==nil {ticker?.invalidate();ticker=nil}
    }
    func playRecorded(_ e:RadioEvent) {
        guard !muted else{queue.finished(e.id);return}
        let channel=channels.first(where:{$0.id==e.channel})
        guard e.status.isQuotaAlert || channel != nil else{queue.finished(e.id);return}
        generation=UUID();activeID=e.id;now=e.status.isQuotaAlert ? e.status.title : "\(channel!.callsign) · \(e.status.title)"
        do {
            guard let voices=voiceDirectory else{throw RecordedAudio.Failure.missingRecording}
            let data:Data
            if e.status.isQuotaAlert {
                guard let root=Bundle.main.resourceURL else{throw RecordedAudio.Failure.invalidAudio}
                let cue=try RecordedAudio.samples(.init(url:root.appendingPathComponent("Audio/"+SoundMap.clips(e.status)[0].file)))
                let reference=try RecordedAudio.samples(.init(url:voices.appendingPathComponent("alfa.wav")))
                data=RecordedAudio.wav(RecordedAudio.matchLevel(cue,to:reference))
            }else{
                let c=channel!
                var pieces=(CallsignCatalog.filenames(for:c.callsignIndex)+CallsignCatalog.numberFiles(c.number)).map{RecordedAudio.Piece(url:voices.appendingPathComponent($0),gap:RecordedAudio.callsignGap,isVoice:true)}
                if let custom=customClips[e.status.rawValue] {pieces.append(RecordedAudio.Piece(url:custom))}
                else {
                    guard let root=Bundle.main.resourceURL else{throw RecordedAudio.Failure.invalidAudio}
                    pieces += SoundMap.clips(e.status,pack:soundPack).map{RecordedAudio.Piece(url:root.appendingPathComponent("Audio/\($0.file)"),start:$0.start,duration:$0.duration,gap:$0.pause)}
                }
                data=try RecordedAudio.compose(pieces,matchCueLevel:true)
            }
            let p=try AVAudioPlayer(data:data);p.delegate=self;p.volume=Float(volume);p.numberOfLoops=0;player=p
            guard p.play() else{throw RecordedAudio.Failure.invalidAudio}
            phase=e.status.isQuotaAlert ? "周额度提醒 · 单次播放" : "真人录音 → \(customClips[e.status.rawValue]==nil ? soundPack.title+"声音包" : "个人音源") · 单一连续音轨"
            let token=generation
            let watchdog=DispatchWorkItem{[weak self] in guard let me=self,me.generation==token else{return};me.phase="音轨超时，已停止";me.finish(e.id,preserveMessage:true)}
            stageTask=watchdog;DispatchQueue.main.asyncAfter(deadline:.now()+p.duration+1,execute:watchdog)
        } catch {phase="真人录音或状态音缺失 / 无效；本次未播放";finish(e.id,preserveMessage:true)}
    }
    func audioPlayerDidFinishPlaying(_ p:AVAudioPlayer,successfully flag:Bool) {
        DispatchQueue.main.async{[weak self] in
            guard let me=self,me.player === p,let id=me.activeID else{return}
            if !flag {me.phase="音轨未完整播放"}
            me.finish(id,preserveMessage:!flag)
        }
    }
    func finish(_ id:String,preserveMessage:Bool=false) {
        guard activeID==id else{return}
        stageTask?.cancel();stageTask=nil;player?.stop();player=nil;activeID=nil;queue.finished(id)
        if !preserveMessage {phase="已播报 · 没有循环警报"}
        pump()
    }
    func cancelAudio() {
        generation=UUID();stageTask?.cancel();stageTask=nil;activeID=nil
        player?.stop();player=nil
    }
    func stopAll() {
        cancelAudio();queue.clear();pendingCount=0;ticker?.invalidate();ticker=nil;now="已停止播报";phase="待播队列已清空"
    }
    func importClip(_ status:RadioStatus) {
        let panel=NSOpenPanel();panel.title="为“\(status.title)”选择航空 / 游戏提示音";panel.allowedContentTypes=[.audio];panel.allowsMultipleSelection=false;panel.canChooseDirectories=false
        guard panel.runModal() == .OK,let url=panel.url else{return}
        // Only a user-chosen audio file; not executed and not uploaded.
        do {let file=try AVAudioFile(forReading:url);guard file.length>0 else{return};customClips[status.rawValue]=url;addLog("\(status.title) 已导入：\(url.lastPathComponent)")}
        catch{addLog("无法读取所选音频")}
    }
}

final class AppDelegate:NSObject,NSApplicationDelegate {
    let store=RadioStore()
    var item:NSStatusItem!
    let popover=NSPopover()
    var settingsWindow:NSWindow?
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.accessory)
        item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        if let button=item.button {button.image=NSImage(systemSymbolName:"antenna.radiowaves.left.and.right",accessibilityDescription:"Codex Radio");button.imagePosition = .imageLeft;button.setAccessibilityLabel("Codex Radio");button.target=self;button.action=#selector(toggle)}
        updateMenuBar()
        popover.contentSize=NSSize(width:400,height:560);popover.behavior = .transient
        popover.contentViewController=NSHostingController(rootView:RadioPanel(store:store))
        store.onOpenSettings={[weak self] in self?.showSettings()}
        store.onChange={[weak self] in self?.updateMenuBar()}
        let atLogin=NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword:AEKeyword(keyAELaunchedAsLogInItem)) != nil
        DispatchQueue.main.async{[weak self] in
            guard let me=self else{return}
            if me.store.needsInitialSetup{me.store.openSettings("setup")}else if !atLogin{me.toggle()}
        }
    }
    func applicationDidBecomeActive(_ notification:Notification){store.loginItems.refresh()}
    func updateMenuBar() {
        item.button?.title=store.menuBarAppearance.statusItemTitle
        item.button?.toolTip=store.muted ? "Codex Radio · 静音 · 点击展开" : "Codex Radio · 播报中 · 点击展开"
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {
        if !flag{toggle()};return true
    }
    func showSettings() {
        popover.performClose(nil);store.refreshCatalog()
        if settingsWindow==nil {
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:960,height:740),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            window.title="Codex Radio设置";window.isReleasedWhenClosed=false;window.minSize=NSSize(width:860,height:640)
            window.contentViewController=NSHostingController(rootView:RadioSettings(store:store));window.center();settingsWindow=window
        }
        settingsWindow?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    @objc func toggle(){guard let b=item.button else{return};if popover.isShown{popover.performClose(nil)}else{store.refreshCatalog();popover.show(relativeTo:b.bounds,of:b,preferredEdge:.minY);NSApp.activate(ignoringOtherApps:true)}}
    func applicationWillTerminate(_ notification:Notification){store.quotaTimer?.invalidate();store.disconnectEvents()}
}

@main struct CodexRadio {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {runDomainTests();return}
        if CommandLine.arguments.contains("--quota-check") {
            guard let executable=CodexQuotaClient.executable() else{fputs("Codex unavailable\n",stderr);exit(1)}
            let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["CODEX_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path)
            do{if let quota=try CodexQuotaClient.read(executable:executable,root:root){print("Weekly remaining: \(quota.display); reset: \(quota.resetsAt)")}else{print("Weekly quota unavailable")}}
            catch{fputs("Quota check failed: \(error.localizedDescription)\n",stderr);exit(1)}
            return
        }
        if CommandLine.arguments.contains("--catalog-check") {
            do {let records=try ConversationCatalog.read();print("Recent 7 days: \(records.count) conversations, \(Set(records.map(\.projectID)).count) project groups");for r in records{print("\(r.projectTitle) | \(r.title)")}}catch{fputs("Catalog failed: \(error.localizedDescription)\n",stderr);exit(1)}
            return
        }
        let app=NSApplication.shared,delegate=AppDelegate();app.delegate=delegate
        withExtendedLifetime(delegate){app.run()}
    }
}
