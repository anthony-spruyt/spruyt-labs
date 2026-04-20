package traefik_api_key_auth

import (
    "context"
    "crypto/subtle"
    "encoding/json"
    "fmt"
    "net/http"
    "os"
    "path"
    "strings"
)

const maxCredentialLength = 4096

type Config struct {
    AuthenticationHeader      bool     `json:"authenticationHeader,omitempty"`
    AuthenticationHeaderName  string   `json:"authenticationHeaderName,omitempty"`
    BearerHeader              bool     `json:"bearerHeader,omitempty"`
    BearerHeaderName          string   `json:"bearerHeaderName,omitempty"`
    QueryParam                bool     `json:"queryParam,omitempty"`
    QueryParamName            string   `json:"queryParamName,omitempty"`
    PathSegment               bool     `json:"pathSegment,omitempty"`
    PermissiveMode            bool     `json:"permissiveMode,omitempty"`
    Keys                      []string `json:"keys,omitempty"`
    RemoveHeadersOnSuccess    bool     `json:"removeHeadersOnSuccess,omitempty"`
    InternalForwardHeaderName string   `json:"internalForwardHeaderName,omitempty"`
    ForwardBearerHeader       bool     `json:"forwardBearerHeader,omitempty"`
    ForwardBearerHeaderName   string   `json:"forwardBearerHeaderName,omitempty"`
    InternalErrorRoute        string   `json:"internalErrorRoute,omitempty"`
    ExemptPaths               []string `json:"exemptPaths,omitempty"`
}

type Response struct {
    Message    string `json:"message"`
    StatusCode int    `json:"status_code"`
}

type keyMaterial struct {
    raw   string
    bytes []byte
}

func CreateConfig() *Config {
    return &Config{
        AuthenticationHeader:      true,
        AuthenticationHeaderName:  "X-API-KEY",
        BearerHeader:              true,
        BearerHeaderName:          "Authorization",
        QueryParam:                false,
        QueryParamName:            "token",
        PathSegment:               false,
        PermissiveMode:            false,
        Keys:                      make([]string, 0),
        RemoveHeadersOnSuccess:    true,
        InternalForwardHeaderName: "",
        ForwardBearerHeader:       false,
        ForwardBearerHeaderName:   "Authorization",
        InternalErrorRoute:        "",
        ExemptPaths:               nil,
    }
}

type KeyAuth struct {
    next                      http.Handler
    passthroughMode           bool
    passthroughSourceHeader   string
    authenticationHeader      bool
    authenticationHeaderName  string
    bearerHeader              bool
    bearerHeaderName          string
    queryParam                bool
    queryParamName            string
    pathSegment               bool
    permissiveMode            bool
    keysByLength              map[int][]keyMaterial
    removeHeadersOnSuccess    bool
    internalForwardHeaderName string
    forwardBearerHeader       bool
    forwardBearerHeaderName   string
    internalErrorRoute        string
    exemptPaths               []string
}

// resolveKeys expands config keys: entries "env:VAR_NAME" are replaced by the value of the environment variable.
// Returns the final list of keys and an error if no keys remain or when an env key is missing.
func resolveKeys(rawKeys []string) ([]string, error) {
    seen := make(map[string]struct{}, len(rawKeys))
    keys := make([]string, 0, len(rawKeys))

    for _, k := range rawKeys {
        k = strings.TrimSpace(k)
        if k == "" {
            continue
        }

        if strings.HasPrefix(k, "env:") {
            envVar := strings.TrimSpace(strings.TrimPrefix(k, "env:"))
            if envVar == "" {
                return nil, fmt.Errorf("invalid env key reference: %q", k)
            }

            v := strings.TrimSpace(os.Getenv(envVar))
            if v == "" {
                return nil, fmt.Errorf("environment variable %q is empty or missing", envVar)
            }
            k = v
        }

        if len(k) > maxCredentialLength {
            return nil, fmt.Errorf("configured key exceeds maximum length (%d)", maxCredentialLength)
        }

        if _, exists := seen[k]; exists {
            continue
        }
        seen[k] = struct{}{}
        keys = append(keys, k)
    }

    if len(keys) == 0 {
        return nil, fmt.Errorf("must specify at least one valid key (or use env:VAR_NAME)")
    }
    return keys, nil
}

func buildKeyIndex(keys []string) map[int][]keyMaterial {
    index := make(map[int][]keyMaterial, len(keys))
    for _, k := range keys {
        m := keyMaterial{raw: k, bytes: []byte(k)}
        index[len(k)] = append(index[len(k)], m)
    }
    return index
}

func normalizeRoutePrefix(value string) string {
    v := strings.TrimSpace(value)
    if v == "" {
        return ""
    }
    if !strings.HasPrefix(v, "/") {
        v = "/" + v
    }
    clean := path.Clean(v)
    if clean == "." {
        return "/"
    }
    return clean
}

func normalizeExemptPaths(raw []string) []string {
    if len(raw) == 0 {
        return nil
    }

    seen := make(map[string]struct{}, len(raw))
    normalized := make([]string, 0, len(raw))
    for _, p := range raw {
        n := normalizeRoutePrefix(p)
        if n == "" {
            continue
        }
        if n != "/" {
            n = strings.TrimSuffix(n, "/")
        }
        if _, exists := seen[n]; exists {
            continue
        }
        seen[n] = struct{}{}
        normalized = append(normalized, n)
    }
    return normalized
}

func New(ctx context.Context, next http.Handler, config *Config, name string) (http.Handler, error) {
    _ = ctx
    if config == nil {
        return nil, fmt.Errorf("config cannot be nil")
    }

    _, _ = os.Stdout.WriteString("traefik_api_key_auth: creating plugin " + name + "\n")

    // Passthrough mode: forwardBearerHeader + no keys = header translation only, no validation.
    passthroughMode := config.ForwardBearerHeader && len(config.Keys) == 0

    var keyIndex map[int][]keyMaterial
    if !passthroughMode {
        resolvedKeys, err := resolveKeys(config.Keys)
        if err != nil {
            return nil, err
        }
        keyIndex = buildKeyIndex(resolvedKeys)

        if !config.AuthenticationHeader && !config.BearerHeader && !config.QueryParam && !config.PathSegment {
            return nil, fmt.Errorf("at least one method must be true")
        }
    }

    authHeaderName := strings.TrimSpace(config.AuthenticationHeaderName)
    if config.AuthenticationHeader && authHeaderName == "" {
        return nil, fmt.Errorf("authenticationHeaderName cannot be empty when authenticationHeader is enabled")
    }

    bearerHeaderName := strings.TrimSpace(config.BearerHeaderName)
    if config.BearerHeader && bearerHeaderName == "" {
        return nil, fmt.Errorf("bearerHeaderName cannot be empty when bearerHeader is enabled")
    }

    queryParamName := strings.TrimSpace(config.QueryParamName)
    if config.QueryParam && queryParamName == "" {
        return nil, fmt.Errorf("queryParamName cannot be empty when queryParam is enabled")
    }

    internalErrorRoute := normalizeRoutePrefix(config.InternalErrorRoute)

    forwardBearerHeaderName := strings.TrimSpace(config.ForwardBearerHeaderName)
    if config.ForwardBearerHeader && forwardBearerHeaderName == "" {
        forwardBearerHeaderName = "Authorization"
    }

    // In passthrough mode, source header defaults to AuthenticationHeaderName.
    passthroughSourceHeader := authHeaderName
    if passthroughMode {
        if passthroughSourceHeader == "" {
            return nil, fmt.Errorf("authenticationHeaderName required in passthrough mode (forwardBearerHeader without keys)")
        }
        _, _ = os.Stdout.WriteString("traefik_api_key_auth: passthrough mode — translating " + passthroughSourceHeader + " → " + forwardBearerHeaderName + " Bearer\n")
    }

    return &KeyAuth{
        next:                      next,
        passthroughMode:           passthroughMode,
        passthroughSourceHeader:   passthroughSourceHeader,
        authenticationHeader:      config.AuthenticationHeader,
        authenticationHeaderName:  authHeaderName,
        bearerHeader:              config.BearerHeader,
        bearerHeaderName:          bearerHeaderName,
        queryParam:                config.QueryParam,
        queryParamName:            queryParamName,
        pathSegment:               config.PathSegment,
        permissiveMode:            config.PermissiveMode,
        keysByLength:              keyIndex,
        removeHeadersOnSuccess:    config.RemoveHeadersOnSuccess,
        internalForwardHeaderName: strings.TrimSpace(config.InternalForwardHeaderName),
        forwardBearerHeader:       config.ForwardBearerHeader,
        forwardBearerHeaderName:   forwardBearerHeaderName,
        internalErrorRoute:        internalErrorRoute,
        exemptPaths:               normalizeExemptPaths(config.ExemptPaths),
    }, nil
}

// findMatchingKey returns the matching valid key if the provided key matches any of them using constant-time comparison.
// Empty provided key never matches. Used to reduce timing attacks.
func findMatchingKey(provided string, keysByLength map[int][]keyMaterial) string {
    provided = strings.TrimSpace(provided)
    if provided == "" || len(provided) > maxCredentialLength {
        return ""
    }

    candidates := keysByLength[len(provided)]
    if len(candidates) == 0 {
        return ""
    }

    providedB := []byte(provided)
    for _, valid := range candidates {
        if subtle.ConstantTimeCompare(providedB, valid.bytes) == 1 {
            return valid.raw
        }
    }
    return ""
}

// extractBearerToken returns the token from "Authorization: Bearer <token>" or empty string if not in that form.
func extractBearerToken(headerValue string) string {
    headerValue = strings.TrimSpace(headerValue)
    if headerValue == "" {
        return ""
    }

    scheme, token, found := strings.Cut(headerValue, " ")
    if !found || !strings.EqualFold(strings.TrimSpace(scheme), "Bearer") {
        return ""
    }

    token = strings.TrimSpace(token)
    if token == "" || strings.ContainsAny(token, " \t") {
        return ""
    }
    if len(token) > maxCredentialLength {
        return ""
    }
    return token
}

// pathSegmentMatchesKey returns the matching key if any path segment (between slashes) exactly matches a valid key.
// Uses constant-time comparison; avoids substring matching for security.
func pathSegmentMatchesKey(pathValue string, keysByLength map[int][]keyMaterial) string {
    start := -1
    for i := 0; i <= len(pathValue); i++ {
        if i == len(pathValue) || pathValue[i] == '/' {
            if start >= 0 && i > start {
                if matched := findMatchingKey(pathValue[start:i], keysByLength); matched != "" {
                    return matched
                }
            }
            start = -1
            continue
        }
        if start == -1 {
            start = i
        }
    }
    return ""
}

func requestPathForLog(req *http.Request) string {
    if req == nil || req.URL == nil {
        return "/"
    }
    p := req.URL.EscapedPath()
    if p == "" {
        return "/"
    }
    return p
}

func (ka *KeyAuth) ok(rw http.ResponseWriter, req *http.Request, matchedKey string) {
    _, _ = os.Stdout.WriteString("traefik_api_key_auth: valid credentials for path " + requestPathForLog(req) + "\n")
    if ka.internalForwardHeaderName != "" {
        req.Header.Del(ka.internalForwardHeaderName)
        req.Header.Set(ka.internalForwardHeaderName, matchedKey)
    }
    if ka.forwardBearerHeader {
        req.Header.Set(ka.forwardBearerHeaderName, "Bearer "+matchedKey)
    }
    req.RequestURI = req.URL.RequestURI()
    ka.next.ServeHTTP(rw, req)
}

func (ka *KeyAuth) permissiveOk(rw http.ResponseWriter, req *http.Request) {
    _, _ = os.Stderr.WriteString("traefik_api_key_auth: no valid credentials for path \"" + requestPathForLog(req) + "\"; allowing in permissive mode\n")
    req.RequestURI = req.URL.RequestURI()
    ka.next.ServeHTTP(rw, req)
}

func (ka *KeyAuth) isExempt(pathValue string) bool {
    for _, prefix := range ka.exemptPaths {
        if prefix == "/" {
            return true
        }
        if pathValue == prefix || strings.HasPrefix(pathValue, prefix+"/") {
            return true
        }
    }
    return false
}

func (ka *KeyAuth) deny(rw http.ResponseWriter, req *http.Request) {
    if ka.permissiveMode {
        ka.permissiveOk(rw, req)
        return
    }

    if ka.internalErrorRoute != "" {
        req.URL.Path = ka.internalErrorRoute
        req.URL.RawQuery = ""
        req.RequestURI = req.URL.RequestURI()
        ka.next.ServeHTTP(rw, req)
        return
    }

    rw.Header().Set("Content-Type", "application/json; charset=utf-8")
    rw.WriteHeader(http.StatusForbidden)
    response := Response{Message: "Invalid or missing API Key", StatusCode: http.StatusForbidden}
    if err := json.NewEncoder(rw).Encode(response); err != nil {
        _, _ = os.Stderr.WriteString("traefik_api_key_auth: failed to write response: " + err.Error() + "\n")
    }
}

func (ka *KeyAuth) ServeHTTP(rw http.ResponseWriter, req *http.Request) {
    pathValue := req.URL.Path
    if ka.isExempt(pathValue) {
        req.RequestURI = req.URL.RequestURI()
        ka.next.ServeHTTP(rw, req)
        return
    }

    // Passthrough mode: read source header, set as Bearer, forward without validation.
    if ka.passthroughMode {
        provided := strings.TrimSpace(req.Header.Get(ka.passthroughSourceHeader))
        if provided == "" || len(provided) > maxCredentialLength {
            ka.deny(rw, req)
            return
        }
        if ka.removeHeadersOnSuccess {
            req.Header.Del(ka.passthroughSourceHeader)
        }
        req.Header.Set(ka.forwardBearerHeaderName, "Bearer "+provided)
        _, _ = os.Stdout.WriteString("traefik_api_key_auth: passthrough for path " + requestPathForLog(req) + "\n")
        req.RequestURI = req.URL.RequestURI()
        ka.next.ServeHTTP(rw, req)
        return
    }

    if ka.authenticationHeader {
        provided := req.Header.Get(ka.authenticationHeaderName)
        if matched := findMatchingKey(provided, ka.keysByLength); matched != "" {
            if ka.removeHeadersOnSuccess {
                req.Header.Del(ka.authenticationHeaderName)
            }
            ka.ok(rw, req, matched)
            return
        }
    }

    if ka.bearerHeader {
        token := extractBearerToken(req.Header.Get(ka.bearerHeaderName))
        if matched := findMatchingKey(token, ka.keysByLength); matched != "" {
            if ka.removeHeadersOnSuccess {
                req.Header.Del(ka.bearerHeaderName)
            }
            ka.ok(rw, req, matched)
            return
        }
    }

    if ka.queryParam {
        qs := req.URL.Query()
        provided := qs.Get(ka.queryParamName)
        if matched := findMatchingKey(provided, ka.keysByLength); matched != "" {
            qs.Del(ka.queryParamName)
            req.URL.RawQuery = qs.Encode()
            ka.ok(rw, req, matched)
            return
        }
    }

    if ka.pathSegment {
        if matched := pathSegmentMatchesKey(pathValue, ka.keysByLength); matched != "" {
            ka.ok(rw, req, matched)
            return
        }
    }

    ka.deny(rw, req)
}
