import Foundation

/// The Cobalt-style `h5vcc.dial.DialServer` shim that lets leanback answer DIAL requests itself (D30, L1).
nonisolated enum YouTubeDIAL {
    static let messageHandlerName = "mmtvlDial"

    /// Document-start user script for the page world (L1). Defines window.h5vcc.dial.DialServer and window.__mmtvlDial,
    /// and nothing else on h5vcc.
    static let shimScript = """
        (() => {
          if (window.h5vcc && window.h5vcc.dial) return;
          const routes = {};
          const norm = (p) => {
            p = String(p == null ? '/' : p);
            if (!p.startsWith('/')) p = '/' + p;
            p = p.replace(/\\/+$/, '');
            return p || '/';
          };
          class DialServer {
            constructor(name) {
              this.name = String(name);
              routes[this.name] = { GET: {}, POST: {}, DELETE: {} };
              try { window.webkit.messageHandlers.mmtvlDial.postMessage({ type: 'ready', app: this.name }); } catch (e) {}
            }
            onGet(path, cb) { routes[this.name].GET[norm(path)] = cb; return true; }
            onPost(path, cb) { routes[this.name].POST[norm(path)] = cb; return true; }
            onDelete(path, cb) { routes[this.name].DELETE[norm(path)] = cb; return true; }
          }
          window.h5vcc = Object.assign(window.h5vcc || {}, { dial: { DialServer } });
          Object.defineProperty(window, '__mmtvlDial', { value: {
            handle(app, method, path, body, host) {
              const table = routes[app] && routes[app][method];
              const cb = table && table[norm(path)];
              if (!cb) return { found: false };
              const headers = [];
              const res = { responseCode: 200, body: '', mimeType: '',
                            addHeader(k, v) { headers.push([String(k), String(v)]); } };
              let ok = false;
              try { ok = !!cb({ path: '/apps/' + app, method, body: body || '', host }, res); } catch (e) { ok = false; }
              return { found: true, handled: ok, status: Number(res.responseCode) || 0,
                       body: res.body == null ? '' : String(res.body),
                       mimeType: res.mimeType ? String(res.mimeType) : '', headers };
            }
          }});
        })();
        """

    /// For callAsyncJavaScript; arguments app, method, path, body, host.
    static let handleScript = "return window.__mmtvlDial ? window.__mmtvlDial.handle(app, method, path, body, host) : null;"

    /// nil for null/garbage or {found:false}.
    static func response(fromJavaScript value: Any?) -> DIALAppResponse? {
        guard let object = value as? [String: Any], object["found"] as? Bool == true else { return nil }
        let status: Int = switch object["status"] {
        case let number as NSNumber: number.intValue
        case let int as Int: int
        default: 0
        }
        let mimeType = (object["mimeType"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let headers = (object["headers"] as? [Any] ?? []).compactMap { entry -> HTTPHeader? in
            guard let pair = entry as? [Any], pair.count == 2,
                  let name = pair[0] as? String, let value = pair[1] as? String
            else { return nil }
            return HTTPHeader(name: name, value: value)
        }
        return DIALAppResponse(handled: object["handled"] as? Bool ?? false,
                               status: status,
                               body: object["body"] as? String ?? "",
                               mimeType: mimeType,
                               headers: headers)
    }
}
