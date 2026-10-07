import Foundation
import AVFoundation

enum RecordedAudio {
    static let rate=24000.0
    static let callsignGap=0.0
    static let voiceCrossfade=0.012
    struct Piece {let url:URL;var start:Double=0;var duration:Double=3;var gap:Double=0;var isVoice=false}
    enum Failure:Error {case invalidAudio,missingRecording}
    static func samples(_ piece:Piece)throws->[Float] {
        let file=try AVAudioFile(forReading:piece.url,commonFormat:.pcmFormatFloat32,interleaved:false)
        let format=file.processingFormat
        guard file.length>0,format.sampleRate>0,format.channelCount>0,format.channelCount<=8 else{throw Failure.invalidAudio}
        let start=AVAudioFramePosition(max(0,piece.start)*format.sampleRate)
        guard start<file.length else{throw Failure.invalidAudio}
        let count=min(file.length-start,AVAudioFramePosition(min(3,piece.duration)*format.sampleRate))
        guard count>0,let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(count)) else{throw Failure.invalidAudio}
        file.framePosition=start;try file.read(into:buffer,frameCount:AVAudioFrameCount(count))
        guard let channels=buffer.floatChannelData,buffer.frameLength>0 else{throw Failure.invalidAudio}
        let length=Int(buffer.frameLength),channelCount=Int(format.channelCount)
        var mono=[Float](repeating:0,count:length)
        for c in 0..<channelCount {for i in 0..<length {mono[i]+=channels[c][i]/Float(channelCount)}}
        let outputCount=max(1,Int(Double(length)*rate/format.sampleRate))
        return (0..<outputCount).map {i in
            let position=Double(i)*format.sampleRate/rate, a=min(length-1,Int(position)), b=min(length-1,a+1)
            let value=mono[a]+(mono[b]-mono[a])*Float(position-Double(a))
            return value.isFinite ? min(0.98,max(-0.98,value)) : 0
        }
    }
    static func stitch(_ pieces:[([Float],Double)],overlaps:[Double]=[])->[Float] {
        var result:[Float]=[]
        for (i,piece) in pieces.enumerated() {
            var overlap=0
            if i>0,i<overlaps.count,pieces[i-1].1<=0 {
                // Bound both sides so a short clip cannot overlap two neighbours at once.
                overlap=min(max(0,Int(overlaps[i]*rate)),pieces[i-1].0.count/2,piece.0.count/2)
                if overlap<2{overlap=0}
            }
            if overlap>0 {
                let start=result.count-overlap
                for n in 0..<overlap {
                    let mix=Float(n)/Float(overlap-1)
                    // Linear gain keeps the blend inside the input peak range.
                    result[start+n]=result[start+n]*(1-mix)+piece.0[n]*mix
                }
            }
            result.append(contentsOf:piece.0.dropFirst(overlap))
            if i+1<pieces.count {result.append(contentsOf:repeatElement(0,count:max(0,Int(piece.1*rate))))}
        }
        return result
    }
    static func wav(_ samples:[Float])->Data {
        var data=Data()
        func ascii(_ s:String){data.append(contentsOf:s.utf8)}
        func u16(_ v:UInt16){var n=v.littleEndian;withUnsafeBytes(of:&n){data.append(contentsOf:$0)}}
        func u32(_ v:UInt32){var n=v.littleEndian;withUnsafeBytes(of:&n){data.append(contentsOf:$0)}}
        ascii("RIFF");u32(UInt32(samples.count*2+36));ascii("WAVEfmt ");u32(16);u16(1);u16(1);u32(UInt32(rate));u32(UInt32(rate*2));u16(2);u16(16);ascii("data");u32(UInt32(samples.count*2))
        for f in samples {u16(UInt16(bitPattern:Int16(min(0.98,max(-0.98,f))*32767)))}
        return data
    }
    // Short cues are too brief for integrated loudness measurements. Compare
    // active 20 ms RMS windows, excluding windows more than 20 dB below the peak.
    static func activeRMS(_ samples:[Float])->Float {
        guard !samples.isEmpty else{return 0}
        let window=Int(rate*0.02)
        let powers=stride(from:0,to:samples.count,by:window).map {start -> Double in
            let end=min(samples.count,start+window)
            return samples[start..<end].reduce(0){$0+Double($1)*Double($1)}/Double(end-start)
        }
        let gate=max(0.0000001,(powers.max() ?? 0)*0.01)
        let active=powers.filter{$0>=gate}
        return active.isEmpty ? 0 : Float(sqrt(active.reduce(0,+)/Double(active.count)))
    }
    static func matchLevel(_ cue:[Float],to reference:[Float])->[Float] {
        let source=activeRMS(cue),target=activeRMS(reference)
        guard source>0.0001,target>0.0001 else{return cue}
        let gain=min(64,target/source),peak=cue.map{abs($0)}.max() ?? 0
        if peak*gain<=0.90{return cue.map{$0*gain}}
        // A soft ceiling controls brief click transients without hard clipping.
        // Only peak-constrained cues take this path; human speech stays intact.
        func limited(_ gain:Float)->[Float]{cue.map{0.90*tanh($0*gain/0.90)}}
        var low:Float=0,high:Float=64
        for _ in 0..<20 {
            let mid=(low+high)/2
            if activeRMS(limited(mid))<target{low=mid}else{high=mid}
        }
        return limited((low+high)/2)
    }
    static func compose(_ pieces:[Piece],matchCueLevel:Bool=false)throws->Data {
        guard !pieces.isEmpty else{throw Failure.missingRecording}
        let overlaps=pieces.indices.map{i in i>0 && pieces[i-1].isVoice && pieces[i].isVoice ? voiceCrossfade : 0}
        let decoded=try pieces.map{(try samples($0),$0.gap)}
        if matchCueLevel,let cueStart=pieces.firstIndex(where:{!$0.isVoice}),cueStart>0,
           pieces[cueStart...].allSatisfy({!$0.isVoice}) {
            let speech=stitch(Array(decoded[..<cueStart]),overlaps:Array(overlaps[..<cueStart]))
            let cue=stitch(Array(decoded[cueStart...]))
            return wav(stitch([(speech,pieces[cueStart-1].gap),(matchLevel(cue,to:speech),0)]))
        }
        return wav(stitch(decoded,overlaps:overlaps))
    }
}
