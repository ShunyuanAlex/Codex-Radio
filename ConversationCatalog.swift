import Foundation
import SQLite3

struct CatalogThread:Equatable {
    let id:String
    let title:String
    let projectID:String
    let projectTitle:String
    let updatedAt:Double
    let createdAt:Double
    let archived:Bool
}

// Read-only metadata adapter for the installed desktop version. No transcripts,
// first messages, tool outputs, credentials, history repair or agent invocation.
enum ConversationCatalog {
    enum Failure:LocalizedError {
        case unavailable,changed,unreadable
        var errorDescription:String? {
            switch self {
            case .unavailable:return "找不到本地 Codex 对话目录"
            case .changed:return "Codex 目录格式已变化；保留当前列表"
            case .unreadable:return "暂时无法读取本地目录；保留当前列表"
            }
        }
    }
    static let week:Double=7*24*60*60
    static func read(root:URL=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"),now:Double=Date().timeIntervalSince1970)throws->[CatalogThread] {
        let database=root.appendingPathComponent("state_5.sqlite")
        guard FileManager.default.fileExists(atPath:database.path) else{throw Failure.unavailable}
        var db:OpaquePointer?
        guard sqlite3_open_v2(database.path,&db,SQLITE_OPEN_READONLY|SQLITE_OPEN_NOMUTEX,nil)==SQLITE_OK,let db else{if let db{sqlite3_close(db)};throw Failure.unreadable}
        defer{sqlite3_close(db)}
        sqlite3_busy_timeout(db,500)
        sqlite3_exec(db,"PRAGMA query_only=ON",nil,nil,nil)
        func rows(_ sql:String,_ since:Double?=nil)throws->[[String?]] {
            var statement:OpaquePointer?
            guard sqlite3_prepare_v2(db,sql,-1,&statement,nil)==SQLITE_OK,let statement else{throw Failure.changed}
            defer{sqlite3_finalize(statement)}
            if let since{sqlite3_bind_double(statement,1,since)}
            var result:[[String?]]=[]
            while true {
                let code=sqlite3_step(statement)
                if code==SQLITE_DONE{return result}
                guard code==SQLITE_ROW else{throw Failure.unreadable}
                result.append((0..<sqlite3_column_count(statement)).map{col in guard let s=sqlite3_column_text(statement,col) else{return nil};return String(cString:s)})
            }
        }
        let columns=Set(try rows("PRAGMA table_info(threads)").compactMap{$0.count>1 ? $0[1] : nil})
        guard Set(["id","name","source","thread_source","project_id","updated_at","created_at","cwd","archived"]).isSubset(of:columns) else{throw Failure.changed}
        let globals=try dictionary(root.appendingPathComponent(".codex-global-state.json"),maxBytes:16_000_000)
        let projects=globals["local-projects"] as? [String:[String:Any]] ?? [:]
        let assignments=globals["thread-project-assignments"] as? [String:[String:Any]] ?? [:]
        let membershipHosts=globals["thread-project-membership-host-ids"] as? [String:String] ?? [:]
        let projectless=Set(globals["projectless-thread-ids"] as? [String] ?? [])
        let mappings=globals["app-server-project-id-by-legacy-project-id-by-host"] as? [String:[String:String]] ?? [:]
        let ids=mappings["local:"+root.path] ?? [:]
        let reverse=Dictionary(ids.map{($0.value,$0.key)},uniquingKeysWith:{a,_ in a})
        var projectNames:[String:String]=[:]
        for (id,p) in projects {if let name=p["name"] as? String{projectNames[id]=name}}
        for row in (try? rows("SELECT id,name FROM projects")) ?? [] {
            if let id=row[0],let name=row[1]{let key=reverse[id] ?? id;if projectNames[key]==nil{projectNames[key]=name}}
        }
        var indexedNames:[String:String]=[:]
        let titleFile=root.appendingPathComponent("session_index.jsonl")
        if let size=try? titleFile.resourceValues(forKeys:[.fileSizeKey]).fileSize,size<16_000_000,let text=try? String(contentsOf:titleFile,encoding:.utf8) {
            for line in text.split(separator:"\n") {
                if let data=String(line).data(using:.utf8),let value=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let id=value["id"] as? String,let name=value["thread_name"] as? String{indexedNames[id]=name}
            }
        }
        let lastUse=columns.contains("recency_at") ? "MAX(updated_at,COALESCE(recency_at,updated_at))" : "updated_at"
        let sql="SELECT id,name,project_id,\(lastUse),created_at,cwd,archived FROM threads WHERE \(lastUse)>=? AND source IN ('vscode','cli','appServer','app_server') AND COALESCE(thread_source,'user') NOT IN ('subagent','guardian_review') ORDER BY \(lastUse) DESC,id"
        return try rows(sql,now-week).compactMap {r in
            guard let id=r[0],let updated=Double(r[3] ?? ""),updated<=now+300 else{return nil}
            if let host=membershipHosts[id],host != "local"{return nil}
            let assignment=assignments[id]
            if let kind=assignment?["projectKind"] as? String,kind != "local"{return nil}
            var project=assignment?["projectId"] as? String ?? r[2].map{reverse[$0] ?? $0}
            if projectless.contains(id){project=nil}
            if project==nil && !projectless.contains(id),let cwd=r[5] {
                let matches=projects.filter{_,p in (p["rootPaths"] as? [String] ?? []).contains(cwd)}.map(\.key)
                if matches.count==1{project=matches[0]}
            }
            let projectID=project ?? "unassigned"
            let name=r[1].flatMap{$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? nil : $0} ?? indexedNames[id] ?? "未命名对话"
            return CatalogThread(id:id,title:name,projectID:projectID,projectTitle:projectNames[projectID] ?? (project==nil ? "独立对话" : "项目 "+String(projectID.suffix(6))),updatedAt:updated,createdAt:Double(r[4] ?? "") ?? updated,archived:r[6]=="1")
        }
    }
    private static func dictionary(_ url:URL,maxBytes:Int)throws->[String:Any] {
        guard FileManager.default.fileExists(atPath:url.path) else{return [:]}
        guard let size=try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize,size<maxBytes,let data=try? Data(contentsOf:url),let value=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else{throw Failure.unreadable}
        return value
    }
}
