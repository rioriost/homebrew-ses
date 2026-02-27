build:
	bash ./scripts/generate-version.sh
	swift build -c release --product ses

test:
	./.build/debug/sesTestRunner

coverage:
	mkdir -p .build/coverage
	swift build -c debug -Xswiftc -profile-generate -Xswiftc -profile-coverage-mapping
	LLVM_PROFILE_FILE=.build/coverage/default.profraw ./.build/debug/sesTestRunner
	xcrun llvm-profdata merge -sparse .build/coverage/default.profraw -o .build/coverage/default.profdata
	xcrun llvm-cov report ./.build/debug/sesTestRunner -instr-profile=.build/coverage/default.profdata

ci: build test coverage

release:
	bash ./scripts/release.sh
