// Render actual announcement PCM, including callsign crossfades and cue level matching.
import Foundation

@main struct PackPreview {
    static func main() throws {
        guard CommandLine.arguments.count==3 else{fatalError("Usage: preview_packs PROJECT OUTPUT")}
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2])
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let voices=["alfa.wav","digit1.wav"].map{RecordedAudio.Piece(url:root.appendingPathComponent("Assets/Voices/"+$0),isVoice:true)}
        let voiceData=try RecordedAudio.compose(voices)
        let voiceFrames=(voiceData.count-44)/2
        func decode(_ data:Data)->[Float] {
            let bytes=Array(data.dropFirst(44))
            return stride(from:0,to:bytes.count,by:2).map{Float(Int16(bitPattern:UInt16(bytes[$0])|UInt16(bytes[$0+1])<<8))/32767}
        }
        func db(_ rms:Float)->Double{20*log10(Double(max(0.000001,rms)))}
        var report:[[String:Any]]=[]
        for pack in ["boeing","airbus","j11a"] {
            var sequence:[Float]=[]
            for status in ["reading","testing","unknown","compacting","complete","waiting","cancelled","blocked"] {
                let cue=RecordedAudio.Piece(url:root.appendingPathComponent("Assets/SoundPacks/\(pack)/\(status).wav"))
                let data=try RecordedAudio.compose(voices+[cue],matchCueLevel:true)
                let pcm=decode(data),speech=Array(pcm.prefix(voiceFrames)),effect=Array(pcm.dropFirst(voiceFrames))
                report.append(["pack":pack,"status":status,"voice_active_rms_db":db(RecordedAudio.activeRMS(speech)),"cue_active_rms_db":db(RecordedAudio.activeRMS(effect)),"cue_peak":effect.map{abs($0)}.max() ?? 0])
                sequence += pcm + [Float](repeating:0,count:14400)
                try data.write(to:out.appendingPathComponent("\(pack)-\(status).wav"))
            }
            try RecordedAudio.wav(sequence).write(to:out.appendingPathComponent("\(pack)-with-callsign.wav"))
        }
        let data=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:out.appendingPathComponent("levels.json"))
        print(String(data:data,encoding:.utf8)!)
    }
}
