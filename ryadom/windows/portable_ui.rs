use native_windows_gui as nwg;

fn show() -> Result<(), nwg::NwgError> {
    nwg::init()?;
    let mut window = nwg::Window::default();
    let mut label = nwg::Label::default();
    nwg::Window::builder()
        .title("Рядом — подготовка приложения")
        .flags(nwg::WindowFlags::WINDOW | nwg::WindowFlags::VISIBLE)
        .size((420, 130))
        .center(true)
        .build(&mut window)?;
    nwg::Label::builder()
        .text("Рядом\nПодготавливаем файлы. Это может занять несколько секунд.")
        .parent(&window)
        .position((20, 20))
        .size((380, 85))
        .build(&mut label)?;
    let handle = window.handle;
    let events = nwg::full_bind_event_handler(&window.handle, move |event, _, sender| {
        if event == nwg::Event::OnWindowClose && sender == handle {
            nwg::stop_thread_dispatch();
        }
    });
    nwg::dispatch_thread_events();
    nwg::unbind_event_handler(&events);
    Ok(())
}

pub fn setup() {
    std::thread::spawn(|| {
        if let Err(error) = show() {
            eprintln!("Рядом: не удалось показать подготовку: {error}");
        }
    });
}
