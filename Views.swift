import SwiftUI
import AppKit

struct RadioPanel:View {
    @ObservedObject var store:RadioStore
    var body:some View {
        VStack(alignment:.leading,spacing:13) {
            header
            currentNotice
            playbackControls
            VStack(alignment:.leading,spacing:9) {
                HStack {
                    panelLabel("MONITOR / 收听模式")
                    Spacer()
                    Menu {
                        ForEach(SoundPack.allCases){pack in Button((store.soundPack==pack ? "✓ " : "")+pack.title){store.setSoundPack(pack)}}
                    }label:{Text(store.soundPack.title).font(.system(size:11,weight:.medium)).foregroundColor(FlightDeck.cyan)}.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("选择声音包")
                }
                FlightModeSelector(store:store)
                Text(modeNote).font(.system(size:10)).foregroundColor(FlightDeck.muted)
            }
            Rectangle().fill(FlightDeck.line).frame(height:1)
            recentActivity
        }.padding(18).frame(width:400,height:560).background(FlightDeck.background).foregroundColor(FlightDeck.text).preferredColorScheme(.dark)
    }
    var header:some View {
        HStack(spacing:10) {
            Image(systemName:"antenna.radiowaves.left.and.right").font(.system(size:21)).foregroundColor(FlightDeck.cyan)
            VStack(alignment:.leading,spacing:4) {
                Text("Codex Radio").font(.system(size:16,weight:.semibold))
                panelLabel("COMMUNICATION PANEL")
            }
            Spacer()
            Button{store.openSettings()}label:{Image(systemName:"slider.horizontal.3").frame(width:14,height:15)}.buttonStyle(FlightButtonStyle()).help("打开设置").accessibilityLabel("打开Codex Radio设置")
            Menu {
                Button("接入与权限…"){store.checkIntegration();store.openSettings("setup")}
                Button(store.connected ? "断开监听" : "重新连接"){if store.connected{store.disconnectEvents()}else{store.connectEvents(RadioStore.eventDirectory)}}
                Divider();Button("退出 Codex Radio"){store.stopAll();NSApp.terminate(nil)}
            }label:{Image(systemName:"ellipsis").frame(width:15,height:24)}.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("更多操作")
        }
    }
    var currentNotice:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                HStack(spacing:6){Circle().fill(store.connected && store.receivedCount>0 ? FlightDeck.green : FlightDeck.amber).frame(width:5,height:5);Text(store.integrationLabel).font(.system(size:10))}.foregroundColor(FlightDeck.muted)
                Spacer();Text(store.activeID != nil ? "PLAY" : "STBY").font(.system(size:10,weight:.semibold,design:.monospaced)).foregroundColor(store.activeID != nil ? FlightDeck.green : FlightDeck.muted)
            }
            if let event=store.displayNotice,let channel=store.noticeChannel {
                HStack(alignment:.firstTextBaseline,spacing:10) {
                    Text(channel.callsign).font(.system(size:26,weight:.medium,design:.monospaced)).foregroundColor(FlightDeck.cyan).lineLimit(1).minimumScaleFactor(0.65)
                    Spacer(minLength:0);Text(event.status.title).font(.system(size:12,weight:.medium)).foregroundColor(event.status == .blocked || event.status == .waiting ? FlightDeck.amber : FlightDeck.green)
                }
                Text(channel.title).font(.system(size:11)).foregroundColor(FlightDeck.muted).lineLimit(1)
            }else{
                Text("RADIO READY").font(.system(size:24,weight:.medium,design:.monospaced)).foregroundColor(FlightDeck.cyan)
                Text(store.muted ? "当前静音 · 等待新的对话活动" : "等待新的对话活动").font(.system(size:11)).foregroundColor(FlightDeck.muted)
            }
            HStack{panelLabel(store.activeID == nil ? "LAST / 最近提示" : "ACTIVE / 正在播报");Spacer();Text(store.pendingCount>0 ? "待播 \(store.pendingCount)" : store.noticeCaption).font(.system(size:10)).foregroundColor(FlightDeck.muted)}
        }.padding(14).frame(maxWidth:.infinity,minHeight:129,alignment:.leading).background(FlightDeck.inset)
            .clipShape(RoundedRectangle(cornerRadius:6)).overlay(RoundedRectangle(cornerRadius:6).stroke(FlightDeck.cyan.opacity(0.22),lineWidth:1))
    }
    var playbackControls:some View {
        VStack(spacing:12) {
            HStack(spacing:10) {
                VStack(alignment:.leading,spacing:4){panelLabel("AUDIO / 播报");Text(store.muted ? "声音已静音" : "正在收听").font(.system(size:12)).foregroundColor(store.muted ? FlightDeck.muted : FlightDeck.green)}
                Spacer()
                Button{store.stopAll()}label:{HStack(spacing:5){Image(systemName:"stop.fill").font(.system(size:9));Text("STOP").font(.system(size:10,weight:.medium,design:.monospaced))}.frame(height:24)}.buttonStyle(FlightButtonStyle(tint:FlightDeck.amber)).disabled(store.activeID==nil && store.pendingCount==0).accessibilityLabel("停止当前播报")
                FlightSwitch(title:"播报声音",isOn:Binding(get:{!store.muted},set:{store.setMuted(!$0)})).disabled(!store.voicesReady)
            }
            HStack(spacing:10){Image(systemName:"speaker.wave.2").font(.system(size:11)).foregroundColor(FlightDeck.muted);Slider(value:Binding(get:{store.volume},set:{store.setVolume($0)}),in:0...0.5).tint(FlightDeck.cyan).accessibilityLabel("播报音量");Text(String(format:"%02d",Int((store.volume*100).rounded()))+" %").font(.system(size:12,design:.monospaced)).foregroundColor(FlightDeck.cyan).frame(width:42,alignment:.trailing)}
            if !store.voicesReady{Text("呼号录音不可用，请重新安装应用。").font(.system(size:10)).foregroundColor(FlightDeck.amber)}
        }
    }
    var recentActivity:some View {
        VStack(alignment:.leading,spacing:9) {
            HStack{panelLabel("EVENT LOG / 最近活动");Spacer();if !store.log.isEmpty{Button("清空"){store.log=[]}.font(.system(size:10)).buttonStyle(.plain).foregroundColor(FlightDeck.muted)}}
            ScrollView {
                VStack(alignment:.leading,spacing:8) {
                    if store.log.isEmpty{Text("等待新的实时事件").font(.system(size:11)).foregroundColor(FlightDeck.muted).padding(.top,5)}
                    ForEach(Array(store.log.enumerated()),id:\.offset){_,entry in HStack(alignment:.top,spacing:12){Text(String(entry.prefix(8))).font(.system(size:10,design:.monospaced)).foregroundColor(FlightDeck.muted);Text(String(entry.dropFirst(10))).font(.system(size:11)).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)}}
                }.frame(maxWidth:.infinity,alignment:.leading)
            }.frame(maxHeight:.infinity)
        }
    }
    func panelLabel(_ text:String)->some View{Text(text).font(.system(size:9,weight:.medium,design:.monospaced)).tracking(0.6).foregroundColor(FlightDeck.muted)}
    var modeNote:String {
        switch store.mode{case "detail":return "所有状态依次播报";case "custom":return "收听 \(store.customSounds.count) 类提示 · 在设置中调整";default:return "只听收尾、等待确认、停止与报错"}
    }
}

struct RadioSettings:View {
    @ObservedObject var store:RadioStore
    @State private var expandedProjects=Set<String>()
    let pages=[("general","通用","SYSTEM","switch.2"),("sounds","声音与模式","AUDIO","waveform"),("callsigns","呼号分配","CALLSIGN","number"),("setup","接入与权限","CONNECTION","cable.connector")]
    var pageTitle:String{pages.first{$0.0==store.settingsTab}?.1 ?? "通用"}
    var pageCode:String{pages.first{$0.0==store.settingsTab}?.2 ?? "SYSTEM"}
    var pageNote:String {
        switch store.settingsTab{case "sounds":return "选择声音包，安排每一类提示。";case "callsigns":return "按项目分配字母呼号，按对话分配数字。";case "setup":return "连接本机 Codex，确认授权与实时事件。";default:return "管理启动方式、播报输出与菜单栏外观。"}
    }
    var body:some View {
        HStack(spacing:0) {
            sidebar.frame(width:185)
            Rectangle().fill(FlightDeck.line).frame(width:1)
            VStack(alignment:.leading,spacing:18) {
                HStack(alignment:.top) {
                    VStack(alignment:.leading,spacing:7){Text(pageCode).font(.system(size:10,weight:.medium,design:.monospaced)).tracking(2).foregroundColor(FlightDeck.cyan);Text(pageTitle).font(.system(size:24,weight:.semibold));Text(pageNote).font(.system(size:12)).foregroundColor(FlightDeck.muted)}
                    Spacer();Text("RADIO / 01").font(.system(size:10,design:.monospaced)).foregroundColor(FlightDeck.muted).padding(.top,4)
                }
                Rectangle().fill(FlightDeck.line).frame(height:1)
                Group {
                    switch store.settingsTab{case "sounds":sounds;case "callsigns":callsigns;case "setup":setup;default:general}
                }.id(store.settingsTab).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
                HStack{Circle().fill(FlightDeck.green).frame(width:4,height:4);Text("设置即时保存在本机").font(.system(size:10));Spacer();Text("CODEX RADIO  0.11.3").font(.system(size:9,design:.monospaced)).tracking(1)}.foregroundColor(FlightDeck.muted)
            }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity)
        }.frame(minWidth:860,minHeight:610).background(FlightDeck.background).foregroundColor(FlightDeck.text).preferredColorScheme(.dark).buttonStyle(FlightButtonStyle())
    }
    var sidebar:some View {
        VStack(alignment:.leading,spacing:24) {
            VStack(alignment:.leading,spacing:9){Image(systemName:"antenna.radiowaves.left.and.right").font(.system(size:26)).foregroundColor(FlightDeck.cyan);Text("Codex Radio").font(.system(size:19,weight:.semibold));Text("CONTROL PANEL").font(.system(size:9,design:.monospaced)).tracking(1.5).foregroundColor(FlightDeck.muted)}.padding(.top,8)
            VStack(spacing:8) {
                ForEach(pages,id:\.0){page in
                    Button{store.settingsTab=page.0;if page.0=="setup"{store.checkIntegration()};store.loginItems.refresh()}label:{
                        HStack(spacing:10){Image(systemName:page.3).font(.system(size:14)).frame(width:18);VStack(alignment:.leading,spacing:5){Text(page.1).font(.system(size:12,weight:.medium));Text(page.2).font(.system(size:8,design:.monospaced)).tracking(0.7)};Spacer(minLength:0)}.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,5)
                    }.buttonStyle(FlightButtonStyle(selected:store.settingsTab==page.0)).accessibilityLabel("设置页面："+page.1).accessibilityValue(store.settingsTab==page.0 ? "已选择" : "未选择")
                }
            }
            Spacer()
            VStack(alignment:.leading,spacing:8){Text("LOCAL LINK").font(.system(size:9,design:.monospaced)).tracking(1).foregroundColor(FlightDeck.muted);HStack(spacing:6){Circle().fill(store.receivedCount>0 && store.connected ? FlightDeck.green : FlightDeck.amber).frame(width:5,height:5);Text(store.integrationLabel).font(.system(size:10)).foregroundColor(FlightDeck.muted)}}
        }.padding(18).frame(maxHeight:.infinity).background(FlightDeck.inset.opacity(0.55))
    }
    var general:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                HStack(spacing:10){FlightReadout(title:"LINK / 接入",value:store.receivedCount>0 && store.connected ? "LIVE" : "STANDBY",tint:store.receivedCount>0 && store.connected ? FlightDeck.green : FlightDeck.amber);FlightReadout(title:"AUDIO / 播报",value:store.muted ? "MUTED" : "ON",tint:store.muted ? FlightDeck.muted : FlightDeck.green);FlightReadout(title:"PACK / 声音包",value:store.soundPack.displayCode)}
                FlightSection("播报输出",code:"OUTPUT") {
                    HStack{VStack(alignment:.leading,spacing:5){Text("当前播报开关").font(.system(size:13,weight:.medium));Text("静音时仍接收状态；启用后只播报新事件。").font(.system(size:11)).foregroundColor(FlightDeck.muted)};Spacer();FlightSwitch(title:"播报声音",isOn:Binding(get:{!store.muted},set:{store.setMuted(!$0)})).disabled(!store.voicesReady)}
                    HStack(spacing:12){Text("音量").font(.system(size:12));Slider(value:Binding(get:{store.volume},set:{store.setVolume($0)}),in:0...0.5).tint(FlightDeck.cyan).accessibilityLabel("播报音量");Text(String(format:"%02d %%",Int((store.volume*100).rounded()))).font(.system(size:15,design:.monospaced)).foregroundColor(FlightDeck.cyan).frame(width:52,alignment:.trailing)}
                    Text("音量会保存，自动播报使用同一音量。").font(.system(size:10)).foregroundColor(FlightDeck.muted)
                }
                StartupSettings(store:store,login:store.loginItems)
                FlightSection("菜单栏外观",code:"DISPLAY") {
                    HStack(spacing:10){ForEach(MenuBarAppearance.allCases,id:\.rawValue){appearance in Button{store.setMenuBarAppearance(appearance)}label:{HStack(spacing:8){Image(systemName:"antenna.radiowaves.left.and.right");Text(appearance.title)}.frame(maxWidth:.infinity)}.buttonStyle(FlightButtonStyle(selected:store.menuBarAppearance==appearance)).accessibilityLabel("菜单栏："+appearance.title).accessibilityValue(store.menuBarAppearance==appearance ? "已选择" : "未选择")}}
                }
            }.padding(.bottom,3)
        }
    }
    var sounds:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                FlightSection("声音包",code:"SOUND PACK") {
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:170),spacing:12)],spacing:12) {
                        ForEach(SoundPack.allCases){pack in
                            Button{store.setSoundPack(pack)}label:{
                                VStack(alignment:.leading,spacing:8){
                                    HStack{Text(pack.displayCode).font(.system(size:16,weight:.semibold,design:.monospaced));Spacer();Circle().fill(store.soundPack==pack ? FlightDeck.cyan : FlightDeck.muted.opacity(0.2)).frame(width:5,height:5)}
                                    Text(pack.vehicle).font(.system(size:11))
                                }.padding(.vertical,5).frame(maxWidth:.infinity,alignment:.leading)
                            }.buttonStyle(FlightButtonStyle(selected:store.soundPack==pack)).accessibilityLabel("声音包："+pack.title).accessibilityValue(store.soundPack==pack ? "已选择" : "未选择")
                        }
                    }
                    Text(store.soundPack.sourceNote).font(.system(size:10)).foregroundColor(FlightDeck.muted)
                }
                FlightSection("收听模式",code:"MONITOR") {
                    FlightModeSelector(store:store)
                    Text(store.mode=="focus" ? "只听本轮收尾、等待确认、停止和报错。" : store.mode=="detail" ? "所有状态按顺序播报，包含上下文压缩。" : "只播报下方开启的类别；压缩提示默认开启。").font(.system(size:11)).foregroundColor(FlightDeck.muted)
                }
                FlightSection("状态声音",code:"EVENTS") {
                    HStack(spacing:10){Text("试听呼号").font(.system(size:11)).foregroundColor(FlightDeck.muted);Picker("试听呼号",selection:$store.selected){if store.channels.isEmpty{Text("尚无本地对话").tag("")};ForEach(store.channels){c in Text(c.callsign+" · "+c.title).tag(c.id)}}.labelsHidden().frame(maxWidth:330);Spacer();if store.muted{Button("启用播报"){store.setMuted(false)}.disabled(!store.voicesReady).help("启用当前声音后可试听，也会播报新的实时事件")}}
                    if store.muted{Text("当前静音，启用播报后可试听。").font(.system(size:10)).foregroundColor(FlightDeck.amber)}
                    ForEach(Array(ListeningMode.availableSounds.enumerated()),id:\.element.id){index,status in
                        soundRow(status,index:index)
                        if index<ListeningMode.availableSounds.count-1{Divider().overlay(FlightDeck.line)}
                    }
                    Text("提示音自动匹配呼号电平；每次播放一遍。个人音源优先，仅当前运行有效。").font(.system(size:10)).foregroundColor(FlightDeck.muted)
                }
            }.padding(.bottom,3)
        }
    }
    func soundRow(_ status:RadioStatus,index:Int)->some View {
        HStack(spacing:12) {
            Text(String(format:"%02d",index+1)).font(.system(size:11,design:.monospaced)).foregroundColor(FlightDeck.muted).frame(width:20)
            VStack(alignment:.leading,spacing:5){Text(status.title).font(.system(size:12,weight:.medium));Text(store.customClips[status.rawValue]==nil ? SoundMap.description(status,pack:store.soundPack) : "个人音源").font(.system(size:10)).foregroundColor(FlightDeck.muted)}.frame(maxWidth:.infinity,alignment:.leading)
            if store.mode=="custom"{FlightSwitch(title:"自定义播报："+status.title,isOn:Binding(get:{store.customSounds.contains(status)},set:{store.setCustomSound(status,enabled:$0)}))}
            else{Text(store.mode=="detail" || ListeningMode.focusSounds.contains(status) ? "播报" : "过滤").font(.system(size:10)).foregroundColor(store.mode=="detail" || ListeningMode.focusSounds.contains(status) ? FlightDeck.green : FlightDeck.muted).frame(width:42)}
            Button{store.audition(status)}label:{Image(systemName:"play.fill").font(.system(size:10)).frame(width:12,height:14)}.disabled(store.muted || store.selected.isEmpty || !store.voicesReady).accessibilityLabel("试听"+store.soundPack.title+status.title)
            Menu {Button("导入个人音源…"){store.importClip(status)};if store.customClips[status.rawValue] != nil{Button("还原内置音效"){store.restoreBuiltIn(status)}}}label:{Image(systemName:"ellipsis").frame(width:16,height:20)}.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel(status.title+"音源选项")
        }
    }
    var filteredGroups:[RadioProject] {
        let search=store.search.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !search.isEmpty else{return store.groups}
        return store.groups.compactMap{group in let rows=group.channels.filter{group.title.localizedCaseInsensitiveContains(search) || $0.title.localizedCaseInsensitiveContains(search) || $0.callsign.localizedCaseInsensitiveContains(search)};return rows.isEmpty ? nil : RadioProject(id:group.id,title:group.title,callsign:group.callsign,channels:rows)}
    }
    var callsigns:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:12){TextField("搜索项目、对话或呼号",text:$store.search).textFieldStyle(.roundedBorder);Button(store.catalogRefreshing ? "刷新中" : "刷新"){store.refreshCatalog()}.disabled(store.catalogRefreshing)}
            Text(store.catalogNote).font(.system(size:10)).foregroundColor(FlightDeck.muted)
            ScrollView {
                LazyVStack(alignment:.leading,spacing:12){ForEach(filteredGroups){project in projectSection(project)};if filteredGroups.isEmpty{Text("没有匹配的本地对话").font(.system(size:12)).foregroundColor(FlightDeck.muted).padding(20)}}
            }
            Text(store.settingsMessage).font(.system(size:11)).foregroundColor(FlightDeck.cyan).lineLimit(2)
            Text("展开项目编辑对话编号 · 0–9999 · 同项目重号时互换 · 子代理共用父对话呼号").font(.system(size:10)).foregroundColor(FlightDeck.muted)
        }
    }
    func projectSection(_ project:RadioProject)->some View {
        let expanded=expandedProjects.contains(project.id) || !store.search.isEmpty
        return VStack(alignment:.leading,spacing:12) {
            HStack(spacing:12) {
                Button{if expandedProjects.contains(project.id){expandedProjects.remove(project.id)}else{expandedProjects.insert(project.id)}}label:{HStack(spacing:10){Image(systemName:expanded ? "chevron.down" : "chevron.right").font(.system(size:10));VStack(alignment:.leading,spacing:5){Text(project.title).font(.system(size:13,weight:.medium)).lineLimit(1);Text("\(project.channels.count) 个对话").font(.system(size:10)).foregroundColor(FlightDeck.muted)}}.frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain).accessibilityLabel((expanded ? "收起" : "展开")+project.title)
                Menu {ForEach(0..<max(26,store.projects.projectKeys.count+1),id:\.self){n in Button(CallsignCatalog.words(for:n).joined(separator:" ")){store.changeProjectCallsign(project.id,to:n)}}}label:{Text(project.callsign).font(.system(size:14,weight:.medium,design:.monospaced)).foregroundColor(FlightDeck.cyan)}.menuStyle(.borderlessButton).fixedSize().accessibilityLabel(project.title+" 项目呼号")
            }
            if expanded{Divider().overlay(FlightDeck.line);ForEach(project.channels){channel in numberRow(channel)}}
        }.padding(16).background(FlightDeck.panel.opacity(0.75)).clipShape(RoundedRectangle(cornerRadius:6)).overlay(RoundedRectangle(cornerRadius:6).stroke(FlightDeck.line,lineWidth:1))
    }
    func numberRow(_ c:FlightChannel)->some View {
        HStack(spacing:10) {
            VStack(alignment:.leading,spacing:4){Text(c.title).font(.system(size:12)).lineLimit(2);Text(c.activity.state.title+(c.archived ? " · 已归档" : "")).font(.system(size:10)).foregroundColor(FlightDeck.muted)}.frame(maxWidth:.infinity,alignment:.leading)
            Text(c.callsign).font(.system(size:11,design:.monospaced)).foregroundColor(FlightDeck.cyan).lineLimit(1).frame(width:98,alignment:.trailing)
            TextField("编号",text:Binding(get:{store.numberDrafts[c.id] ?? String(c.number)},set:{store.numberDrafts[c.id]=$0})).textFieldStyle(.roundedBorder).frame(width:54).multilineTextAlignment(.center).onSubmit{store.changeNumber(c.id)}.accessibilityLabel(c.title+" 对话编号")
            Button("保存"){store.changeNumber(c.id)}.accessibilityLabel("保存 "+c.title+" 编号")
        }.padding(.vertical,5)
    }
    var setup:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                HStack(spacing:10){FlightReadout(title:"CONFIG / 接入配置",value:"\(store.integration.installedEvents) / 12",tint:store.integration.complete ? FlightDeck.green : FlightDeck.amber);FlightReadout(title:"EVENTS / 本次实时事件",value:String(store.receivedCount),tint:store.receivedCount>0 ? FlightDeck.green : FlightDeck.muted)}
                FlightSection("允许本地接入",code:"01 / CONNECT") {
                    Text("先安装并登录 Codex，再确认这台 Mac 的数据目录。").font(.system(size:12))
                    Text(store.codexHome.path).font(.system(size:11,design:.monospaced)).foregroundColor(FlightDeck.cyan).textSelection(.enabled).lineLimit(3)
                    HStack{Button("选择目录…"){store.chooseCodexHome()}.disabled(store.integrationBusy);Button("重新检查"){store.checkIntegration()}.disabled(store.integrationBusy);Spacer()}
                    if let issue=store.integration.issue{Text(issue).font(.system(size:11)).foregroundColor(FlightDeck.amber)}
                    Text("允许后读取本地项目与对话标题，向 hooks.json 追加缺少的监听；保留并备份原有 Hooks。").font(.system(size:11)).foregroundColor(FlightDeck.muted)
                    Button(store.integrationBusy ? "正在配置…" : store.integration.complete ? "允许读取并检查接入" : "允许读取并安装接入"){store.installIntegration()}.buttonStyle(FlightButtonStyle(selected:true)).disabled(store.integrationBusy || !store.integration.folderExists || store.integration.issue != nil)
                    if !store.integrationMessage.isEmpty{Text(store.integrationMessage).font(.system(size:11)).foregroundColor(FlightDeck.cyan).textSelection(.enabled)}
                }
                FlightSection("在 Codex 中审查信任",code:"02 / AUTHORIZE") {
                    Text("安装配置不等于授权。在 Codex CLI 输入 /hooks，亲自审查并信任 Radio 的 12 项监听，再重新打开本地对话。").font(.system(size:12))
                    HStack{Button("复制 CLI 命令"){store.copyHooksReviewCommand()}.disabled(!store.integration.complete);Button("查看接入文件"){NSWorkspace.shared.activateFileViewerSelecting([store.codexHome.appendingPathComponent("hooks.json")])}.disabled(store.integration.installedEvents==0);Spacer()}
                    Link("Codex 官方审查说明 ↗",destination:URL(string:"https://learn.chatgpt.com/docs/hooks")!).font(.system(size:11)).foregroundColor(FlightDeck.cyan)
                    Text("Radio 不修改信任记录或放宽权限。管理员禁用 Hooks 时需联系管理员。").font(.system(size:11)).foregroundColor(FlightDeck.muted)
                }
                FlightSection("确认真实事件",code:"03 / VERIFY") {
                    Text(store.receivedCount>0 ? "本次启动已收到 \(store.receivedCount) 个实时事件。" : "新建或重新打开本地对话并发送一句话，收到真实事件后确认接入。").font(.system(size:12)).foregroundColor(store.receivedCount>0 ? FlightDeck.green : FlightDeck.text)
                    Text("手动试听不计入验证。云端、远程对话和部分托管工具不保证覆盖。").font(.system(size:11)).foregroundColor(FlightDeck.muted)
                    Button("前往播报与启动设置"){store.settingsTab="general"}
                }
                Text("无需 API Key、辅助功能、屏幕录制、麦克风或完整磁盘访问。事件只保存必要标识，不保存聊天正文。全新接入无需 Python；完整旧接入沿用原程序。").font(.system(size:10)).foregroundColor(FlightDeck.muted)
            }.padding(.bottom,3)
        }
    }
}
