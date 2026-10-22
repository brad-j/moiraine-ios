// swift-tools-version: 6.2
import PackageDescription

let package = Package(
	name: "MoiraineCore",
	// macOS too, so `swift test` runs on the Mac without a simulator.
	platforms: [.iOS(.v26), .macOS(.v26)],
	products: [
		.library(name: "MoiraineCore", targets: ["MoiraineCore"]),
	],
	targets: [
		.target(name: "MoiraineCore"),
		.testTarget(name: "MoiraineCoreTests", dependencies: ["MoiraineCore"]),
	]
)
