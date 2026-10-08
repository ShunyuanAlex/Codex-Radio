import Foundation
import AVFoundation
import SQLite3

func runDomainTests() {
    var passed=0
    func check(_ name:String,_ body:()->Bool){guard body() else{fputs("FAIL \(name)\n",stderr);exit(1)};passed += 1;print("PASS \(name)")}
    func e(_ channel:String="01",_ status:RadioStatus = .complete,_ time:Double=0)->RadioEvent{RadioEvent(channel:channel,status:status,receivedAt:time)}
    check("默认静音，没有事件进入队列"){let q=RadioQueue();q.offer(e(),at:0);return q.next(at:1)==nil}
    check("300毫秒合并同一对话的普通工具事件"){let q=RadioQueue();q.muted=false;q.mode="custom";q.customSounds=Set(RadioStatus.allCases);q.offer(e("01",.testing),at:0);q.offer(e("01",.success),at:0.1);return q.next(at:0.29)==nil && q.next(at:0.3)?.status == .success}
    check("普通播报每滚动秒最多两次"){let q=RadioQueue();q.muted=false;q.mode="custom";q.customSounds=Set(RadioStatus.allCases);var starts:[Double]=[];for i in 0..<1000 {let t=Double(i)*0.01;if i%10==0{q.offer(e(String(i%4),.success,t),at:t)};if let x=q.next(at:t){starts.append(t);q.finished(x.id)}};return starts.count>2 && starts.allSatisfy{a in starts.filter{$0>=a && $0<a+0.999999}.count<=2}}
    check("高优先级抢占，不同时启动两个前景"){let q=RadioQueue();q.muted=false;q.mode="custom";q.customSounds=Set(RadioStatus.allCases);q.offer(e(),at:0);_ = q.next(at:0.3);let x=e("04",.blocked,0.4);return q.offer(x,at:0.4) && q.next(at:0.4)?.id==x.id && q.next(at:0.5)==nil}
    check("静音与停止清空队列，不补播"){let q=RadioQueue();q.muted=false;q.offer(e(),at:0);q.mute(true);q.mute(false);return q.next(at:1)==nil}
    check("取消后旧完成回调不清除新事件"){let q=RadioQueue();q.muted=false;q.offer(e("01",.waiting),at:0);let first=q.next(at:0)!;q.offer(e("02",.blocked),at:0.1);let second=q.next(at:0.1)!;q.finished(first.id);return q.active?.id==second.id}
    check("事件ID去重"){let q=RadioQueue();q.muted=false;let x=e();q.offer(x,at:0);q.offer(x,at:0.1);return q.pending.count==1}
    check("未知业务结果使用独立返回音，不当作成功音"){!SoundMap.clips(.unknown).isEmpty && SoundMap.clips(.unknown) != SoundMap.clips(.success)}
    check("全部状态有明确中文标签"){RadioStatus.allCases.count==15 && RadioStatus.allCases.allSatisfy{!$0.title.isEmpty}}
    check("固定已有 NATO 呼号，不接受自定义文字"){FlightChannel.defaults.map(\.callsign)==["Alpha","Bravo","Charlie","Delta"] && Set(CallsignCatalog.names).count==26}
    check("超过四个或26个项目仍有唯一呼号"){Set((0..<2000).map{CallsignCatalog.words(for:$0).joined(separator:" ")}).count==2000 && CallsignCatalog.words(for:26)==["Alpha","Alpha"]}
    check("呼号、数字与状态音零额外间隔，没有末尾多余停顿"){let x=RecordedAudio.stitch([([0.1,0.2],RecordedAudio.callsignGap),([0.3],0.2)]);return x==[0.1,0.2,0.3]}
    check("12ms人声叠化缩短接缝且不增加峰值或引入突跳") {
        let a=[Float](repeating:0.8,count:960),b=[Float](repeating:-0.8,count:960)
        let joined=RecordedAudio.stitch([(a,0),(b,0)],overlaps:[0,RecordedAudio.voiceCrossfade])
        return joined.count==1632 && joined.prefix(672).allSatisfy{$0==0.8} && joined.suffix(672).allSatisfy{$0 == -0.8} && joined.allSatisfy{abs($0)<=0.8} && zip(joined,joined.dropFirst()).allSatisfy{abs($0-$1)<0.006}
    }
    check("叠化不覆盖指定停顿，过短片段保留一半以上原样") {
        let a=[Float](repeating:0.4,count:40),b=[Float](repeating:0.6,count:40),c=[Float](repeating:0.8,count:40)
        let gap=RecordedAudio.stitch([(a,0.01),(b,0)],overlaps:[0,1])
        let short=RecordedAudio.stitch([(a,0),(b,0),(c,0)],overlaps:[0,1,1])
        return gap.count==320 && gap[40..<280].allSatisfy{$0==0} && short.count==80 && short.first==0.4 && short.last==0.8
    }
    check("单音轨PCM编码长度和格式正确"){let d=RecordedAudio.wav([0,0.25,-0.25]);return d.count==50 && String(data:d.prefix(4),encoding:.ascii)=="RIFF" && String(data:d[8..<12],encoding:.ascii)=="WAVE"}
    check("缺少录音直接失败，没有合成或状态音替代"){do{_ = try RecordedAudio.compose([]);return false}catch{return true}}
    check("所有声音包八类音效可解码、无削波、时长受控且波形不同") {
        guard let root=Bundle.main.resourceURL else{return false}
        var tracks=Set<Data>()
        for pack in SoundPack.allCases {
            for status in ListeningMode.availableSounds {
                do {
                    let clips=SoundMap.clips(status,pack:pack)
                    let pieces=clips.map{RecordedAudio.Piece(url:root.appendingPathComponent("Audio/\($0.file)"),start:$0.start,duration:$0.duration,gap:$0.pause)}
                    let samples=try pieces.flatMap{try RecordedAudio.samples($0)}
                    let data=try RecordedAudio.compose(pieces)
                    guard samples.count>=1000,samples.count<=52800,samples.allSatisfy({$0.isFinite && abs($0)<0.66}),samples.contains(where:{abs($0)>0.07}),tracks.insert(data).inserted else{return false}
                }catch{return false}
            }
        }
        return tracks.count==SoundPack.allCases.count*ListeningMode.availableSounds.count
    }
    check("声音包默认A320，全部选择可恢复且损坏值安全回退") {
        let suite="radio-packs-test-"+UUID().uuidString
        guard let prefs=UserDefaults(suiteName:suite) else{return false};defer{prefs.removePersistentDomain(forName:suite)}
        guard SoundPack.load(from:prefs) == .airbus else{return false}
        for pack in SoundPack.allCases {
            pack.save(to:prefs)
            guard SoundPack.load(from:prefs) == pack else{return false}
        }
        prefs.set("corrupt",forKey:SoundPack.preferenceKey)
        return SoundPack.load(from:prefs) == .airbus
    }
    check("撤回的本地声音包迁移到歼-11A并持久保存") {
        let suite="radio-pack-migration-"+UUID().uuidString
        guard let prefs=UserDefaults(suiteName:suite) else{return false};defer{prefs.removePersistentDomain(forName:suite)}
        prefs.set(0.34,forKey:"volume")
        for previous in ["ssn775","asr33"] {
            prefs.set(previous,forKey:SoundPack.preferenceKey)
            guard SoundPack.load(from:prefs) == .j11a,prefs.string(forKey:SoundPack.preferenceKey)=="j11a" else{return false}
        }
        return prefs.double(forKey:"volume")==0.34
    }
    check("全部提示匹配36个呼号与数字的有效电平，误差小于0.5dB且峰值受控") {
        guard let root=Bundle.main.resourceURL else{return false}
        do {
            let cues=try SoundPack.allCases.flatMap {pack in
                try ListeningMode.availableSounds.map {status in
                    try RecordedAudio.samples(.init(url:root.appendingPathComponent("Audio/"+SoundMap.clips(status,pack:pack)[0].file)))
                }
            }
            let digit=try RecordedAudio.samples(.init(url:root.appendingPathComponent("Voices/digit1.wav")))
            for filename in CallsignCatalog.recordingFiles {
                let voice=try RecordedAudio.samples(.init(url:root.appendingPathComponent("Voices/"+filename)))
                let spoken=RecordedAudio.stitch([(voice,0),(digit,0)],overlaps:[0,RecordedAudio.voiceCrossfade])
                let target=RecordedAudio.activeRMS(spoken)
                for cue in cues {
                    let matched=RecordedAudio.matchLevel(cue,to:spoken)
                    let delta=abs(20*log10(RecordedAudio.activeRMS(matched)/target))
                    guard delta<0.5,matched.count==cue.count,matched.allSatisfy({$0.isFinite && abs($0)<=0.901}) else{return false}
                }
            }
            return true
        }catch{return false}
    }
    check("自动电平只调整状态音，呼号叠化及声音节奏完整保留") {
        guard let root=Bundle.main.resourceURL else{return false}
        let voices=["alfa.wav","digit1.wav"].map{RecordedAudio.Piece(url:root.appendingPathComponent("Voices/"+$0),isVoice:true)}
        do {
            let prefix=try RecordedAudio.compose(voices).dropFirst(44)
            let cue=RecordedAudio.Piece(url:root.appendingPathComponent("Audio/Packs/airbus/compacting.wav"))
            let raw=try RecordedAudio.compose(voices+[cue])
            let matched=try RecordedAudio.compose(voices+[cue],matchCueLevel:true)
            return raw.count==matched.count && matched.dropFirst(44).prefix(prefix.count)==prefix && raw != matched
        }catch{return false}
    }
    check("静默音频不被自动增益放大成噪声或无效值") {
        let silence=[Float](repeating:0,count:480)
        return RecordedAudio.matchLevel(silence,to:[0.1,0.2])==silence && RecordedAudio.matchLevel([0.1,0.2],to:silence)==[0.1,0.2] && RecordedAudio.activeRMS([])==0
    }
    check("所有声音包的回执、收尾、等待与报错不会映射成同一音效") {
        SoundPack.allCases.allSatisfy { pack in
            let statuses:[RadioStatus]=[.unknown,.complete,.waiting,.blocked]
            let files=statuses.flatMap{SoundMap.clips($0,pack:pack).map(\.file)}
            return Set(files).count==4 && RadioStatus.allCases.allSatisfy{!SoundMap.clips($0,pack:pack).isEmpty && !SoundMap.description($0,pack:pack).isEmpty}
        }
    }
    check("切换声音包不改变真人呼号及叠化边界") {
        guard let root=Bundle.main.resourceURL else{return false}
        let voices=["alfa.wav","digit1.wav"].map{RecordedAudio.Piece(url:root.appendingPathComponent("Voices/"+$0),isVoice:true)}
        do {
            let prefix=try RecordedAudio.compose(voices).dropFirst(44)
            for pack in SoundPack.allCases {
                let cue=SoundMap.clips(.complete,pack:pack).map{RecordedAudio.Piece(url:root.appendingPathComponent("Audio/\($0.file)"))}
                let combined=try RecordedAudio.compose(voices+cue).dropFirst(44)
                guard combined.prefix(prefix.count)==prefix else{return false}
            }
            return true
        }catch{return false}
    }
    check("26个呼号及10个真人数字均可解码，拼接后时长紧凑"){
        guard let root=Bundle.main.resourceURL else{return false}
        return CallsignCatalog.recordingFiles.allSatisfy{name in
            do {
                let voice=root.appendingPathComponent("Voices/\(name)")
                let samples=try RecordedAudio.samples(.init(url:voice))
                let track=try RecordedAudio.compose([.init(url:voice,gap:RecordedAudio.callsignGap),.init(url:root.appendingPathComponent("Audio/Packs/airbus/reading.wav"))])
                return samples.count>6500 && samples.count<24000 && samples.contains{abs($0)>0.1} && track.count<60000
            }catch{return false}
        }
    }
    check("仅相邻人声叠化，状态提示音波形保持完整") {
        guard let root=Bundle.main.resourceURL else{return false}
        let a=RecordedAudio.Piece(url:root.appendingPathComponent("Voices/alfa.wav"),isVoice:true)
        let b=RecordedAudio.Piece(url:root.appendingPathComponent("Voices/digit1.wav"),isVoice:true)
        let cue=RecordedAudio.Piece(url:root.appendingPathComponent("Audio/Packs/airbus/reading.wav"),duration:0.12)
        do {
            let first=try RecordedAudio.samples(a),second=try RecordedAudio.samples(b),last=try RecordedAudio.samples(cue)
            let data=try RecordedAudio.compose([a,b,cue])
            return (data.count-44)/2==first.count+second.count+last.count-288 && data.suffix(last.count*2)==RecordedAudio.wav(last).dropFirst(44)
        }catch{return false}
    }
    check("项目呼号和对话编号独立持久化，刷新不重排编号"){
        var r=ProjectRegistry();let a=r.register(project:"p",thread:"one");let b=r.register(project:"p",thread:"two");let c=r.register(project:"q",thread:"three")
        r.assign(project:"p",to:1)
        guard let data=try? JSONEncoder().encode(r),var restored=try? JSONDecoder().decode(ProjectRegistry.self,from:data) else{return false}
        let again=restored.register(project:"p",thread:"two")
        return a.0==0 && a.1==1 && b.1==2 && c.0==1 && again.0==1 && again.1==2 && restored.register(project:"q",thread:"three").0==0
    }
    check("旧版编号无损迁移，自定义数字持久化且同项目冲突互换") {
        let old=Data(#"{"projectKeys":["p","q"],"callsigns":[0,1],"threadKeys":{"p":["a","b"],"q":["c"]}}"#.utf8)
        guard var r=try? JSONDecoder().decode(ProjectRegistry.self,from:old) else{return false}
        guard r.register(project:"p",thread:"a").1==1,r.assignNumber(project:"p",thread:"a",to:2),r.register(project:"p",thread:"b").1==1,r.assignNumber(project:"p",thread:"a",to:0) else{return false}
        guard let saved=try? JSONEncoder().encode(r),var copy=try? JSONDecoder().decode(ProjectRegistry.self,from:saved) else{return false}
        return copy.register(project:"p",thread:"a").1==0 && copy.register(project:"p",thread:"new").1==2 && copy.register(project:"q",thread:"c").1==1 && !copy.assignNumber(project:"p",thread:"a",to:-1) && !copy.assignNumber(project:"p",thread:"a",to:10000)
    }
    check("数字0可显示并使用原录音播报") {CallsignCatalog.numberFiles(0)==["digit0.wav"] && FlightChannel(id:"a",callsignIndex:0,number:0).callsign=="Alpha 0"}
    check("默认专注严格只允许收尾、等待确认、停止和报错") {
        let q=RadioQueue();let allowed=Set(RadioStatus.allCases.filter{!$0.isQuotaAlert && q.accepts($0)})
        return q.mode=="focus" && allowed==[.complete,.waiting,.cancelled,.blocked] && ListeningMode.allCases.map(\.rawValue)==["focus","detail","custom"]
    }
    check("详细模式逐条保留同对话事件、不过期、不抢占丢失") {
        let q=RadioQueue();q.muted=false;q.mode="detail"
        let a=e("p",.testing,0),b=e("p",.unknown,0.1),c=e("p",.waiting,0.2)
        q.offer(a,at:0);guard q.next(at:0)?.id==a.id else{return false}
        let preempt=q.offer(b,at:0.1);q.offer(c,at:0.2);q.finished(a.id)
        guard q.next(at:20)?.id==b.id else{return false};q.finished(b.id)
        return !preempt && q.next(at:30)?.id==c.id
    }
    check("自定义模式仅播放勾选状态，允许全部取消") {
        let q=RadioQueue();q.mode="custom";q.customSounds=[.reading,.unknown]
        guard RadioStatus.allCases.filter({!$0.isQuotaAlert && q.accepts($0)})==[.reading,.unknown] else{return false}
        q.customSounds=[];return RadioStatus.allCases.filter{!$0.isQuotaAlert}.allSatisfy{!q.accepts($0)}
    }
    check("菜单栏两种显示方式可保存重载，非法值恢复图标加文字") {
        let suite="radio-appearance-test-"+UUID().uuidString
        guard let prefs=UserDefaults(suiteName:suite) else{return false};defer{prefs.removePersistentDomain(forName:suite)}
        guard MenuBarAppearance.load(from:prefs) == .iconAndText else{return false}
        MenuBarAppearance.iconOnly.save(to:prefs)
        guard MenuBarAppearance.load(from:prefs).statusItemTitle.isEmpty else{return false}
        MenuBarAppearance.iconAndText.save(to:prefs)
        guard MenuBarAppearance.load(from:prefs).statusItemTitle == " Radio" else{return false}
        prefs.set("invalid",forKey:MenuBarAppearance.preferenceKey)
        return MenuBarAppearance.load(from:prefs) == .iconAndText
    }
    check("升级只新增压缩默认勾选，保留旧选择及之后的取消") {
        let suite="radio-sounds-test-"+UUID().uuidString
        guard let prefs=UserDefaults(suiteName:suite) else{return false};defer{prefs.removePersistentDomain(forName:suite)}
        prefs.set(["reading","unknown"],forKey:"customSoundsV1")
        guard ListeningMode.loadCustomSounds(from:prefs)==[.reading,.unknown,.compacting] else{return false}
        prefs.set(["reading","unknown"],forKey:"customSoundsV1")
        guard ListeningMode.loadCustomSounds(from:prefs)==[.reading,.unknown] else{return false}
        prefs.set([],forKey:"customSoundsV1")
        return ListeningMode.loadCustomSounds(from:prefs).isEmpty
    }
    check("压缩默认进入详细和自定义，专注始终过滤") {
        let suite="radio-defaults-test-"+UUID().uuidString
        guard let prefs=UserDefaults(suiteName:suite) else{return false};defer{prefs.removePersistentDomain(forName:suite)}
        let custom=ListeningMode.loadCustomSounds(from:prefs)
        return custom==ListeningMode.defaultCustomSounds && custom.contains(.compacting) && ListeningMode.detail.accepts(.compacting,custom:[]) && !ListeningMode.focus.accepts(.compacting,custom:custom) && ListeningMode.custom.accepts(.compacting,custom:custom)
    }
    check("压缩提示音独立、可离线组成单条音轨") {
        guard let root=Bundle.main.resourceURL else{return false}
        let clips=SoundMap.clips(.compacting)
        guard ListeningMode.availableSounds.filter({$0 != .compacting}).allSatisfy({SoundMap.clips($0) != clips}) else{return false}
        do {
            let data=try RecordedAudio.compose(clips.map{RecordedAudio.Piece(url:root.appendingPathComponent("Audio/\($0.file)"),start:$0.start,duration:$0.duration,gap:$0.pause)})
            return data.count>44
        }catch{return false}
    }
    check("自定义压缩提示不被紧随的工具事件合并吞掉") {
        let q=RadioQueue();q.muted=false;q.mode="custom";q.customSounds=[.compacting,.testing]
        let compact=e("p",.compacting,0);q.offer(compact,at:0);q.offer(e("p",.testing,0.1),at:0.1)
        return q.next(at:0.1)?.id==compact.id
    }
    check("项目编号由现有人声数字组成，12按无线电方式逐位读") {CallsignCatalog.filenames(for:0)==["alfa.wav"] && CallsignCatalog.numberFiles(12)==["digit1.wav","digit2.wav"]}
    func hook(_ name:String,_ agent:String?=nil,_ status:String?=nil,_ time:Double=1,_ tool:String?=nil)->LiveHookEvent{LiveHookEvent(id:UUID().uuidString,host:"local",session:"parent",agent:agent,event:name,status:status,receivedAt:time,turn:"t",toolUse:tool)}
    check("发送与停止有独立实际事件提示") {var a=ConversationActivity();let sent=a.receive(hook("UserPromptSubmit"));let stop=a.receive(hook("Interrupt",nil,nil,2));return sent == .reading && stop == .cancelled && a.state == .interrupted}
    check("同一轮插入保留正在执行的工具及子代理") {var a=ConversationActivity();_ = a.receive(hook("UserPromptSubmit"));_ = a.receive(hook("PreToolUse",nil,nil,2,"tool"));_ = a.receive(hook("SubagentStart","child",nil,3));let cue=a.receive(hook("UserPromptSubmit",nil,nil,4));return cue == .reading && a.state == .running && a.tools.count==1 && a.agents.count==1}
    check("停止后晚到的主工具结果不恢复状态") {var a=ConversationActivity();_ = a.receive(hook("Interrupt"));return a.receive(hook("PostToolUse",nil,"unknown",2))==nil && a.state == .interrupted}
    check("未知结果接入为工具返回，不推断成功或报错") {var a=ConversationActivity();_ = a.receive(hook("PreToolUse",nil,nil,1,"tool"));let cue=a.receive(hook("PostToolUse",nil,"unknown",2,"tool"));return cue == .unknown && a.state == .returned && a.tools.isEmpty}
    check("子代理归父对话，子代理结束不标记主对话完成") {var a=ConversationActivity();_ = a.receive(hook("SubagentStart","child"));_ = a.receive(hook("SubagentStop","child",nil,2));return a.agents.isEmpty && a.state == .returned}
    check("主对话中断后晚到的子代理事件不会复活状态或播报") {var a=ConversationActivity();_ = a.receive(hook("Interrupt"));return a.receive(hook("PostToolUse","child","unknown",2))==nil && a.state == .interrupted}
    check("并行工具返回不会提前显示空闲") {var a=ConversationActivity();_ = a.receive(hook("PreToolUse",nil,nil,1,"a"));_ = a.receive(hook("PreToolUse","child",nil,2,"b"));_ = a.receive(hook("PostToolUse",nil,"unknown",3,"a"));return a.state == .running && a.tools.count==1}
    check("压缩开始播报一次，完成静默恢复状态且保留工具与子代理") {
        var a=ConversationActivity();_ = a.receive(hook("PreToolUse",nil,nil,1,"a"));_ = a.receive(hook("SubagentStart","child",nil,2))
        let start=a.receive(hook("PreCompact",nil,nil,3))
        guard start == .compacting,a.state == .compacting,a.tools.count==1,a.agents.count==1 else{return false}
        return a.receive(hook("PostCompact",nil,nil,4))==nil && a.state == .running && a.tools.count==1 && a.agents.count==1
    }
    check("停止和收尾后晚到的压缩完成不会重新激活对话") {
        for ending in ["Interrupt","Stop"] {
            var a=ConversationActivity();_ = a.receive(hook("PreCompact"));_ = a.receive(hook(ending,nil,nil,2));let state=a.state
            guard a.receive(hook("PostCompact",nil,nil,3))==nil,a.state==state else{return false}
        }
        return true
    }
    check("子代理压缩使用父呼号且不改变父任务状态") {
        var a=ConversationActivity();_ = a.receive(hook("PreToolUse",nil,nil,1,"a"))
        guard a.receive(hook("PreCompact","child",nil,2)) == .compacting,a.state == .running else{return false}
        return a.receive(hook("PostCompact","child",nil,3))==nil && a.state == .running && a.tools.count==1
    }
    check("最近一周目录仅读元数据，真实项目归属优先于工作目录"){
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent("wing-catalog-"+UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:dir)}
            var db:OpaquePointer?;guard sqlite3_open(dir.appendingPathComponent("state_5.sqlite").path,&db)==SQLITE_OK else{return false}
            let sql="CREATE TABLE threads(id TEXT,name TEXT,source TEXT,thread_source TEXT,project_id TEXT,updated_at INTEGER,created_at INTEGER,cwd TEXT,archived INTEGER); INSERT INTO threads VALUES('recent','真实标题','vscode','user',NULL,900000,1,'/shared',0),('old','旧对话','vscode','user',NULL,1,1,'/shared',0),('child','内部子代理','vscode','subagent',NULL,900000,1,'/shared',0),('archived','本周已归档','vscode','user',NULL,900000,1,'/shared',1),('remote','远程','vscode','user',NULL,900000,1,'/shared',0);"
            let ok=sqlite3_exec(db,sql,nil,nil,nil)==SQLITE_OK;sqlite3_close(db);guard ok else{return false}
            let config:[String:Any]=["local-projects":["p":["name":"项目原名","rootPaths":["/shared"]],"q":["name":"另一个项目","rootPaths":["/shared"]]],"thread-project-assignments":["recent":["projectKind":"local","projectId":"p"]],"thread-project-membership-host-ids":["remote":"remote"],"projectless-thread-ids":["archived"]]
            try JSONSerialization.data(withJSONObject:config).write(to:dir.appendingPathComponent(".codex-global-state.json"))
            let rows=try ConversationCatalog.read(root:dir,now:1_000_000)
            return rows.count==2 && rows.first{$0.id=="recent"}?.projectTitle=="项目原名" && rows.first{$0.id=="recent"}?.title=="真实标题" && rows.first{$0.id=="archived"}?.projectID=="unassigned"
        }catch{return false}
    }
    check("连接只消费新事件，不回放历史与重复文件"){
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("wing-radio-reader-"+UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            defer{try? FileManager.default.removeItem(at:root)}
            func write(_ name:String,_ time:Double)throws{let data=try JSONSerialization.data(withJSONObject:["id":name,"host":"local","session":"s","event":"PreToolUse","status":"testing","receivedAt":time]);try data.write(to:root.appendingPathComponent("event-"+name+".json"))}
            try write("old",Date().timeIntervalSince1970-20)
            let reader=LiveEventReader();reader.connect(root)
            try write("new",Date().timeIntervalSince1970)
            try FileManager.default.copyItem(at:root.appendingPathComponent("event-new.json"),to:root.appendingPathComponent("event-duplicate.json"))
            let events=reader.poll()
            return events.count==1 && events[0].id=="new" && reader.poll().isEmpty
        } catch{return false}
    }
    runIntegrationTests(check)
    runStartupTests(check)
    runQuotaTests(check)
    print("\(passed) checks passed; no audio player constructed and no physical playback.")
}
