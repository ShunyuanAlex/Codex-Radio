// Offline comparison renders through the same composer as the menu bar app.
import Foundation

@main struct VoicePreview {
    static func main() throws {
        guard CommandLine.arguments.count==4 else{fatalError("Usage: preview OLD_VOICES NEW_VOICES OUTPUT")}
        let old=URL(fileURLWithPath:CommandLine.arguments[1]),new=URL(fileURLWithPath:CommandLine.arguments[2]),output=URL(fileURLWithPath:CommandLine.arguments[3])
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var results:[[String:Any]]=[]
        for (name,files) in [("Alpha-1",["alfa","digit1"]),("Bravo-2",["bravo","digit2"]),("Alpha-12",["alfa","digit1","digit2"]),("Foxtrot-56",["foxtrot","digit5","digit6"])] {
            var durations:[String:Double]=[:]
            for (label,root,crossfade) in [("before",old,false),("after",new,true)] {
                let pieces=files.map{RecordedAudio.Piece(url:root.appendingPathComponent($0+".wav"),isVoice:crossfade)}
                let data=try RecordedAudio.compose(pieces)
                try data.write(to:output.appendingPathComponent(name+"-"+label+".wav"))
                durations[label]=Double((data.count-44)/2)/RecordedAudio.rate
            }
            results.append(["sample":name,"before_seconds":durations["before"]!,"after_seconds":durations["after"]!,"saved_ms":(durations["before"]!-durations["after"]!)*1000])
        }
        let data=try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:output.appendingPathComponent("comparison.json"))
        print(String(data:data,encoding:.utf8)!)
    }
}
