import Foundation

enum SoakScenarioStep: Equatable, Sendable {
    case move(x: Double, y: Double, headingX: Double, headingY: Double)
    case map(Int)
    case disconnect
    case reconnect
    case character(String)
    case mount(UInt8)
    case combat(Bool)
}

struct SoakScriptedFrame: Equatable, Sendable {
    var at: TimeInterval
    var step: SoakScenarioStep
}

enum SoakScenario {
    static let defaultDuration: TimeInterval = 30 * 60

    static func script(duration: TimeInterval = defaultDuration) -> [SoakScriptedFrame] {
        let cycle: [(TimeInterval, SoakScenarioStep)] = [
            (0, .character("Soak Alpha")),
            (0, .map(15)),
            (0, .reconnect),
            (0, .move(x: 44_615.5, y: 29_863.7, headingX: 0, headingY: 1)),
            (8, .move(x: 44_720.0, y: 29_900.0, headingX: 0.4, headingY: 0.9)),
            (16, .mount(8)),
            (20, .combat(true)),
            (24, .combat(false)),
            (28, .mount(0)),
            (32, .map(23)),
            (36, .move(x: 44_843.0, y: 31_380.9, headingX: 0, headingY: 1)),
            (44, .disconnect),
            (52, .reconnect),
            (56, .character("Soak Beta")),
            (60, .map(15)),
            (64, .move(x: 43_728.4, y: 28_589.9, headingX: 1, headingY: 0))
        ]
        let cycleLength: TimeInterval = 72
        var frames: [SoakScriptedFrame] = []
        var offset: TimeInterval = 0
        while offset < duration {
            for (at, step) in cycle {
                let time = offset + at
                if time <= duration { frames.append(SoakScriptedFrame(at: time, step: step)) }
            }
            offset += cycleLength
        }
        return frames
    }

    static func apply(_ step: SoakScenarioStep, to envelope: TelemetryEnvelope, tick: UInt32) -> TelemetryEnvelope {
        var connected = envelope.connected
        var positionAvailable = envelope.positionAvailable
        var character = envelope.character
        var map = envelope.map
        var player = envelope.player
        var camera = envelope.camera
        var ui = envelope.ui
        var mount = envelope.mount
        var status = envelope.statusMessage
        switch step {
        case let .move(x, y, headingX, headingY):
            player = PlayerTelemetry(
                continentX: x, continentY: y,
                avatarX: player?.avatarX ?? 0, avatarY: player?.avatarY ?? 0, avatarZ: player?.avatarZ ?? 0,
                headingX: headingX, headingY: headingY)
            camera = CameraTelemetry(frontX: headingX, frontY: 0, frontZ: -headingY)
        case let .map(id):
            map = MapTelemetry(id: id, type: 5, shardId: 1, instanceId: 1)
        case .disconnect:
            connected = false
            positionAvailable = false
            status = "Guild Wars 2 is not running."
        case .reconnect:
            connected = true
            positionAvailable = true
            status = nil
        case let .character(name):
            character = CharacterTelemetry(
                name: name, profession: character?.profession, specialization: character?.specialization,
                race: character?.race)
        case let .mount(index):
            mount = MountTelemetry(index: index)
        case let .combat(inCombat):
            ui = UITelemetry(inCombat: inCombat, mapOpen: ui.mapOpen, gameHasFocus: true)
        }
        return TelemetryEnvelope(
            protocolVersion: envelope.protocolVersion,
            timestampUnixMs: Int64(Date().timeIntervalSince1970 * 1_000),
            connected: connected,
            uiTick: tick,
            positionAvailable: positionAvailable,
            character: character,
            map: map,
            player: player,
            camera: camera,
            ui: ui,
            mount: mount,
            statusMessage: status,
            uiVersion: envelope.uiVersion)
    }
}

struct SoakTelemetryProvider: LiveTelemetryProvider {
    var duration: TimeInterval
    var intervalNanoseconds: UInt64 = 100_000_000

    func telemetryStream() -> AsyncThrowingStream<TelemetryEnvelope, Error> {
        TelemetryStreamBuffer.latest { continuation in
            let task = Task {
                let frames = SoakScenario.script(duration: duration)
                var envelope = TelemetryEnvelope(
                    protocolVersion: 1, timestampUnixMs: 1, connected: true, uiTick: 0,
                    positionAvailable: true,
                    character: CharacterTelemetry(name: "Soak Alpha", profession: 8, specialization: 0, race: 0),
                    map: MapTelemetry(id: 15, type: 5, shardId: 1, instanceId: 1),
                    player: PlayerTelemetry(
                        continentX: 44_615.5, continentY: 29_863.7,
                        avatarX: 0, avatarY: 0, avatarZ: 0, headingX: 0, headingY: 1),
                    camera: CameraTelemetry(frontX: 0, frontY: 0, frontZ: -1),
                    ui: UITelemetry(inCombat: false, mapOpen: false, gameHasFocus: true),
                    mount: MountTelemetry(index: 0),
                    statusMessage: nil,
                    uiVersion: 2)
                var tick: UInt32 = 0
                let start = ContinuousClock.now
                var frameIndex = 0
                while !Task.isCancelled {
                    let elapsed = start.duration(to: ContinuousClock.now)
                    let seconds = Double(elapsed.components.seconds)
                        + Double(elapsed.components.attoseconds) / 1e18
                    if seconds > duration { break }
                    while frameIndex < frames.count, frames[frameIndex].at <= seconds {
                        envelope = SoakScenario.apply(frames[frameIndex].step, to: envelope, tick: tick)
                        frameIndex += 1
                    }
                    tick &+= 1
                    continuation.yield(SoakScenario.apply(.move(
                        x: envelope.player?.continentX ?? 0,
                        y: envelope.player?.continentY ?? 0,
                        headingX: envelope.player?.headingX ?? 0,
                        headingY: envelope.player?.headingY ?? 1
                    ), to: envelope, tick: tick))
                    try await Task.sleep(nanoseconds: intervalNanoseconds)
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
