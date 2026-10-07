// Codex Radio native observer. No network, transcript access, playback or hook decisions.
import Foundation
import CryptoKit
import Darwin

enum HookCollector {
    static let events=["SessionStart","SessionEnd","UserPromptSubmit","PreToolUse","PostToolUse","PermissionRequest","Stop","Interrupt","SubagentStart","SubagentStop","PreCompact","PostCompact"]
    static func normalize(_ payload:[String:Any],now:Double=Date().timeIntervalSince1970)->[String:Any]? {
        func short(_ key:String)->String{String((payload[key] as? String ?? "").prefix(256))}
        let event=short("hook_event_name"),session=short("session_id"),turn=short("turn_id"),tool=short("tool_use_id"),agent=short("agent_id")
        guard events.contains(event),!session.isEmpty else{return nil}
        var status:String?
        switch event {
        case "PreToolUse":status=["apply_patch","Edit","Write"].contains(short("tool_name")) ? "editing" : "testing"
        case "PostToolUse":
            status="unknown"
            if let response=payload["tool_response"] as? [String:Any] {
                if let flag=response["isError"] as? NSNumber,CFGetTypeID(flag)==CFBooleanGetTypeID(),flag.boolValue{status="blocked"}
                else if short("tool_name")=="Bash",let code=response["exit_code"] as? NSNumber,CFGetTypeID(code) != CFBooleanGetTypeID(),["c","s","i","l","q","C","S","I","L","Q"].contains(String(cString:code.objCType)){status=code.intValue==0 ? "success" : "blocked"}
            }
        case "PermissionRequest":status="waiting"
        case "Interrupt":status="cancelled"
        case "Stop":status="complete"
        case "SubagentStart":status="delegating"
        case "SubagentStop":status="unknown"
        case "PreCompact":status="compacting"
        default:break
        }
        var id=UUID().uuidString
        if ["PreToolUse","PostToolUse"].contains(event),!turn.isEmpty,!tool.isEmpty,
           let data=try? JSONSerialization.data(withJSONObject:["local",session,turn,tool,event,agent]) {
            id=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
        }
        return ["id":id,"host":"local","session":session,"turn":turn,"agent":agent.isEmpty ? NSNull() : agent as Any,"toolUse":tool,"event":event,"status":status as Any? ?? NSNull(),"receivedAt":now]
    }
    static func save(_ event:[String:Any],to directory:URL)throws {
        let fm=FileManager.default
        guard directory.path.hasPrefix("/"),directory.standardizedFileURL.path==directory.resolvingSymlinksInPath().path else{throw CocoaError(.fileWriteNoPermission)}
        try fm.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        var info=stat()
        guard lstat(directory.path,&info)==0,info.st_mode & S_IFMT == S_IFDIR,info.st_uid==getuid(),info.st_mode & 0o077==0 else{throw CocoaError(.fileWriteNoPermission)}
        for file in (try? fm.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)) ?? [] where file.lastPathComponent.hasPrefix("event-") && file.pathExtension=="json" {
            var entry=stat()
            if lstat(file.path,&entry)==0,entry.st_mode & S_IFMT == S_IFREG,entry.st_uid==getuid(),Double(entry.st_mtimespec.tv_sec)<Date().timeIntervalSince1970-60{try? fm.removeItem(at:file)}
        }
        let token=UUID().uuidString,temp=directory.appendingPathComponent(".pending-"+token)
        let fd=open(temp.path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0o600)
        guard fd>=0 else{throw CocoaError(.fileWriteNoPermission)}
        let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:true)
        defer{try? handle.close();try? fm.removeItem(at:temp)}
        try handle.write(contentsOf:JSONSerialization.data(withJSONObject:event,options:[.sortedKeys]))
        try handle.synchronize();try handle.close()
        guard rename(temp.path,directory.appendingPathComponent("event-"+token+".json").path)==0 else{throw CocoaError(.fileWriteUnknown)}
    }
}

@main struct CodexRadioHook {
    static func main() {
        defer{print("{}")}
        let args=CommandLine.arguments
        guard args.count==3,args[1]=="--spool",args[2].hasPrefix("/") else{return}
        do {
            var input=Data()
            while let chunk=try FileHandle.standardInput.read(upToCount:min(65536,1048577-input.count)),!chunk.isEmpty {
                input.append(chunk);if input.count>1048576{return}
            }
            guard let payload=try JSONSerialization.jsonObject(with:input) as? [String:Any],let event=HookCollector.normalize(payload) else{return}
            try HookCollector.save(event,to:URL(fileURLWithPath:args[2]))
        }catch{fputs("Codex Radio could not record this event\n",stderr)}
    }
}
