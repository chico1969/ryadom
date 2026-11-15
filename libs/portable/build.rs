#[cfg(windows)]
#[path = "../../ryadom/signing/windows_resource.rs"]
mod ryadom_signing_resource;

fn main() {
    #[cfg(windows)]
    {
        use std::io::Write;
        let mut res = winres::WindowsResource::new();
        let ryadom = std::env::var("RYADOM_BUILD").as_deref() == Ok("1");
        res.set_icon(if ryadom { "../../ryadom/assets/ryadom.ico" } else { "../../res/icon.ico" })
            .set_language(winapi::um::winnt::MAKELANGID(
                winapi::um::winnt::LANG_ENGLISH,
                winapi::um::winnt::SUBLANG_ENGLISH_US,
            ))
            .set_manifest_file("../../res/manifest.xml");
        println!("cargo:rerun-if-env-changed=RYADOM_BUILD");
        if ryadom {
            println!("cargo:rustc-cfg=ryadom_build");
            res.set("CompanyName", "Ryadom Contributors")
                .set("ProductName", "Рядом")
                .set("OriginalFilename", "Ryadom.exe")
                .set("FileDescription", "Рядом — удалённая помощь (разработка)")
                .set("LegalCopyright", "Ryadom Contributors; includes RustDesk, AGPL-3.0");
            println!("cargo:rerun-if-changed=../../ryadom/assets/ryadom.ico");
            ryadom_signing_resource::configure(&mut res, "Ryadom.exe");
        }
        match res.compile() {
            Err(e) => {
                write!(std::io::stderr(), "{}", e).unwrap();
                std::process::exit(1);
            }
            Ok(_) => {}
        }
    }
}
