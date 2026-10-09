fn main() -> Result<(), slint_build::CompileError> {
    // The testing backend finds elements by accessible label only with the compiler's debug info.
    let debug_build = std::env::var("PROFILE").is_ok_and(|profile| profile == "debug");
    let config = slint_build::CompilerConfiguration::new()
        .with_debug_info(debug_build)
        .with_bundled_translations("translations");
    slint_build::compile_with_config("ui/app-window.slint", config)
}
