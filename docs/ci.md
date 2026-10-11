# CI and test-first loop

Tests never run on the dev Mac (too slow). Xcode Cloud runs them.

## Workflow "CI" (create once in Xcode: Product → Xcode Cloud → Create Workflow)
- **Start condition:** Pull Request → target branch `main` (and Branch Changes → `main`).
- **Actions:** Test → scheme `Lumi`, test plan `Lumi.xctestplan`, destination: latest iPhone simulator.
- **Repo access:** grant the Xcode Cloud GitHub app access to `hlum/Lumi`.
- Protect `main` on GitHub: require the Xcode Cloud check before merge.

## Loop per task
1. Write failing Swift Testing tests.
2. Implement. Compile locally only: `xcodegen generate && xcodebuild -project Lumi.xcodeproj -scheme Lumi -destination 'platform=iOS Simulator,name=iPhone 17' build-for-testing -quiet`
3. Open a PR to `main`. Merge only when Xcode Cloud is green.

## Rules
- Bundle fixtures into LumiTests (`LumiTests/Fixtures/`); Xcode Cloud has no access to other repo paths at test time.
- The generated `Lumi.xcodeproj` is committed so CI needs no XcodeGen. Re-run `xcodegen generate` after editing `project.yml`.
- Hardware-dependent code goes behind protocols with fakes.
