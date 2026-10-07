import Foundation
import CryptoKit
import Darwin

struct IntegrationSnapshot {
    var folderExists=false
    var installedEvents=0
    var issue:String?
    var complete:Bool{folderExists && installedEvents==12 && issue==nil}
}

enum RadioIntegration {
    static let events=["SessionStart","SessionEnd","UserPromptSubmit","PreToolUse","PostToolUse","PermissionRequest","Stop","Interrupt","SubagentStart","SubagentStop","PreCompact","PostCompact"]
    static let legacyHashes=["collector-36e0ec4d7659b689.py":"36e0ec4d7659b68982ed8a24f5acfd1510abcd5a9380a038ae04b73cf12ee5f8","compaction-collector-e4c6d979ecd18f36.py":"e4c6d979ecd18f36a2b6e1d8c8edd8702831e84c0aeec95846cc97348e69df36"]
    static func digest(_ data:Data)->String{SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    static func quote(_ text:String)->String{"'"+text.replacingOccurrences(of:"'",with:"'\\''")+"'"}
    static func support(home:URL)->URL{home.appendingPathComponent("Library/Application Support/WingRadio")}
    static func nativeCommand(helper:URL,home:URL)->String{quote(helper.path)+" --spool "+quote(support(home:home).appendingPathComponent("events").path)}
    static func checkPath(_ path:URL)throws {
        var info=stat()
        if lstat(path.path,&info)==0 {
            guard info.st_mode & S_IFMT != S_IFLNK,info.st_uid==getuid() else{throw Failure.unsafePath}
        }else if errno != ENOENT{throw Failure.unreadable}
    }
    static func readFile(_ file:URL,limit:Int=16_000_000)throws->Data {
        try checkPath(file)
        let values=try file.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
        guard values.isRegularFile==true,(values.fileSize ?? Int.max)<=limit else{throw Failure.unreadable}
        return try Data(contentsOf:file)
    }
    enum Failure:LocalizedError {
        case missingCodex,malformed,unsafePath,unreadable,missingHelper,concurrentEdit
        var errorDescription:String? {
            switch self {
            case .missingCodex:return "未找到 Codex 数据目录。请先安装并打开 Codex，或选择实际使用的目录。"
            case .malformed:return "现有 hooks.json 格式无效；未覆盖。请先在 Codex 中修复配置。"
            case .unsafePath:return "配置路径包含符号链接或不属于当前用户；未写入。请选择实际目录并检查文件权限。"
            case .unreadable:return "无法读取或写入所选目录。请检查目录权限，不需要授予辅助功能或屏幕录制权限。"
            case .missingHelper:return "应用内置接入程序缺失或无效，请重新安装 Codex Radio。"
            case .concurrentEdit:return "配置刚被其他程序修改；未覆盖，请重新检查后再试。"
            }
        }
    }
    static func document(_ root:URL)throws->([String:Any],Data?) {
        try checkPath(root)
        var isDirectory:ObjCBool=false
        guard FileManager.default.fileExists(atPath:root.path,isDirectory:&isDirectory),isDirectory.boolValue else{throw Failure.missingCodex}
        let file=root.appendingPathComponent("hooks.json");try checkPath(file)
        guard FileManager.default.fileExists(atPath:file.path) else{return ([:],nil)}
        guard let data=try? readFile(file,limit:4_000_000) else{throw Failure.unreadable}
        guard let object=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else{throw Failure.malformed}
        if let hooks=object["hooks"] {
            guard let map=hooks as? [String:Any],map.values.allSatisfy({$0 is [[String:Any]]}) else{throw Failure.malformed}
        }
        return (object,data)
    }
    static func knownCommands(home:URL)->Set<String> {
        let base=support(home:home),fm=FileManager.default
        var commands=Set<String>()
        for (name,hash) in legacyHashes {
            let file=base.appendingPathComponent(name)
            guard let data=try? readFile(file,limit:65536),digest(data)==hash else{continue}
            // shlex.quote leaves safe strings bare; these support paths contain spaces.
            commands.insert("/usr/bin/python3 "+quote(file.path)+" --spool "+quote(base.appendingPathComponent("events").path)+" --host local")
        }
        let receipt=base.appendingPathComponent("native-integration.json")
        if let data=try? readFile(receipt,limit:8192),let value=try? JSONSerialization.jsonObject(with:data) as? [String:String],
           let filename=value["helper"],filename.hasPrefix("radio-hook-"),!filename.contains("/"),let expected=value["sha256"] {
            let file=base.appendingPathComponent(filename)
            if fm.isExecutableFile(atPath:file.path),let bytes=try? readFile(file),digest(bytes)==expected{commands.insert(nativeCommand(helper:file,home:home))}
        }
        return commands
    }
    static func installed(_ object:[String:Any],commands:Set<String>)->Set<String> {
        let hooks=object["hooks"] as? [String:[[String:Any]]] ?? [:]
        return Set(events.filter {event in
            (hooks[event] ?? []).contains {group in
                let matcher=group["matcher"] as? String
                guard matcher==nil || matcher=="" || matcher=="*" else{return false}
                return ((group["hooks"] as? [[String:Any]]) ?? []).contains {handler in
                    handler["type"] as? String=="command" && commands.contains(handler["command"] as? String ?? "") && (handler["enabled"] as? Bool != false)
                }
            }
        })
    }
    static func inspect(root:URL,home:URL)->IntegrationSnapshot {
        do{let (object,_)=try document(root);return IntegrationSnapshot(folderExists:true,installedEvents:installed(object,commands:knownCommands(home:home)).count)}
        catch{return IntegrationSnapshot(folderExists:FileManager.default.fileExists(atPath:root.path),issue:error.localizedDescription)}
    }
    static func atomicWrite(_ bytes:Data,to file:URL)throws {
        try checkPath(file)
        if FileManager.default.fileExists(atPath:file.path){guard try file.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile==true else{throw Failure.unsafePath}}
        let temp=file.deletingLastPathComponent().appendingPathComponent(".radio-"+UUID().uuidString)
        let fd=open(temp.path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0o600)
        guard fd>=0 else{throw Failure.unreadable}
        let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:true)
        defer{try? handle.close();try? FileManager.default.removeItem(at:temp)}
        try handle.write(contentsOf:bytes);try handle.synchronize();try handle.close()
        guard rename(temp.path,file.path)==0 else{throw Failure.unreadable}
    }
    static func privateDirectory(_ directory:URL)throws {
        try checkPath(directory)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        var info=stat()
        guard lstat(directory.path,&info)==0,info.st_mode & S_IFMT == S_IFDIR,info.st_uid==getuid(),info.st_mode & 0o077==0 else{throw Failure.unsafePath}
    }
    @discardableResult static func install(root:URL,home:URL,helper:URL,beforeCommit:(()->Void)?=nil)throws->Int {
        var (object,old)=try document(root)
        let present=installed(object,commands:knownCommands(home:home))
        let missing=events.filter{!present.contains($0)}
        guard !missing.isEmpty else{return 0}
        let helperInfo=try? helper.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
        guard FileManager.default.isExecutableFile(atPath:helper.path),helperInfo?.isRegularFile==true,(helperInfo?.fileSize ?? Int.max)<16_000_000,let bundledBytes=try? Data(contentsOf:helper),!bundledBytes.isEmpty else{throw Failure.missingHelper}
        let base=support(home:home)
        // Validate the owned support chain before creating any executable or event file.
        for component in [home,home.appendingPathComponent("Library"),home.appendingPathComponent("Library/Application Support"),base]{try checkPath(component)}
        try privateDirectory(base);try privateDirectory(base.appendingPathComponent("events"))
        var bytes=bundledBytes
        // Repair missing events with the already installed helper when valid;
        // app upgrades must not silently invalidate existing hook definitions.
        if let receipt=try? readFile(base.appendingPathComponent("native-integration.json"),limit:8192),
           let value=try? JSONSerialization.jsonObject(with:receipt) as? [String:String],let name=value["helper"],!name.contains("/") {
            let oldHelper=base.appendingPathComponent(name)
            if knownCommands(home:home).contains(nativeCommand(helper:oldHelper,home:home)),let oldBytes=try? readFile(oldHelper){bytes=oldBytes}
        }
        let hash=digest(bytes),target=base.appendingPathComponent("radio-hook-"+String(hash.prefix(16)))
        try checkPath(target)
        if FileManager.default.fileExists(atPath:target.path) {
            guard try readFile(target)==bytes else{throw Failure.missingHelper}
        }else{try atomicWrite(bytes,to:target)}
        try FileManager.default.setAttributes([.posixPermissions:0o500],ofItemAtPath:target.path)
        let handler:[String:Any]=["type":"command","command":nativeCommand(helper:target,home:home),"timeout":1]
        var hooks=object["hooks"] as? [String:[[String:Any]]] ?? [:]
        var review:[String:[[String:Any]]]=[:]
        for event in missing {let group:[String:Any]=["hooks":[handler]];hooks[event,default:[]].append(group);review[event]=[group]}
        object["hooks"]=hooks
        let file=root.appendingPathComponent("hooks.json")
        beforeCommit?();try checkPath(file)
        let current=FileManager.default.fileExists(atPath:file.path) ? try readFile(file,limit:4_000_000) : nil
        guard current==old else{throw Failure.concurrentEdit}
        if let old{try atomicWrite(old,to:base.appendingPathComponent("hooks-before-"+UUID().uuidString+".json"))}
        let receipt:[String:String]=["helper":target.lastPathComponent,"sha256":hash]
        try atomicWrite(try JSONSerialization.data(withJSONObject:receipt,options:[.sortedKeys]),to:base.appendingPathComponent("native-integration.json"))
        try atomicWrite(try JSONSerialization.data(withJSONObject:["hooks":review],options:[.prettyPrinted,.sortedKeys]),to:base.appendingPathComponent("native-hook-review.json"))
        try atomicWrite(try JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys]),to:file)
        return missing.count
    }
}
