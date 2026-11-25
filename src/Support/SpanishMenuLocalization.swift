import AppKit

/// Traduce los menús nativos generados por SwiftUI cuando las herramientas del
/// sistema muestran títulos ingleses. No cambia atajos, selectores ni acciones.
/// Esta capa se sustituirá por recursos de localización al incorporar más idiomas.
enum SpanishMenuLocalization {
    private static var observer: NSObjectProtocol?
    private static let titles: [String: String] = [
        "File": "Archivo", "Edit": "Edición", "View": "Visualización",
        "Window": "Ventana", "Help": "Ayuda", "Format": "Formato",
        "Services": "Servicios", "Speech": "Voz", "Spelling and Grammar": "Ortografía y gramática",
        "Substitutions": "Sustituciones", "Transformations": "Transformaciones",
        "About Música Local": "Acerca de Música Local",
        "About MusicaLocal": "Acerca de Música Local",
        "About Musica Local": "Acerca de Música Local",
        "Settings…": "Configuración…", "Settings...": "Configuración…",
        "Preferences…": "Preferencias…", "Preferences...": "Preferencias…",
        "Hide Música Local": "Ocultar Música Local",
        "Hide MusicaLocal": "Ocultar Música Local",
        "Hide Others": "Ocultar las demás", "Show All": "Mostrar todo",
        "Quit Música Local": "Salir de Música Local",
        "Quit MusicaLocal": "Salir de Música Local",
        "Undo": "Deshacer", "Redo": "Rehacer", "Cut": "Cortar", "Copy": "Copiar",
        "Paste": "Pegar", "Paste and Match Style": "Pegar con el mismo estilo",
        "Select All": "Seleccionar todo", "Delete": "Eliminar",
        "Start Dictation…": "Iniciar dictado…", "Emoji & Symbols": "Emojis y símbolos",
        "Find": "Buscar", "Find…": "Buscar…", "Find...": "Buscar…",
        "Find Next": "Buscar siguiente", "Find Previous": "Buscar anterior",
        "Use Selection for Find": "Usar selección para buscar", "Jump to Selection": "Ir a la selección",
        "Enter Full Screen": "Entrar en pantalla completa",
        "Exit Full Screen": "Salir de pantalla completa",
        "Minimize": "Minimizar", "Zoom": "Ajustar tamaño",
        "Bring All to Front": "Traer todo al frente",
        "Close Window": "Cerrar ventana", "Close": "Cerrar",
        "Open…": "Abrir…", "Open...": "Abrir…", "Save": "Guardar",
        "Print…": "Imprimir…", "Print...": "Imprimir…",
        "Show Toolbar": "Mostrar barra de herramientas",
        "Hide Toolbar": "Ocultar barra de herramientas",
        "Customize Toolbar…": "Personalizar barra de herramientas…",
        "Música Local Help": "Ayuda de Música Local",
        "Search": "Buscar"
    ]

    static func install() {
        // SwiftUI construye algunos menús tras aparecer la ventana.
        DispatchQueue.main.async { translate() }
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: NSMenu.didBeginTrackingNotification,
                object: nil,
                queue: .main
            ) { _ in translate() }
        }
    }

    private static func translate() {
        guard let menu = NSApp.mainMenu else { return }
        translateMenu(menu)
    }

    private static func translateMenu(_ menu: NSMenu) {
        for item in menu.items {
            if let spanish = titles[item.title] { item.title = spanish }
            if let submenu = item.submenu {
                if let spanish = titles[submenu.title] { submenu.title = spanish }
                translateMenu(submenu)
            }
        }
    }
}
