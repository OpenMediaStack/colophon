fn main() {
    // Windows reads the icon and the name of an executable from its resources: Explorer, the task
    // bar and the Task Manager show them.
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        let mut resource = winresource::WindowsResource::new();
        resource
            .set_icon("../../assets/icon/Colophon.ico")
            .set("ProductName", "Colophon")
            .set("FileDescription", "Colophon")
            .set("LegalCopyright", "© 2026 Florent Sorel");
        if let Err(error) = resource.compile() {
            panic!("the Windows resources do not compile: {error}");
        }
    }
}
