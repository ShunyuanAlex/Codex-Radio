import Foundation

func runStartupTests(_ check:(String,()->Bool)->Void) {
    final class FakeService:LoginItemService {
        var state=LoginItemState.off
        var nextState=LoginItemState.on
        var fail=false
        var registrations=0
        var removals=0
        func register()throws{registrations += 1;if fail{throw NSError(domain:"Test",code:1)};state=nextState}
        func unregister()throws{removals += 1;if fail{throw NSError(domain:"Test",code:2)};state = .off}
    }
    check("首次启动保持静音且使用18%音量") {
        let suite="radio-startup-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
        defer{defaults.removePersistentDomain(forName:suite)}
        let prefs=StartupPreferences.load(from:defaults)
        return !prefs.autoBroadcast && abs(prefs.volume-0.18)<0.0001 && !prefs.shouldEnableBroadcast(consent:true,configured:true,voicesReady:true)
    }
    check("保存的自动播报与音量可恢复，接入或录音缺失时不自动发声") {
        let suite="radio-startup-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
        defer{defaults.removePersistentDomain(forName:suite)}
        defaults.set(true,forKey:StartupPreferences.broadcastKey);defaults.set(0.34,forKey:StartupPreferences.volumeKey)
        let prefs=StartupPreferences.load(from:defaults)
        guard prefs.autoBroadcast,abs(prefs.volume-0.34)<0.0001 else{return false}
        for consent in [false,true]{for configured in [false,true]{for voices in [false,true]{
            guard prefs.shouldEnableBroadcast(consent:consent,configured:configured,voicesReady:voices)==(consent && configured && voices) else{return false}
        }}}
        return true
    }
    check("异常音量限制在0–50%，非有限值回退") {
        StartupPreferences.normalizedVolume(-1)==0 && StartupPreferences.normalizedVolume(1)==0.5 && StartupPreferences.normalizedVolume(.nan)==0.18 && StartupPreferences.normalizedVolume(.infinity)==0.18
    }
    check("登录项显示系统真实状态并响应外部关闭，读取不注册") {
        let service=FakeService();service.state = .on
        let controller=LoginItemController(service:service,installed:true)
        guard controller.state == .on else{return false};service.state = .off;controller.refresh()
        return controller.state == .off && service.registrations==0 && service.removals==0
    }
    check("系统拒绝注册时不虚报已开启") {
        let service=FakeService();service.fail=true;let controller=LoginItemController(service:service,installed:true)
        controller.setEnabled(true)
        return controller.state == .off && !controller.message.isEmpty
    }
    check("待系统允许保持独立状态，不能当作有效自启动") {
        let service=FakeService();service.nextState = .approval;let controller=LoginItemController(service:service,installed:true)
        controller.setEnabled(true)
        return controller.state == .approval && controller.state != .on && controller.state.requested
    }
    check("临时构建和DMG位置不能注册登录项") {
        let service=FakeService();let controller=LoginItemController(service:service,installed:false);controller.setEnabled(true)
        return service.registrations==0 && controller.state == .off && !controller.message.isEmpty
    }
    check("注销失败保留真实已开启状态并显示错误") {
        let service=FakeService();service.state = .on;service.fail=true;let controller=LoginItemController(service:service,installed:true);controller.setEnabled(false)
        return controller.state == .on && !controller.message.isEmpty
    }
    check("登录项重复开启关闭不会重复注册或注销") {
        let service=FakeService();let controller=LoginItemController(service:service,installed:true)
        controller.setEnabled(true);controller.setEnabled(true);controller.setEnabled(false);controller.setEnabled(false)
        return service.registrations==1 && service.removals==1 && controller.state == .off
    }
}
