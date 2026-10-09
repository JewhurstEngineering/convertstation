import Foundation

protocol ConversionProvider: Sendable {
    var id: String { get }
    func canRead(_ source: SourceDescriptor) -> Bool
    func availableTargets(for source: SourceDescriptor) -> [TargetDescriptor]
    func validate(_ request: ConversionRequest, source: SourceDescriptor) throws
    func makePlan(_ request: ConversionRequest, source: SourceDescriptor, temporaryOutput: URL) throws -> ExecutionPlan
}

struct ExecutionPlan: Equatable, Sendable {
    var executableURL: URL
    var arguments: [String]
    var expectedDuration: Double
    var temporaryOutput: URL
    var warnings: [String]
}

struct CapabilityRegistry: Sendable {
    var providers: [any ConversionProvider]

    func targets(for source: SourceDescriptor) -> [TargetDescriptor] {
        var seen = Set<String>()
        var result: [TargetDescriptor] = []
        for provider in providers {
            for target in provider.availableTargets(for: source) {
                if seen.insert(target.id).inserted {
                    result.append(target)
                }
            }
        }
        return result
    }

    func provider(for target: TargetDescriptor) -> (any ConversionProvider)? {
        providers.first { $0.id == target.providerID }
    }

    func provider(id: String) -> (any ConversionProvider)? {
        providers.first { $0.id == id }
    }
}
