pub fn configure(resource: &mut winres::WindowsResource, filename: &str) -> bool {
    println!("cargo:rerun-if-env-changed=RYADOM_SIGNING_VERSION");
    let Ok(version) = std::env::var("RYADOM_SIGNING_VERSION") else {
        return false;
    };
    let parts: Vec<u16> = version
        .split('.')
        .map(|part| part.parse::<u16>().unwrap_or_else(|_| panic!("Invalid RYADOM_SIGNING_VERSION")))
        .collect();
    if parts.len() != 4 {
        panic!("RYADOM_SIGNING_VERSION must contain four 16-bit numbers");
    }
    let numeric = parts.iter().fold(0_u64, |value, part| (value << 16) | u64::from(*part));
    resource
        .set("ProductName", "Рядом")
        .set("CompanyName", "Ryadom Contributors")
        .set("FileDescription", "Рядом — удалённая помощь")
        .set("OriginalFilename", filename)
        .set("LegalCopyright", "Ryadom Contributors; includes RustDesk, AGPL-3.0")
        .set("FileVersion", &version)
        .set("ProductVersion", &version)
        .set_version_info(winres::VersionInfo::FILEVERSION, numeric)
        .set_version_info(winres::VersionInfo::PRODUCTVERSION, numeric);
    true
}

#[allow(dead_code)]
pub fn build_dll() {
    let mut resource = winres::WindowsResource::new();
    if configure(&mut resource, "librustdesk.dll") {
        resource.set_version_info(winres::VersionInfo::FILETYPE, 2);
        if let Err(error) = resource.compile() {
            panic!("Ryadom signing metadata could not be compiled: {error}");
        }
    }
}
