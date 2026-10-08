import Foundation

func runQuotaTests(_ check:(String,()->Bool)->Void) {
    let now=1000.0,reset=2000.0
    func window(_ used:Any=100,_ duration:Any=10080,_ reset:Any=2000)->[String:Any]{["usedPercent":used,"windowDurationMins":duration,"resetsAt":reset]}
    func read(_ payload:[String:Any])->WeeklyQuotaSnapshot?{try? WeeklyQuotaSnapshot.decode(JSONSerialization.data(withJSONObject:payload),now:now)}
    func legacy(_ window:[String:Any],slot:String="primary")->[String:Any]{["rateLimits":["limitId":"codex",slot:window]]}
    func withPrefs(_ body:(UserDefaults)->Bool)->Bool {
        let name="radio-quota-test-"+UUID().uuidString
        guard let prefs=UserDefaults(suiteName:name) else{return false}
        defer{prefs.removePersistentDomain(forName:name)}
        return body(prefs)
    }
    check("周窗口按10080分钟识别，兼容第一栏与第二栏") {
        read(legacy(window()))?.exhausted==true && read(legacy(window(),slot:"secondary"))?.exhausted==true
    }
    check("短时额度耗尽不会触发周额度报警") {
        read(["rateLimits":["primary":window(100,300),"secondary":window(38)]])?.remainingPercent==62 && read(legacy(window(100,300)))==nil
    }
    check("多额度桶优先使用Codex，预备额度与旧视图不触发误报") {
        let quota=read(["rateLimits":["primary":window()],"rateLimitsByLimitId":["codex":["limitId":"codex","primary":window(98)],"base_model_inference":["primary":window()]]])
        return quota?.remainingPercent==2 && read(["rateLimits":["primary":window()],"rateLimitsByLimitId":["base_model_inference":["primary":window()]]])==nil
    }
    check("空多桶可回退旧视图，未知额度不当作0%") {
        read(["rateLimits":["primary":window()],"rateLimitsByLimitId":[:]])?.exhausted==true && read([:])==nil && read(["rateLimits":NSNull()])==nil && read(legacy([:]))==nil
    }
    check("非周窗口、已过期窗口及损坏数字不报警") {
        [window(100,10080,999),window(-1),window(101),window("100"),window(true),window(100,NSNull()),window(100,10080,NSNull())].allSatisfy{read(legacy($0))==nil}
    }
    check("0.1%尚未耗尽且不会四舍五入显示0%") {
        let quota=read(legacy(window(99.9)))
        return quota?.exhausted==false && quota?.display=="<1%" && read(legacy(window()))?.display=="0%"
    }
    check("5至1每下降1%提醒一次，0%独立警报，同档不重复") {withPrefs {prefs in
        for remaining in stride(from:6,through:0,by:-1) {
            let quota=WeeklyQuotaSnapshot(usedPercent:Double(100-remaining),resetsAt:reset)
            let expected:WeeklyQuotaAlarm?=remaining==6 ? nil : remaining==0 ? .exhausted : .warning(remaining)
            guard WeeklyQuotaAlertGate.observe(quota,scope:"a",canPlay:true,defaults:prefs)==expected,
                  WeeklyQuotaAlertGate.observe(quota,scope:"a",canPlay:true,defaults:prefs)==nil else{return false}
        }
        return true
    }}
    check("小数阈值不提前进入下一档，低于1%仍只属于1%档") {withPrefs {prefs in
        func observe(_ used:Double)->WeeklyQuotaAlarm? {WeeklyQuotaAlertGate.observe(.init(usedPercent:used,resetsAt:reset),scope:"a",canPlay:true,defaults:prefs)}
        return observe(94.9)==nil && observe(95) == .warning(5) && observe(95.9)==nil && observe(96) == .warning(4) && observe(99) == .warning(1) && observe(99.9)==nil && observe(100) == .exhausted
    }}
    check("跳过多档只报当前档，读数回升与重启不重报旧档") {withPrefs {prefs in
        func observe(_ used:Double)->WeeklyQuotaAlarm? {WeeklyQuotaAlertGate.observe(.init(usedPercent:used,resetsAt:reset),scope:"a",canPlay:true,defaults:prefs)}
        guard observe(98) == .warning(2),observe(96)==nil,observe(98)==nil,observe(99) == .warning(1) else{return false}
        // Every observation reloads the persisted threshold history.
        return observe(100) == .exhausted && observe(100)==nil
    }}
    check("新周与不同Codex目录分别去重") {withPrefs {prefs in
        let quota=WeeklyQuotaSnapshot(usedPercent:95,resetsAt:reset)
        return WeeklyQuotaAlertGate.observe(quota,scope:"a",canPlay:true,defaults:prefs) == .warning(5)
            && WeeklyQuotaAlertGate.observe(quota,scope:"b",canPlay:true,defaults:prefs) == .warning(5)
            && WeeklyQuotaAlertGate.observe(.init(usedPercent:95,resetsAt:reset+604800),scope:"a",canPlay:true,defaults:prefs) == .warning(5)
    }}
    check("静音或零音量不补报当前档，更低新档仍可提醒") {withPrefs {prefs in
        let quota=WeeklyQuotaSnapshot(usedPercent:95,resetsAt:reset)
        return WeeklyQuotaAlertGate.observe(quota,scope:"a",canPlay:false,defaults:prefs)==nil
            && WeeklyQuotaAlertGate.observe(quota,scope:"a",canPlay:true,defaults:prefs)==nil
            && WeeklyQuotaAlertGate.observe(.init(usedPercent:96,resetsAt:reset),scope:"a",canPlay:true,defaults:prefs) == .warning(4)
    }}
    check("5%以上不产生提醒记录") {withPrefs {prefs in
        WeeklyQuotaAlertGate.observe(.init(usedPercent:94,resetsAt:reset),scope:"a",canPlay:true,defaults:prefs)==nil && prefs.object(forKey:WeeklyQuotaAlertGate.historyKey)==nil
    }}
    check("周额度报警默认开启，手动关闭可持久保存") {withPrefs {prefs in
        guard WeeklyQuotaAlertGate.enabled(in:prefs) else{return false}
        prefs.set(false,forKey:WeeklyQuotaAlertGate.enabledKey)
        return !WeeklyQuotaAlertGate.enabled(in:prefs)
    }}
    check("周额度报警在三种模式均可抢占，后续事件不重叠或抢占它") {
        ListeningMode.allCases.allSatisfy {mode in
            let queue=RadioQueue();queue.muted=false;queue.mode=mode.rawValue;queue.customSounds=[]
            let task=RadioEvent(channel:"task",status:.waiting,receivedAt:0)
            queue.offer(task,at:0,force:true);guard queue.next(at:0) != nil else{return false}
            let alarm=RadioEvent(channel:"weekly-quota",status:.weeklyLimit,receivedAt:1)
            guard queue.offer(alarm,at:1),queue.next(at:1)?.id==alarm.id else{return false}
            queue.offer(.init(channel:"task2",status:.blocked,receivedAt:1),at:1,force:true)
            return queue.active?.id==alarm.id && queue.next(at:1)==nil
        }
    }
    check("周额度声音跨机型一致，包含两段完整录音且匹配呼号电平") {
        guard let root=Bundle.main.resourceURL else{return false}
        do {
            let raw=try RecordedAudio.samples(.init(url:root.appendingPathComponent("Audio/Alerts/pull-up.wav")))
            let reference=try RecordedAudio.samples(.init(url:root.appendingPathComponent("Voices/alfa.wav")))
            let matched=RecordedAudio.matchLevel(raw,to:reference)
            let phraseLength=(raw.count-1920)/2
            return raw.count>48000 && raw.count<72000 && Array(raw.prefix(phraseLength))==Array(raw.suffix(phraseLength))
                && abs(20*log10(RecordedAudio.activeRMS(matched)/RecordedAudio.activeRMS(reference)))<0.5
                && matched.allSatisfy{abs($0)<=0.901}
                && Set(SoundPack.allCases.map{SoundMap.clips(.weeklyWarning,pack:$0)[0].file}).count==1
        }catch{return false}
    }
    check("耗尽警报与Pull up不同，无语音重复，电平匹配且时长受控") {
        guard let root=Bundle.main.resourceURL else{return false}
        do {
            let alarm=try RecordedAudio.samples(.init(url:root.appendingPathComponent("Audio/Alerts/quota-exhausted.wav")))
            let speech=try RecordedAudio.samples(.init(url:root.appendingPathComponent("Audio/Alerts/pull-up.wav")))
            let reference=try RecordedAudio.samples(.init(url:root.appendingPathComponent("Voices/alfa.wav")))
            let matched=RecordedAudio.matchLevel(alarm,to:reference)
            return alarm != speech && alarm.count>12000 && alarm.count<72000 && matched.allSatisfy{abs($0)<=0.901}
                && abs(20*log10(RecordedAudio.activeRMS(matched)/RecordedAudio.activeRMS(reference)))<0.5
                && SoundMap.clips(.weeklyLimit) != SoundMap.clips(.weeklyWarning)
        }catch{return false}
    }
    // Exercise actual child-process transport with a local fixture, never a
    // live account, auth file, network request or audio player.
    func fixture(_ script:String,_ body:(URL,URL)throws->Bool)->Bool {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent("radio-quota-"+UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            defer{try? FileManager.default.removeItem(at:dir)}
            let executable=dir.appendingPathComponent("codex-fixture")
            try ("#!/bin/sh\n"+script).write(to:executable,atomically:true,encoding:.utf8)
            try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:executable.path)
            return try body(executable,dir)
        }catch{return false}
    }
    check("额度客户端完成握手，只请求额度并保留自定义CODEX_HOME") {
        fixture("""
        [ "$1" = app-server ] && [ "$2" = --listen ] && [ "$3" = stdio:// ] || exit 1
        [ "$CODEX_HOME" -ef . ] || exit 1
        IFS= read -r line
        printf '%s\\n' '{"id":1,"result":{}}'
        IFS= read -r line
        IFS= read -r line
        case "$line" in *rateLimits*read*) ;; *) exit 1;; esac
        printf '%s' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":100,'
        printf '%s\\n' '"windowDurationMins":10080,"resetsAt":4102444800}}}}'
        """) {exe,root in try CodexQuotaClient.read(executable:exe,root:root)?.exhausted==true}
    }
    check("读取失败与超时安全结束，不变成耗尽数据") {
        let error=fixture("IFS= read -r line\nprintf '%s\\n' '{\"id\":1,\"error\":{\"code\":-1}}'") {exe,root in
            do{_ = try CodexQuotaClient.read(executable:exe,root:root);return false}catch CodexQuotaClient.Failure.requestFailed{return true}catch{return false}
        }
        let timeout=fixture("trap '' TERM\nIFS= read -r line\nIFS= read -r line") {exe,root in
            let started=ProcessInfo.processInfo.systemUptime
            do{_ = try CodexQuotaClient.read(executable:exe,root:root,timeout:0.2);return false}catch CodexQuotaClient.Failure.timeout{return ProcessInfo.processInfo.systemUptime-started<2}catch{return false}
        }
        return error && timeout
    }
}
