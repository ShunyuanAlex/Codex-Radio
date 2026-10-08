import Foundation
import AppKit
import Darwin

struct WeeklyQuotaSnapshot:Equatable {
    let usedPercent:Double
    let resetsAt:Double
    var remainingPercent:Double {max(0,100-usedPercent)}
    var exhausted:Bool {usedPercent>=100}
    var display:String {
        if exhausted{return "0%"}
        if remainingPercent<1{return "<1%"}
        return remainingPercent == remainingPercent.rounded() ? "\(Int(remainingPercent))%" : String(format:"%.1f%%",remainingPercent)
    }
    // A week can be primary or secondary. Only the standard Codex bucket is
    // relevant here; reserve/model-specific limits must not trigger this alarm.
    static func decode(_ data:Data,now:Double)throws->Self? {
        struct Window:Decodable {let usedPercent:Double?;let windowDurationMins:Int?;let resetsAt:Double?}
        struct Bucket:Decodable {let limitId:String?;let primary:Window?;let secondary:Window?}
        struct Response:Decodable {let rateLimits:Bucket?;let rateLimitsByLimitId:[String:Bucket]?}
        let response=try JSONDecoder().decode(Response.self,from:data)
        let bucket:Bucket?
        if let buckets=response.rateLimitsByLimitId,!buckets.isEmpty{bucket=buckets["codex"]}
        else{bucket=response.rateLimits}
        guard let bucket,bucket.limitId==nil || bucket.limitId=="codex" else{return nil}
        let candidates=[bucket.primary,bucket.secondary].compactMap{$0}.filter{$0.windowDurationMins==10080}
        guard candidates.count==1,let window=candidates.first,
              let used=window.usedPercent,used.isFinite,(0...100).contains(used),
              let reset=window.resetsAt,reset.isFinite,reset>now else{return nil}
        return Self(usedPercent:used,resetsAt:reset)
    }
}

enum WeeklyQuotaAlarm:Equatable {
    case warning(Int),exhausted
    var status:RadioStatus {self == .exhausted ? .weeklyLimit : .weeklyWarning}
    var title:String {switch self{case .warning(let percent):return "周剩余 \(percent)% / Pull up Pull up";case .exhausted:return "周剩余额度 0% / 耗尽警报"}}
}

struct WeeklyQuotaAlertGate {
    static let enabledKey="weeklyQuotaAlarmV1"
    static let historyKey="weeklyQuotaAlarmThresholdsV2"
    static func enabled(in defaults:UserDefaults)->Bool {defaults.object(forKey:enabledKey)==nil || defaults.bool(forKey:enabledKey)}
    // Keep the lowest observed threshold per reset window. A jump from 6% to 2%
    // sounds once for 2%, never a burst of skipped warnings. Muted observations
    // also advance this mark, so unmute/restart cannot replay them.
    static func observe(_ quota:WeeklyQuotaSnapshot,scope:String,canPlay:Bool,defaults:UserDefaults)->WeeklyQuotaAlarm? {
        guard quota.remainingPercent<=5 else{return nil}
        let threshold=quota.exhausted ? 0 : Int(ceil(quota.remainingPercent))
        let key=scope+"|codex|"+String(quota.resetsAt)
        var history=defaults.dictionary(forKey:historyKey) as? [String:Int] ?? [:]
        guard threshold < (history[key] ?? 6) else{return nil}
        history[key]=threshold
        // A small bounded history, retaining this window and the latest resets.
        let keys=history.keys.sorted{(Double($0.split(separator:"|").last ?? "") ?? 0) > (Double($1.split(separator:"|").last ?? "") ?? 0)}
        history=Dictionary(uniqueKeysWithValues:keys.prefix(64).map{($0,history[$0]!)})
        defaults.set(history,forKey:historyKey)
        guard canPlay else{return nil}
        return threshold==0 ? .exhausted : .warning(threshold)
    }
}

enum CodexQuotaClient {
    enum Failure:Error,LocalizedError {
        case unavailable,timeout,invalidResponse,requestFailed
        var errorDescription:String? {
            switch self {
            case .unavailable:return "未找到 Codex 程序，请先安装并登录 Codex。"
            case .timeout:return "额度读取超时，将自动重试。"
            case .invalidResponse:return "暂时无法识别周额度，不触发报警。"
            case .requestFailed:return "暂时无法读取额度，请确认 Codex 已登录。"
            }
        }
    }
    static func executable()->URL? {
        let fm=FileManager.default
        let apps=[NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.openai.codex"),NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.openai.chat")].compactMap{$0}
            + [URL(fileURLWithPath:"/Applications/Codex.app"),URL(fileURLWithPath:"/Applications/ChatGPT.app")]
        let relatives=["Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex","Contents/Resources/codex-cli/bin/codex","Contents/Resources/codex"]
        let paths=apps.flatMap{app in relatives.map{app.appendingPathComponent($0)}}
            + ["/opt/homebrew/bin/codex","/usr/local/bin/codex"].map{URL(fileURLWithPath:$0)}
        return paths.first{fm.isExecutableFile(atPath:$0.path)}
    }
    // Run only on a utility queue. No shell, auth-file access, model turn, remote
    // listener, or persistent daemon. Codex handles its own existing login.
    static func read(executable:URL,root:URL,timeout:Double=15)throws->WeeklyQuotaSnapshot? {
        let process=Process(),input=Pipe(),output=Pipe()
        process.executableURL=executable
        process.arguments=["app-server","--listen","stdio://"]
        var environment=ProcessInfo.processInfo.environment;environment["CODEX_HOME"]=root.path
        process.environment=environment;process.currentDirectoryURL=root
        process.standardInput=input;process.standardOutput=output;process.standardError=FileHandle.nullDevice
        do{try process.run()}catch{throw Failure.unavailable}
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning{process.terminate()}
            let until=ProcessInfo.processInfo.systemUptime+0.5
            while process.isRunning && ProcessInfo.processInfo.systemUptime<until{Thread.sleep(forTimeInterval:0.01)}
            if process.isRunning{kill(process.processIdentifier,SIGKILL)}
            try? output.fileHandleForReading.close()
        }
        func send(_ object:[String:Any])throws {
            var data=try JSONSerialization.data(withJSONObject:object);data.append(10)
            do{try input.fileHandleForWriting.write(contentsOf:data)}catch{throw Failure.requestFailed}
        }
        _=fcntl(input.fileHandleForWriting.fileDescriptor,F_SETNOSIGPIPE,1)
        try send(["id":1,"method":"initialize","params":["clientInfo":["name":"codex_radio","title":"Codex Radio","version":"0.12.0"]]])
        let fd=output.fileHandleForReading.fileDescriptor
        _=fcntl(fd,F_SETFL,fcntl(fd,F_GETFL)|O_NONBLOCK)
        let deadline=ProcessInfo.processInfo.systemUptime+timeout
        var buffer=Data(),total=0,initialized=false
        while ProcessInfo.processInfo.systemUptime<deadline {
            var descriptor=pollfd(fd:fd,events:Int16(POLLIN),revents:0)
            let ready=poll(&descriptor,1,100)
            if ready<0 {if errno==EINTR{continue};throw Failure.requestFailed}
            if ready==0 {if !process.isRunning{throw Failure.requestFailed};continue}
            var bytes=[UInt8](repeating:0,count:8192)
            let count=Darwin.read(fd,&bytes,bytes.count)
            if count<0 {if errno==EAGAIN || errno==EINTR{continue};throw Failure.requestFailed}
            guard count>0 else{throw Failure.requestFailed}
            total += count;guard total<=262144 else{throw Failure.invalidResponse}
            buffer.append(contentsOf:bytes.prefix(count))
            while let newline=buffer.firstIndex(of:10) {
                let line=Data(buffer[..<newline]);buffer.removeSubrange(...newline)
                guard let object=(try? JSONSerialization.jsonObject(with:line)) as? [String:Any],let id=object["id"] as? Int else{continue}
                guard object["error"]==nil else{throw Failure.requestFailed}
                if id==1 && !initialized {
                    guard object["result"] != nil else{throw Failure.invalidResponse}
                    initialized=true;try send(["method":"initialized"])
                    try send(["id":2,"method":"account/rateLimits/read"])
                }else if id==2 && initialized {
                    guard let result=object["result"] as? [String:Any] else{throw Failure.invalidResponse}
                    do{return try WeeklyQuotaSnapshot.decode(JSONSerialization.data(withJSONObject:result),now:Date().timeIntervalSince1970)}
                    catch{throw Failure.invalidResponse}
                }
            }
        }
        throw Failure.timeout
    }
}
