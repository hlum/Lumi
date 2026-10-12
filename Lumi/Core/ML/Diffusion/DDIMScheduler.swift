import Foundation

/// Deterministic DDIM sampling (eta 0) with Stable Diffusion's scaled-linear noise schedule.
struct DDIMScheduler {
    let steps: Int
    private let alphas: [Double]          // cumulative product of (1 - beta), per training step

    init(steps: Int, trainSteps: Int = 1000, betaStart: Double = 0.00085, betaEnd: Double = 0.012) {
        self.steps = steps
        var a: [Double] = [], running = 1.0
        for i in 0..<trainSteps {
            let beta = pow(sqrt(betaStart) + (sqrt(betaEnd) - sqrt(betaStart)) * Double(i) / Double(trainSteps - 1), 2)
            running *= 1 - beta; a.append(running)
        }
        alphas = a
    }

    /// Time steps from noisiest to cleanest, spaced evenly and offset by one like diffusers' SD scheduler.
    var timesteps: [Int] {
        let ratio = alphas.count / steps
        return (0..<steps).map { $0 * ratio + 1 }.reversed()
    }

    /// One denoising step: from the noisy sample at `t` and the predicted noise to the sample at the previous time step.
    func step(sample: [Float], noise: [Float], t: Int) -> [Float] {
        let prev = t - alphas.count / steps
        let aT = alphas[t], aPrev = prev >= 0 ? alphas[prev] : alphas[0]
        let sa = Float(aT.squareRoot()), sb = Float((1 - aT).squareRoot()), pa = Float(aPrev.squareRoot()), pb = Float((1 - aPrev).squareRoot())
        var out = [Float](repeating: 0, count: sample.count)
        for i in 0..<sample.count {
            let x0 = (sample[i] - sb * noise[i]) / sa
            out[i] = pa * x0 + pb * noise[i]
        }
        return out
    }
}

/// Small deterministic normal-noise source, so the same photo and mask always give the same fill.
struct SeededNormal {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    private mutating func uniform() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return (Double(state >> 11) + 0.5) / Double(1 << 53)
    }
    mutating func next() -> Float {
        let u1 = uniform(), u2 = uniform()
        return Float((-2 * log(u1)).squareRoot() * cos(2 * .pi * u2))
    }
    mutating func array(_ n: Int) -> [Float] { (0..<n).map { _ in next() } }
}
