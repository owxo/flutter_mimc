`libmimc_sdk.dylib` is the Universal x86_64/arm64 artifact produced by
`tool/build_desktop_sdk.sh macos`. The podspec embeds every dylib in this
directory and the bridge resolves the SDK through `@rpath`.
