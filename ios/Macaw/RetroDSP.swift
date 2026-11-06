import Foundation

/// The sound effects (Settings > Sound effect), ported line by line from the web player's retroDSP (index.html), so a
/// song sounds the same in the app as it did there. Not live: each song is rendered once into a 16-bit stereo WAV that
/// then replaces the song's source at the same position (lock screen and seeking keep working).
/// Gramophone and Old radio: 22.05 kHz mono in, a device in a room out. Vinyl: 32 kHz stereo, keeps the song's clarity,
/// adds the groove's tone, muddy stretches, hiss, generated crackle and real crackle taken from Nick's vinyl rip.
enum RetroDSP {
    static func rate(_ mode: String) -> Double { mode == "vinyl" ? 32000 : 22050 }

    /// x: the song (mono, or the left side for Vinyl), xr: the right side (Vinyl only). Returns interleaved 16-bit stereo.
    static func render(_ x: inout [Float], _ xr: inout [Float]?, sr: Double, mode: String) -> [Int16] {
        if mode == "vinyl" { return vinyl(&x, &xr, sr: sr) }
        return device(x, sr: sr, mode: mode)
    }

    // MARK: shared parts

    /// The web player's random numbers (mulberry32): the same song + preset gives the same crackles every time.
    struct Rnd {
        var seed: UInt32
        mutating func next() -> Double {
            seed = seed &+ 0x6d2b79f5
            var t = (seed ^ (seed >> 15)) &* (1 | seed)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double(t ^ (t >> 14)) / 4294967296
        }
    }

    /// RBJ biquad, applied in place to a whole buffer.
    static func bq(_ type: String, _ f0: Double, _ Q: Double, _ g: Double = 0, sr: Double, _ buf: inout [Float]) {
        let f = min(f0, sr * 0.45), w = 2 * Double.pi * f / sr, c = cos(w), a = sin(w) / (2 * Q), A = pow(10, g / 40)
        var b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double
        switch type {
        case "lp": b0 = (1 - c) / 2; b1 = 1 - c; b2 = b0; a0 = 1 + a; a1 = -2 * c; a2 = 1 - a
        case "hp": b0 = (1 + c) / 2; b1 = -(1 + c); b2 = b0; a0 = 1 + a; a1 = -2 * c; a2 = 1 - a
        case "hs":
            let s = 2 * sqrt(A) * a
            b0 = A * ((A + 1) + (A - 1) * c + s); b1 = -2 * A * ((A - 1) + (A + 1) * c); b2 = A * ((A + 1) + (A - 1) * c - s)
            a0 = (A + 1) - (A - 1) * c + s; a1 = 2 * ((A - 1) - (A + 1) * c); a2 = (A + 1) - (A - 1) * c - s
        default: b0 = 1 + a * A; b1 = -2 * c; b2 = 1 - a * A; a0 = 1 + a / A; a1 = -2 * c; a2 = 1 - a / A
        }
        b0 /= a0; b1 /= a0; b2 /= a0; a1 /= a0; a2 /= a0
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        buf.withUnsafeMutableBufferPointer { p in
            for i in 0..<p.count {
                let v = Double(p[i]), y = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                x2 = x1; x1 = v; y2 = y1; y1 = y; p[i] = Float(y)
            }
        }
    }

    private static func limit(_ v0: Double, _ k1: Double) -> Int16 {
        var v = v0 * k1
        if v > 0.97 { v = 0.97 + tanh((v - 0.97) * 10) * 0.03 } else if v < -0.97 { v = -0.97 - tanh((-v - 0.97) * 10) * 0.03 }
        return Int16(max(-32768, min(32767, (v * 32767).rounded())))
    }

    // MARK: Gramophone / Old radio

    private struct Preset {
        var hp: (Double, Int), lp: (Double, Int), pk: (Double, Double, Double), drive: Double, wow: (Double, Double), flut: (Double, Double)
        var crk: Double, crkA: Double, pop: Double, popA: Double, tick: (Double, Double), hiss: Double, rev: Double, room: Double
        var hum: Double, fade: Double, stat: Double, dry: Double, er: Double, late: Double, t60: Double
    }
    private static let presets: [String: Preset] = [
        "gram": Preset(hp: (220, 2), lp: (3900, 2), pk: (1500, 4.5, 1.1), drive: 2.4, wow: (0.55, 0.0024), flut: (7.2, 0.0007), crk: 10, crkA: 0.11, pop: 0.35,
                       popA: 0.5, tick: (1.3, 0.05), hiss: 0.014, rev: 0.1, room: 0.22, hum: 0, fade: 0, stat: 0, dry: 0.78, er: 0.5, late: 0.3, t60: 1.0),
        "radio": Preset(hp: (380, 2), lp: (3100, 3), pk: (1900, 5, 1.2), drive: 3.2, wow: (0.13, 0.0007), flut: (0, 0), crk: 2, crkA: 0.05, pop: 0.06,
                        popA: 0.2, tick: (0, 0), hiss: 0.022, rev: 0.12, room: 0.18, hum: 0.005, fade: 0.25, stat: 0.05, dry: 0.74, er: 0.55, late: 0.36, t60: 1.15),
    ]

    private static func device(_ x: [Float], sr: Double, mode: String) -> [Int16] {
        let P = presets[mode] ?? presets["gram"]!
        let n = x.count, TAU = 2 * Double.pi
        var r = Rnd(seed: 0x9e3779b9 ^ UInt32(truncatingIfNeeded: n))
        func band(_ b: inout [Float]) {
            for _ in 0..<P.hp.1 { bq("hp", P.hp.0, 0.707, sr: sr, &b) }
            for _ in 0..<P.lp.1 { bq("lp", P.lp.0, 0.707, sr: sr, &b) }
        }
        // 1. wow + flutter
        var y = [Float](repeating: 0, count: n)
        let D = 4096, M = D - 1
        var ring = [Float](repeating: 0, count: D)
        let A1 = P.wow.1 / (TAU * P.wow.0) * sr, A2 = P.flut.0 != 0 ? P.flut.1 / (TAU * P.flut.0) * sr : 0, base = 8 + A1 + A2 + 4
        var drift = 0.0, dv = 0.0
        for i in 0..<n {
            ring[i & M] = x[i]
            if i & 255 == 0 { dv += (r.next() - 0.5) * 0.02; dv *= 0.97; drift = max(-1, min(1, drift + dv)) }
            let t = Double(i) / sr, d = base + A1 * (sin(TAU * P.wow.0 * t) + 0.25 * drift) + A2 * sin(TAU * P.flut.0 * t + 1.3)
            let rr = Double(i) - d, i0 = Int(floor(rr)), fr = Float(rr - Double(i0))
            y[i] = i0 < 0 ? 0 : ring[i0 & M] * (1 - fr) + ring[(i0 + 1) & M] * fr
        }
        // 2. the band + the honk
        band(&y); bq("pk", P.pk.0, P.pk.2, P.pk.1, sr: sr, &y)
        // 3. radio: the signal swells and fades a little
        if P.fade != 0 {
            var lv = 0.0, v = 0.0
            for i in 0..<n {
                if i & 511 == 0 { v += (r.next() - 0.5) * 0.04; v *= 0.985; lv = max(-1, min(1, lv + v)) }
                y[i] *= Float(1 - P.fade * (0.5 + 0.5 * lv))
            }
        }
        // 4. warmth: normalise, then soft saturation
        var pk: Float = 1e-6
        for v in y { let a = abs(v); if a > pk { pk = a } }
        let g = P.drive, tg = tanh(g), k0 = 0.9 / Double(pk)
        for i in 0..<n { y[i] = Float(tanh(g * Double(y[i]) * k0) / tg) }
        // 5. the box: a very short resonance inside the cabinet (four combs, two all-passes)
        if P.rev != 0 {
            var cb = [29.7, 37.1, 41.1, 43.7].map { ms -> (b: [Float], L: Int, i: Int, lp: Float) in
                let L = max(1, Int((ms * P.room * sr / 1000).rounded())); return ([Float](repeating: 0, count: L), L, 0, 0)
            }
            var ap = [5.0, 1.7].map { ms -> (b: [Float], L: Int, i: Int) in
                let L = max(1, Int((ms * sr / 1000).rounded())); return ([Float](repeating: 0, count: L), L, 0)
            }
            for i in 0..<n {
                let v = y[i]; var w: Float = 0
                for c in 0..<cb.count {
                    let o = cb[c].b[cb[c].i]; cb[c].lp = o * 0.7 + cb[c].lp * 0.3
                    cb[c].b[cb[c].i] = v + cb[c].lp * 0.72; cb[c].i = (cb[c].i + 1) % cb[c].L; w += o
                }
                w *= 0.25
                for a in 0..<ap.count {
                    let o = ap[a].b[ap[a].i], z = w + o * 0.5; ap[a].b[ap[a].i] = z; w = o - z * 0.5; ap[a].i = (ap[a].i + 1) % ap[a].L
                }
                y[i] = v + w * Float(P.rev)
            }
        }
        // 6. surface noise: built separately, shaped, then laid on top
        var hiss = [Float](repeating: 0, count: n), crk = [Float](repeating: 0, count: n), pops = [Float](repeating: 0, count: n)
        let pC = P.crk / sr, pP = P.pop / sr
        var st = 0.0, sv = 0.0
        for i in 0..<n {
            hiss[i] = Float((r.next() * 2 - 1) * P.hiss)
            if P.stat != 0 {
                if i & 255 == 0 { sv += (r.next() - 0.5) * 0.08; sv *= 0.96; st = max(0, min(1, st + sv)) }
                hiss[i] += Float((r.next() * 2 - 1) * P.stat * st * st)
            }
            if r.next() < pC { let a = pow(r.next(), 3) * P.crkA; crk[i] += Float(r.next() < 0.5 ? -a : a) }
            if r.next() < pP { let a = (0.35 + 0.65 * r.next()) * P.popA; pops[i] += Float(r.next() < 0.5 ? -a : a) }
        }
        if P.tick.0 != 0 {
            let per = sr / P.tick.0
            var c = r.next() * per
            while c < Double(n) {
                let j = Int((c + (r.next() - 0.5) * 3).rounded())
                if j >= 0 && j < n { pops[j] += Float(P.tick.1 * (r.next() < 0.5 ? -1 : 1)) }
                c += per
            }
        }
        band(&hiss); bq("hp", 1800, 0.7, sr: sr, &crk); bq("lp", 1400, 0.7, sr: sr, &pops); bq("lp", 900, 0.7, sr: sr, &pops)
        for i in 0..<n {
            var v = Double(y[i] + hiss[i] + crk[i] + pops[i] * 2.2)
            if P.hum != 0 { let t = Double(i) / sr; v += P.hum * (sin(TAU * 50 * t) + 0.5 * sin(TAU * 100 * t) + 0.25 * sin(TAU * 150 * t)) }
            y[i] = Float(v)
        }
        // 7. the room you're listening in: direct sound, wall reflections (different each side), the room's tail
        var wl = [Float](repeating: 0, count: n), wr = [Float](repeating: 0, count: n), yf = y
        bq("lp", 2800, 0.7, sr: sr, &yf); bq("hp", 160, 0.7, sr: sr, &yf)
        func taps(_ out: inout [Float], _ list: [(Double, Double)]) {
            for (ms, g0) in list {
                let d = Int((ms * sr / 1000).rounded()), gg = Float(g0 * P.er)
                if d < n { for i in d..<n { out[i] += yf[i - d] * gg } }
            }
        }
        taps(&wl, [(7.3, 0.62), (12.9, 0.47), (19.7, 0.4), (27.1, 0.3), (35.9, 0.22), (47.3, 0.15), (61.1, 0.1)])
        taps(&wr, [(8.9, 0.6), (14.3, 0.5), (21.1, 0.36), (29.7, 0.28), (39.1, 0.2), (51.7, 0.13), (66.7, 0.09)])
        func tail(_ out: inout [Float], _ sp: Int) {
            let pd = Int((0.022 * sr).rounded()), damp: Float = 0.38
            var cb = [558, 594, 638, 678, 712, 746].map { L0 -> (b: [Float], L: Int, i: Int, lp: Float, g: Float) in
                let L = L0 + sp; return ([Float](repeating: 0, count: L), L, 0, 0, Float(pow(10, -3 * Double(L) / (P.t60 * sr))))
            }
            var ap = [220, 112].map { L0 -> (b: [Float], L: Int, i: Int) in let L = L0 + (sp >> 1); return ([Float](repeating: 0, count: L), L, 0) }
            let k = Float(P.late / 6)
            for i in 0..<n {
                let v = i >= pd ? yf[i - pd] : 0; var w: Float = 0
                for c in 0..<cb.count {
                    let o = cb[c].b[cb[c].i]; cb[c].lp = o * (1 - damp) + cb[c].lp * damp
                    cb[c].b[cb[c].i] = v + cb[c].lp * cb[c].g; cb[c].i += 1; if cb[c].i == cb[c].L { cb[c].i = 0 }; w += o
                }
                for a in 0..<ap.count {
                    let o = ap[a].b[ap[a].i], z = w + o * 0.5; ap[a].b[ap[a].i] = z; w = o - z * 0.5
                    ap[a].i += 1; if ap[a].i == ap[a].L { ap[a].i = 0 }
                }
                out[i] += w * k
            }
        }
        tail(&wl, 0); tail(&wr, 23)
        // 8. final level, 16-bit stereo
        var peak = 1e-6
        for i in 0..<n { let d = Double(y[i]) * P.dry, a = max(abs(d + Double(wl[i])), abs(d + Double(wr[i]))); if a > peak { peak = a } }
        let k1 = min(1.4, 0.93 / peak)
        var out = [Int16](repeating: 0, count: n * 2)
        for i in 0..<n { let d = Double(y[i]) * P.dry; out[2 * i] = limit(d + Double(wl[i]), k1); out[2 * i + 1] = limit(d + Double(wr[i]), k1) }
        return out
    }

    // MARK: Vinyl

    private struct CrackleSide { var pos: [Int32]; var len: [UInt8]; var off: [Int32]; var val: [Float] }
    private static let crackle: (srcLen: Int, sides: [CrackleSide])? = {
        guard let url = Bundle.main.url(forResource: "vinyl-crackle", withExtension: "txt"),
              let b64 = try? String(contentsOf: url, encoding: .utf8),
              let d = Data(base64Encoded: b64.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let u = [UInt8](d)
        var p = 0
        func u32() -> UInt32 { let v = UInt32(u[p]) | UInt32(u[p + 1]) << 8 | UInt32(u[p + 2]) << 16 | UInt32(u[p + 3]) << 24; p += 4; return v }
        let srcLen = Int(u32())
        var sides: [CrackleSide] = []
        for _ in 0..<2 {
            let cnt = Int(u32())
            var pos = [Int32](repeating: 0, count: cnt), len = [UInt8](repeating: 0, count: cnt), val: [Float] = []
            var at = 0
            for r in 0..<cnt {
                var dlt = 0, sh = 0, b: UInt8
                repeat { b = u[p]; p += 1; dlt |= Int(b & 127) << sh; sh += 7 } while b & 128 != 0
                at += dlt; pos[r] = Int32(at); len[r] = u[p]; p += 1
                for _ in 0..<Int(len[r]) {
                    let q = Int(u[p]); p += 1
                    let sq = Double(q > 127 ? q - 256 : q) / 127
                    val.append(Float(sq < 0 ? -2 * sq * sq : 2 * sq * sq))
                }
            }
            var off = [Int32](repeating: 0, count: cnt + 1), o: Int32 = 0
            for r in 0..<cnt { off[r] = o; o += Int32(len[r]) }
            off[cnt] = o
            sides.append(CrackleSide(pos: pos, len: len, off: off, val: val))
        }
        return (srcLen, sides)
    }()

    private static func vinyl(_ L: inout [Float], _ R0: inout [Float]?, sr: Double) -> [Int16] {
        let n = L.count, TAU = 2 * Double.pi
        let mono = R0 == nil
        var R = R0 ?? [Float](repeating: 0, count: n)
        R0 = nil
        var r = Rnd(seed: 0x5bd1e995 ^ UInt32(truncatingIfNeeded: n))
        // slow random curves, one value per 256 samples: the wow's wander, how muddy it is, how busy the crackle is
        let K = (n >> 8) + 2
        var drift = [Float](repeating: 0, count: K), mud = [Float](repeating: 0, count: K), burst = [Float](repeating: 0, count: K)
        do {
            var d = 0.0, dv = 0.0, m = 0.0, mv = 0.0, b = 0.0, bv = 0.0, ac = 0.3, av = 0.0
            for k in 0..<K {
                dv += (r.next() - 0.5) * 0.02; dv *= 0.97; d = max(-1, min(1, d + dv)); drift[k] = Float(d)
                mv += (r.next() - 0.5) * 0.001; mv *= 0.995; m = max(-1, min(1, (m + mv) * 0.999))
                mud[k] = m > 0.4 ? Float(min(0.55, (m - 0.4) * 1.5)) : 0
                bv += (r.next() - 0.5) * 0.05; bv *= 0.97; b = max(0, min(1, b + bv))
                av += (r.next() - 0.5) * 0.0016; av *= 0.995; ac = max(0, min(1, ac + av + (0.3 - ac) * 0.0006))
                burst[k] = Float((0.12 + 0.88 * ac * ac) * (0.45 + 0.55 * b))
            }
        }
        // 1. wow (both sides together), then the tone, then the muddy stretches
        let rev = 33.333 / 60, A1 = 0.0007 / (TAU * rev) * sr, base = 4 + A1, D = 2048, M = D - 1
        var ring = [Float](repeating: 0, count: D), dark = [Float](repeating: 0, count: n), tmp = [Double](repeating: 0, count: n)
        for i in 0..<n { tmp[i] = Double(i) - base - A1 * (sin(TAU * rev * Double(i) / sr) + 0.3 * Double(drift[i >> 8])) }
        func side(_ src: [Float], _ dst: inout [Float]) {
            for i in 0..<D { ring[i] = 0 }
            for i in 0..<n {
                ring[i & M] = src[i]
                let rr = tmp[i], i0 = Int(floor(rr)), fr = Float(rr - Double(i0))
                dst[i] = i0 < 0 ? 0 : ring[i0 & M] * (1 - fr) + ring[(i0 + 1) & M] * fr
            }
            bq("hp", 28, 0.707, sr: sr, &dst); bq("pk", 250, 0.8, 2.5, sr: sr, &dst); bq("hs", 7000, 0.7, -2.5, sr: sr, &dst); bq("lp", 14500, 0.707, sr: sr, &dst)
            dark = dst; bq("lp", 2600, 0.6, sr: sr, &dark); bq("pk", 300, 0.9, 3, sr: sr, &dark)
            for i in 0..<n { let a = mud[i >> 8]; if a != 0 { dst[i] += (dark[i] - dst[i]) * a } }
        }
        let srcL = L
        side(srcL, &L)
        side(mono ? srcL : R, &R)
        // 2. warmth, and the slight crosstalk between the two sides of the groove
        var pk: Float = 1e-6
        for i in 0..<n { let m = max(abs(L[i]), abs(R[i])); if m > pk { pk = m } }
        let g = 1.25, tg = tanh(g), k0 = 0.9 / Double(pk)
        for i in 0..<n {
            let l = Float(tanh(g * Double(L[i]) * k0) / tg), rr = Float(tanh(g * Double(R[i]) * k0) / tg)
            L[i] = l + 0.1 * rr; R[i] = rr + 0.1 * l
        }
        // 3. surface noise, set against how loud the song itself is
        var ms = 0.0
        for i in 0..<n { ms += Double(L[i] * L[i] + R[i] * R[i]) }
        let refv = sqrt(ms / Double(2 * n)), ref = refv > 0 ? refv : 0.1
        func db(_ v: Double) -> Double { ref * pow(10, v / 20) }
        let per = sr / rev
        var nz = dark
        var h = UInt32(r.seed | 1)
        func white() -> Float { h ^= h << 13; h ^= h >> 17; h ^= h << 5; return Float(Double(Int32(bitPattern: h)) / 2147483648) }
        func gap(_ rate: Double) -> Double { -log(1 - r.next()) * sr / rate }
        func rms(_ b: [Float]) -> Double { var q = 0.0; for v in b { q += Double(v * v) }; let s = sqrt(q / Double(n)); return s > 0 ? s : 1 }
        for i in 0..<n { nz[i] = white() }
        bq("hp", 1500, 0.6, sr: sr, &nz); bq("hp", 1500, 0.6, sr: sr, &nz); bq("lp", 10000, 0.6, sr: sr, &nz)
        do { let k = Float(db(-61) * 0.85 / rms(nz)); for i in 0..<n { nz[i] *= k } }
        var ticks: [Int] = []
        do { var c = r.next() * per; while c < Double(n) { ticks.append(Int(c.rounded())); c += per * (1 + (r.next() - 0.5) * 0.004) } }
        // generated crackle: (where, size, how far right, kind: 0 dust / 1 tick / 2 scrape)
        var ev: [(Int, Double, Double, Int)] = []
        do {
            var i = Int(floor(gap(2)))
            while i < n {
                let a = db(-46 + 24 * pow(r.next(), 1.8)) * (r.next() < 0.5 ? -1 : 1)
                let kind = r.next() < 0.45 ? 0 : (r.next() < 0.9 ? 1 : 2)
                let pan = r.next() < 0.6 ? (r.next() < 0.5 ? r.next() * 0.25 : 1 - r.next() * 0.25) : r.next()
                ev.append((i, a, pan, kind))
                if r.next() < 0.35 {
                    var c = 1 + Int(floor(r.next() * 4)), j = i
                    while c > 0 {
                        j += Int((sr * (0.003 + 0.035 * r.next())).rounded()); if j >= n { break }
                        let a2 = a * (0.25 + 0.6 * r.next()), p2 = min(1, max(0, pan + (r.next() - 0.5) * 0.3)), k2 = r.next() < 0.6 ? 0 : 1
                        ev.append((j, a2, p2, k2))
                        c -= 1
                    }
                }
                i += 1 + Int(floor(gap(1.5 + 9 * Double(burst[i >> 8]))))
            }
        }
        var t2 = [Float](repeating: 0, count: n)
        func click(_ i: Int, _ a: Double, _ kind: Int) {
            if kind < 2 { t2[i] += Float(a); if i + 1 < n { t2[i + 1] -= Float(0.6 * a) }; if i + 2 < n { t2[i + 2] += Float(0.25 * a) }; return }
            let len = Int((sr * (0.003 + 0.006 * r.next())).rounded()), tau = Double(len) / 3
            var k = 0
            while k < len && i + k < n { t2[i + k] += Float(a * 0.8 * exp(-Double(k) / tau)) * white(); k += 1 }
        }
        for s in 0..<2 {
            var out = s == 0 ? L : R
            let isRight = s == 1
            for i in 0..<n { t2[i] = white() }                                // this side's own hiss
            bq("hp", 1500, 0.6, sr: sr, &t2); bq("lp", 10000, 0.6, sr: sr, &t2)
            do { let k = Float(db(-61) * 0.5 / rms(t2)); for i in 0..<n { out[i] += nz[i] + t2[i] * k } }
            for dust in [true, false] {
                for i in 0..<n { t2[i] = 0 }
                for (i, a, pan, kind) in ev where (kind == 0) == dust { click(i, a * sqrt(isRight ? pan : 1 - pan) * 1.4, kind) }
                if dust { bq("hp", 400, 0.7, sr: sr, &t2); bq("lp", 3000, 0.6, sr: sr, &t2); bq("lp", 4500, 0.7, sr: sr, &t2); for i in 0..<n { t2[i] *= 1.8 } }
                else { bq("hp", 700, 0.7, sr: sr, &t2); bq("lp", 7000, 0.6, sr: sr, &t2) }
                for i in 0..<n { out[i] += t2[i] }
            }
            for i in 0..<n { t2[i] = 0 }                                      // pops and the tick
            var i = Int(floor(gap(0.15)))
            while i < n { t2[i] += Float(db(-12 - 8 * r.next()) * 6 * (r.next() < 0.5 ? -1 : 1)); i += 1 + Int(floor(gap(0.15))) }
            for j in ticks where j < n { t2[j] += Float(db(-20) * 4 * (j & 1 == 1 ? -1 : 1)) }
            bq("lp", 1200, 0.7, sr: sr, &t2); bq("lp", 800, 0.7, sr: sr, &t2)
            for i in 0..<n { out[i] += t2[i] }
            if s == 0 { L = out } else { R = out }
        }
        // 3b. the real crackle from Nick's vinyl rip, laid under the song in 3-9 s chunks from random places
        if let cr = crackle {
            let rs = sr / 44100, G = ref * 0.4
            var t0 = 0
            while t0 < n {
                let chunk = Int((sr * (3 + 6 * r.next())).rounded())
                let from = floor(r.next() * max(1, Double(cr.srcLen) - Double(chunk) / rs)), to = from + Double(chunk) / rs
                let swap = r.next() < 0.5, sgn: Double = r.next() < 0.5 ? -1 : 1, gg = Float(G * sgn * (0.85 + 0.3 * r.next()))
                for c in 0..<2 {
                    let S = cr.sides[c], toLeft = (c == 0) != swap
                    var lo = 0, hi = S.pos.count
                    while lo < hi { let m = (lo + hi) >> 1; if Double(S.pos[m]) < from { lo = m + 1 } else { hi = m } }
                    var rr = lo
                    while rr < S.pos.count && Double(S.pos[rr]) < to {
                        let j0 = t0 + Int(((Double(S.pos[rr]) - from) * rs).rounded())
                        for k in 0..<Int(S.len[rr]) {
                            let j = j0 + k
                            if j < n && j >= 0 { let v = S.val[Int(S.off[rr]) + k] * gg; if toLeft { L[j] += v } else { R[j] += v } }
                        }
                        rr += 1
                    }
                }
                t0 += chunk
            }
        }
        // 4. final level, 16-bit stereo
        var peak: Float = 1e-6
        for i in 0..<n { let m = max(abs(L[i]), abs(R[i])); if m > peak { peak = m } }
        let k1 = min(1.4, 0.95 / Double(peak))
        var out = [Int16](repeating: 0, count: n * 2)
        for i in 0..<n { out[2 * i] = limit(Double(L[i]), k1); out[2 * i + 1] = limit(Double(R[i]), k1) }
        return out
    }

    /// A 16-bit stereo WAV file.
    static func wav(_ pcm: [Int16], sr: Int) -> Data {
        var d = Data(capacity: 44 + pcm.count * 2)
        func s(_ t: String) { d.append(contentsOf: Array(t.utf8)) }
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        s("RIFF"); u32(UInt32(36 + pcm.count * 2)); s("WAVE"); s("fmt "); u32(16); u16(1); u16(2)
        u32(UInt32(sr)); u32(UInt32(sr * 4)); u16(4); u16(16); s("data"); u32(UInt32(pcm.count * 2))
        pcm.withUnsafeBufferPointer { d.append(UnsafeBufferPointer(start: UnsafeRawPointer($0.baseAddress!).assumingMemoryBound(to: UInt8.self), count: pcm.count * 2)) }
        return d
    }
}
