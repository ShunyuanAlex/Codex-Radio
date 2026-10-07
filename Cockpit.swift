import SwiftUI

enum FlightDeck {
    static let background=Color(red:0.085,green:0.105,blue:0.12)
    static let panel=Color(red:0.14,green:0.17,blue:0.19)
    static let inset=Color(red:0.035,green:0.065,blue:0.075)
    static let text=Color(red:0.89,green:0.91,blue:0.88)
    static let muted=Color(red:0.60,green:0.66,blue:0.67)
    static let cyan=Color(red:0.43,green:0.81,blue:0.85)
    static let green=Color(red:0.53,green:0.85,blue:0.64)
    static let amber=Color(red:0.98,green:0.73,blue:0.38)
    static let line=Color.white.opacity(0.10)
}

struct FlightButtonStyle:ButtonStyle {
    var selected=false
    var tint=FlightDeck.cyan
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.system(size:12,weight:.medium))
            .foregroundColor(!enabled ? FlightDeck.muted.opacity(0.45) : selected ? tint : FlightDeck.text)
            .padding(.horizontal,12).padding(.vertical,9)
            .background(LinearGradient(colors:[selected ? tint.opacity(0.12) : .white.opacity(0.06),FlightDeck.inset.opacity(0.65)],startPoint:.top,endPoint:.bottom))
            .clipShape(RoundedRectangle(cornerRadius:5))
            .overlay(RoundedRectangle(cornerRadius:5).stroke(selected ? tint.opacity(0.65) : .white.opacity(enabled ? 0.16 : 0.05),lineWidth:1))
            .shadow(color:.black.opacity(0.35),radius:1,y:2)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct FlightSwitch:View {
    let title:String
    @Binding var isOn:Bool
    var pending=false
    var body:some View {
        Button{isOn.toggle()}label:{
            VStack(spacing:5) {
                Text(pending ? "WAIT" : isOn ? "ON" : "OFF").font(.system(size:11,weight:.bold,design:.monospaced)).tracking(1)
                Capsule().fill(isOn ? (pending ? FlightDeck.amber : FlightDeck.green) : FlightDeck.muted.opacity(0.22)).frame(width:28,height:3)
            }.frame(width:42,height:24)
        }.buttonStyle(FlightButtonStyle(selected:isOn,tint:pending ? FlightDeck.amber : FlightDeck.green))
            .accessibilityLabel(title).accessibilityValue(pending ? "等待系统允许" : isOn ? "开启" : "关闭")
            .help(title+(isOn ? "：已开启" : "：已关闭"))
    }
}

struct FlightSection<Content:View>:View {
    let title:String
    let code:String
    @ViewBuilder var content:Content
    init(_ title:String,code:String,@ViewBuilder content:()->Content){self.title=title;self.code=code;self.content=content()}
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(spacing:10) {
                Text(code).font(.system(size:10,weight:.medium,design:.monospaced)).tracking(1.1).foregroundColor(FlightDeck.muted)
                Rectangle().fill(FlightDeck.line).frame(height:1)
                Text(title).font(.system(size:12,weight:.semibold)).fixedSize()
            }
            content
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
            .background(FlightDeck.panel.opacity(0.75)).clipShape(RoundedRectangle(cornerRadius:7))
            .overlay(RoundedRectangle(cornerRadius:7).stroke(FlightDeck.line,lineWidth:1))
    }
}

struct FlightReadout:View {
    let title:String
    let value:String
    var tint=FlightDeck.cyan
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text(title).font(.system(size:10,weight:.medium,design:.monospaced)).tracking(0.6).foregroundColor(FlightDeck.muted)
            Text(value).font(.system(size:17,weight:.medium,design:.monospaced)).foregroundColor(tint).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth:.infinity,alignment:.leading).padding(13).background(FlightDeck.inset)
            .clipShape(RoundedRectangle(cornerRadius:5)).overlay(RoundedRectangle(cornerRadius:5).stroke(.black.opacity(0.5),lineWidth:1))
    }
}

struct FlightModeSelector:View {
    @ObservedObject var store:RadioStore
    var body:some View {
        HStack(spacing:8) {
            ForEach(ListeningMode.allCases,id:\.rawValue){mode in
                Button{store.setMode(mode.rawValue)}label:{
                    HStack(spacing:7){Circle().fill(store.mode==mode.rawValue ? FlightDeck.cyan : FlightDeck.muted.opacity(0.2)).frame(width:4,height:4);Text(mode.title)}.frame(maxWidth:.infinity)
                }.buttonStyle(FlightButtonStyle(selected:store.mode==mode.rawValue)).accessibilityLabel("收听模式："+mode.title).accessibilityValue(store.mode==mode.rawValue ? "已选择" : "未选择")
            }
        }
    }
}

struct StartupSettings:View {
    @ObservedObject var store:RadioStore
    @ObservedObject var login:LoginItemController
    var body:some View {
        FlightSection("启动与运行",code:"STARTUP") {
            HStack(spacing:20) {
                VStack(alignment:.leading,spacing:6) {
                    Text("登录时自动启动").font(.system(size:13,weight:.medium))
                    Text("登录这台 Mac 后，Radio 自动常驻菜单栏。").font(.system(size:11)).foregroundColor(FlightDeck.muted)
                    Text(login.installed ? login.state.title : "先将应用安装到应用程序文件夹").font(.system(size:10)).foregroundColor(login.state == .on ? FlightDeck.green : FlightDeck.amber)
                }.frame(maxWidth:.infinity,alignment:.leading)
                FlightSwitch(title:"登录时自动启动",isOn:Binding(get:{login.state.requested},set:{login.setEnabled($0)}),pending:login.state == .approval).disabled(!login.installed && !login.state.requested)
            }
            if login.state == .approval {
                HStack{Text("请在 macOS 登录项中允许 Radio。").font(.system(size:11)).foregroundColor(FlightDeck.amber);Spacer();Button("打开系统登录项"){login.openSystemSettings()}}
            }
            if !login.message.isEmpty{Text(login.message).font(.system(size:11)).foregroundColor(FlightDeck.amber).textSelection(.enabled)}
            Divider().overlay(FlightDeck.line)
            HStack(spacing:20) {
                VStack(alignment:.leading,spacing:6) {
                    Text("启动后自动启用播报").font(.system(size:13,weight:.medium))
                    Text("下次启动使用保存的音量与模式；关闭时静音启动。").font(.system(size:11)).foregroundColor(FlightDeck.muted)
                    if !store.metadataAllowed || !store.integration.complete{Text("完成 Codex 接入后生效。").font(.system(size:10)).foregroundColor(FlightDeck.amber)}
                }.frame(maxWidth:.infinity,alignment:.leading)
                FlightSwitch(title:"启动后自动启用播报",isOn:Binding(get:{store.autoBroadcast},set:{store.setAutoBroadcast($0)}))
            }
        }
    }
}
