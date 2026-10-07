import Foundation

enum ConversationState:String,Codable {
    case idle,submitted,running,waiting,returned,closing,interrupted,error,compacting
    var title:String {
        switch self {
        case .idle:return "待命"
        case .submitted:return "消息已提交"
        case .running:return "处理中"
        case .waiting:return "等待确认"
        case .returned:return "工具已返回"
        case .closing:return "本轮收尾"
        case .interrupted:return "已停止"
        case .error:return "工具报错"
        case .compacting:return "正在压缩上下文"
        }
    }
    var cue:RadioStatus? {
        switch self {
        case .idle:return nil
        case .submitted:return .reading
        case .running:return .testing
        case .waiting:return .waiting
        case .returned:return .unknown
        case .closing:return .complete
        case .interrupted:return .cancelled
        case .error:return .blocked
        case .compacting:return .compacting
        }
    }
}

struct ConversationActivity:Codable {
    var state:ConversationState = .idle
    var detail="尚未收到本轮实时事件"
    var lastAt:Double=0
    var turn:String?
    var tools=Set<String>()
    var agents=Set<String>()
    var preCompactionState:ConversationState?
    // Child activity shares its parent channel; it cannot close or stop the parent.
    mutating func receive(_ e:LiveHookEvent)->RadioStatus? {
        guard e.receivedAt>=lastAt else{return nil}
        lastAt=e.receivedAt
        let child=e.agent != nil
        if child && (state == .closing || state == .interrupted){
            if e.event == "SubagentStop",let id=e.agent{agents.remove(id)}
            return nil
        }
        if child,let active=turn,let incoming=e.turn,active != incoming{return nil}
        if !child && state == .interrupted && ["PostToolUse","PreCompact","PostCompact"].contains(e.event){return nil}
        let suffix=child ? " · 子代理" : ""
        let key=e.toolUse.flatMap{$0.isEmpty ? nil : (e.agent ?? "main")+":"+$0}
        switch e.event {
        case "PreCompact":
            if !child {
                if state != .compacting{preCompactionState=state}
                state = .compacting
            }
            detail="正在压缩上下文"+suffix;return .compacting
        case "PostCompact":
            if !child {
                if state == .compacting{state=preCompactionState ?? .running}
                preCompactionState=nil
            }
            detail="上下文压缩已完成"+suffix;return nil
        case "UserPromptSubmit":
            if !child {
                let next=e.turn.flatMap{$0.isEmpty ? nil : $0}
                if state == .idle || state == .closing || state == .interrupted || (next != nil && next != turn){tools=[];agents=[];preCompactionState=nil}
                if let next{turn=next}
                state = tools.isEmpty && agents.isEmpty ? .submitted : .running
                detail="已收到提示提交事件"+(state == .running ? " · 当前处理继续" : "")
                return .reading
            }
        case "PreToolUse":
            if let key{tools.insert(key)}
            state = .running;detail="正在执行工具"+suffix;return .testing
        case "PostToolUse":
            if let key{tools.remove(key)}
            if e.status=="blocked"{state = .error;detail="工具报告了明确错误"+suffix;return .blocked}
            state = tools.isEmpty && agents.isEmpty ? .returned : .running
            detail=(e.status=="success" ? "工具返回，退出码为 0" : "收到工具结果")+suffix
            return .unknown
        case "PermissionRequest":state = .waiting;detail="需要你确认权限"+suffix;return .waiting
        case "Interrupt":
            if !child{state = .interrupted;tools=[];agents=[];preCompactionState=nil;detail="当前轮已中断";return .cancelled}
        case "Stop":
            if !child {state = .closing;tools=[];preCompactionState=nil;detail="模型准备结束本轮";return .complete}
        case "SubagentStart":
            if let id=e.agent{agents.insert(id)}
            state = .running;detail="子代理开始处理";return .testing
        case "SubagentStop":
            if let id=e.agent{agents.remove(id);tools=Set(tools.filter{!$0.hasPrefix(id+":")})}
            if state != .closing && state != .interrupted{state = tools.isEmpty && agents.isEmpty ? .returned : .running;detail="子代理已返回"}
            return .unknown
        case "SessionEnd":
            if !child{state = .idle;tools=[];agents=[];preCompactionState=nil;detail="会话已关闭"}
        case "SessionStart":
            if state == .idle{detail="会话已连接，等待下一轮"}
        default:break
        }
        return nil
    }
}
