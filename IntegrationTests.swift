import Foundation

func runIntegrationTests(_ check:(String,()->Bool)->Void) {
    let fm=FileManager.default
    guard let resources=Bundle.main.resourceURL else{fatalError("Missing test resources")}
    let helper=resources.appendingPathComponent("../Helpers/CodexRadioHook").standardizedFileURL
    func isolated(_ body:(URL,URL)throws->Bool)->Bool {
        let home=fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("radio-fresh-"+UUID().uuidString+" 用户's Mac")
        do {
            try fm.createDirectory(at:home,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]);defer{try? fm.removeItem(at:home)}
            return try body(home,home.appendingPathComponent(".codex"))
        }catch{print("Integration test error: \(error)");return false}
    }
    func makeRoot(_ root:URL)throws{try fm.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])}
    check("新电脑未安装Codex时只报告缺失，不创建或伪造配置") {isolated {home,root in
        let snapshot=RadioIntegration.inspect(root:root,home:home)
        do{try RadioIntegration.install(root:root,home:home,helper:helper);return false}catch{}
        return !snapshot.folderExists && !fm.fileExists(atPath:root.path) && !fm.fileExists(atPath:RadioIntegration.support(home:home).path)
    }}
    check("首次检查无写入，允许安装后新增12项且不需要Python") {isolated {home,root in
        try makeRoot(root)
        guard RadioIntegration.inspect(root:root,home:home).installedEvents==0,!fm.fileExists(atPath:root.appendingPathComponent("hooks.json").path) else{return false}
        guard try RadioIntegration.install(root:root,home:home,helper:helper)==12 else{return false}
        let (object,_)=try RadioIntegration.document(root)
        let text=String(data:try JSONSerialization.data(withJSONObject:object),encoding:.utf8)!
        return RadioIntegration.inspect(root:root,home:home).complete && !text.contains("python") && !fm.fileExists(atPath:root.appendingPathComponent("config.toml").path) && !fm.fileExists(atPath:root.appendingPathComponent("auth.json").path)
    }}
    check("原有Hooks与顶层字段保留，重复安装不改字节且不写信任记录") {isolated {home,root in
        try makeRoot(root)
        let existing:[String:Any]=["description":"user-owned","hooks":["Stop":[["hooks":[["type":"command","command":"user-hook"]]]]]]
        let file=root.appendingPathComponent("hooks.json")
        try JSONSerialization.data(withJSONObject:existing).write(to:file)
        let trust=root.appendingPathComponent("hook-trust-sentinel");try Data("unchanged".utf8).write(to:trust)
        try RadioIntegration.install(root:root,home:home,helper:helper)
        let first=try Data(contentsOf:file),object=try RadioIntegration.document(root).0
        guard try RadioIntegration.install(root:root,home:home,helper:helper)==0 else{return false}
        let groups=(object["hooks"] as? [String:[[String:Any]]])?["Stop"] ?? []
        return try groups.count==2 && ((groups[0]["hooks"] as? [[String:Any]])?.first?["command"] as? String)=="user-hook" && object["description"] as? String=="user-owned" && (try Data(contentsOf:file))==first && (try String(contentsOf:trust))=="unchanged"
    }}
    check("旧12项已配置时原定义保持逐字节不变") {isolated {home,root in
        try makeRoot(root);let base=RadioIntegration.support(home:home);try RadioIntegration.privateDirectory(base)
        for name in RadioIntegration.legacyHashes.keys {
            let source=name.hasPrefix("compaction") ? "compaction_collector.py" : "collector.py"
            try fm.copyItem(at:resources.appendingPathComponent("Integration/"+source),to:base.appendingPathComponent(name))
        }
        let commands=RadioIntegration.knownCommands(home:home)
        guard commands.count==2 else{return false}
        var hooks:[String:Any]=[:]
        for event in RadioIntegration.events {
            let compact=["PreCompact","PostCompact"].contains(event)
            let command=commands.first{$0.contains("compaction-collector")==compact}!
            hooks[event]=[["hooks":[["type":"command","command":command,"timeout":1]]]]
        }
        let file=root.appendingPathComponent("hooks.json"),original=try JSONSerialization.data(withJSONObject:["hooks":hooks],options:[.prettyPrinted])
        try original.write(to:file)
        return try RadioIntegration.inspect(root:root,home:home).complete && (try RadioIntegration.install(root:root,home:home,helper:helper))==0 && (try Data(contentsOf:file))==original && !fm.fileExists(atPath:base.appendingPathComponent("native-integration.json").path)
    }}
    check("无效JSON拒绝覆盖，接入目录中不产生程序") {isolated {home,root in
        try makeRoot(root);let file=root.appendingPathComponent("hooks.json"),bad=Data("{invalid".utf8);try bad.write(to:file)
        do{try RadioIntegration.install(root:root,home:home,helper:helper);return false}catch{}
        return (try Data(contentsOf:file))==bad && !fm.fileExists(atPath:RadioIntegration.support(home:home).path)
    }}
    check("拒绝hooks文件符号链接，不修改其目标") {isolated {home,root in
        try makeRoot(root);let target=home.appendingPathComponent("private.json"),bytes=Data("{}".utf8);try bytes.write(to:target)
        try fm.createSymbolicLink(at:root.appendingPathComponent("hooks.json"),withDestinationURL:target)
        do{try RadioIntegration.install(root:root,home:home,helper:helper);return false}catch{}
        return (try Data(contentsOf:target))==bytes
    }}
    check("安装时发现并发编辑会停止，不覆盖新配置") {isolated {home,root in
        try makeRoot(root);let file=root.appendingPathComponent("hooks.json"),edited=Data("{\"description\":\"concurrent\"}".utf8)
        do{try RadioIntegration.install(root:root,home:home,helper:helper,beforeCommit:{try! edited.write(to:file)});return false}catch{}
        return (try Data(contentsOf:file))==edited
    }}
    check("中文空格和单引号路径可运行原生命令，输出只含最小元数据") {isolated {home,root in
        try makeRoot(root);try RadioIntegration.install(root:root,home:home,helper:helper)
        guard let command=RadioIntegration.knownCommands(home:home).first else{return false}
        let process=Process(),input=Pipe(),output=Pipe();process.executableURL=URL(fileURLWithPath:"/bin/sh");process.arguments=["-c",command];process.standardInput=input;process.standardOutput=output
        try process.run()
        try input.fileHandleForWriting.write(contentsOf:Data(#"{"hook_event_name":"PreCompact","session_id":"test","prompt":"PRIVATE","transcript_path":"PRIVATE"}"#.utf8));try input.fileHandleForWriting.close();process.waitUntilExit()
        let stdout=output.fileHandleForReading.readDataToEndOfFile(),spool=RadioIntegration.support(home:home).appendingPathComponent("events")
        let files=try fm.contentsOfDirectory(at:spool,includingPropertiesForKeys:nil).filter{$0.lastPathComponent.hasPrefix("event-")}
        guard files.count==1 else{return false}
        let text=try String(contentsOf:files[0])
        return process.terminationStatus==0 && String(data:stdout,encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines)=="{}" && text.contains("compacting") && !text.contains("PRIVATE")
    }}
    check("缺少或损坏原生程序时不会误报完整接入") {isolated {home,root in
        try makeRoot(root);try RadioIntegration.install(root:root,home:home,helper:helper)
        let base=RadioIntegration.support(home:home),receipt=try RadioIntegration.readFile(base.appendingPathComponent("native-integration.json"))
        let name=(try JSONSerialization.jsonObject(with:receipt) as! [String:String])["helper"]!
        try fm.removeItem(at:base.appendingPathComponent(name))
        return !RadioIntegration.inspect(root:root,home:home).complete
    }}
}
