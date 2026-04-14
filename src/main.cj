package finalwork

const SERVER_HOST = "0.0.0.0"
const SERVER_PORT: UInt16 = 8080

main(): Int64 {
    let app = GomokuHttpApp()
    let server = createGomokuServer(app, SERVER_HOST, SERVER_PORT)
    server.serve()
    return 0
}
