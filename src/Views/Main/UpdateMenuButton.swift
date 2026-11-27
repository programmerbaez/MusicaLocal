import SwiftUI

struct UpdateMenuButton: View {
    @EnvironmentObject private var updates: UpdateChecker
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 27, height: 25)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isPresented ? 0.14 : 0.07)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Actualizaciones de Música Local")
        .accessibilityLabel("Actualizaciones de Música Local")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            updateMenu
        }
    }

    private var updateMenu: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Actualizaciones").font(.headline)
            if let version = updates.installedVersion {
                Text("Versión actual \(version)").foregroundColor(.secondary)
            } else {
                Text("Versión actual desconocida").foregroundColor(.secondary)
            }
            Divider()
            updateStatus
            Button("Buscar actualizaciones…") {
                updates.check(manual: false, notifyAvailability: false)
            }
            .disabled(updates.checking || updates.installing)
        }
        .padding(14)
        .frame(width: 290, alignment: .leading)
    }

    @ViewBuilder
    private var updateStatus: some View {
        if updates.installing {
            progress("Instalando actualización…")
        } else if updates.checking {
            progress("Buscando actualizaciones…")
        } else {
            switch updates.status {
            case .idle:
                EmptyView()
            case .upToDate:
                Label("Música Local está al día", systemImage: "checkmark.circle")
            case let .available(archive):
                Label("Versión \(archive.version.description) disponible", systemImage: "arrow.down.circle")
                Button("Descargar e instalar") { updates.install(archive) }
                    .buttonStyle(.borderedProminent)
                Text("Música Local se reiniciará al terminar.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case let .missingArchive(version):
                Text("La versión \(version.description) todavía no ofrece un ZIP verificable.")
            case let .failed(message):
                Text(message)
            case let .installed(version):
                Text("Versión \(version.description) instalada. Reinicia Música Local para abrirla.")
            }
        }
    }

    private func progress(_ title: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(title)
        }
    }
}
