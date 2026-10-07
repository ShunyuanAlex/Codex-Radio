import Foundation

struct LiveHookEvent:Decodable {
    let id:String
    let host:String
    let session:String
    let agent:String?
    let event:String
    let status:String?
    let receivedAt:Double
    var turn:String?=nil
    var toolUse:String?=nil
}

// A user-selected dedicated event directory only. Never opens Codex history or credentials.
final class LiveEventReader {
    private var directory:URL?
    private var connectedAt:Double=0
    private var seen=Set<String>()
    private var order:[String]=[]
    private var seenIDs=Set<String>()
    private var idOrder:[String]=[]
    func connect(_ directory:URL){self.directory=directory;connectedAt=Date().timeIntervalSince1970;seen=[];order=[];seenIDs=[];idOrder=[]}
    func disconnect(){directory=nil;seen=[];order=[];seenIDs=[];idOrder=[]}
    func poll()->[LiveHookEvent] {
        guard let directory,let files=try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.fileSizeKey,.isRegularFileKey,.isSymbolicLinkKey]) else{return []}
        var result:[LiveHookEvent]=[]
        for f in files where f.pathExtension=="json" && f.lastPathComponent.hasPrefix("event-") {
            guard !seen.contains(f.lastPathComponent),let values=try? f.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey,.isSymbolicLinkKey]),values.isRegularFile==true,values.isSymbolicLink != true,(values.fileSize ?? 99999)<8192 else{continue}
            seen.insert(f.lastPathComponent);order.append(f.lastPathComponent)
            guard let data=try? Data(contentsOf:f),let e=try? JSONDecoder().decode(LiveHookEvent.self,from:data),!e.host.isEmpty,!e.session.isEmpty,e.session.count<=256,e.host.count<=128,e.id.count<=256,e.receivedAt>=connectedAt,e.receivedAt<=Date().timeIntervalSince1970+1,Date().timeIntervalSince1970-e.receivedAt<10 else{continue}
            guard !seenIDs.contains(e.id) else{continue}
            seenIDs.insert(e.id);idOrder.append(e.id);result.append(e)
        }
        if order.count>10000 {for key in order.prefix(order.count-10000){seen.remove(key)};order=Array(order.suffix(10000))}
        if idOrder.count>10000 {for key in idOrder.prefix(idOrder.count-10000){seenIDs.remove(key)};idOrder=Array(idOrder.suffix(10000))}
        // Arrival timestamps only; this is not a claim of source/global ordering.
        return result.sorted{$0.receivedAt<$1.receivedAt}
    }
}
