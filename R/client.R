snapforge_client <- function(base_url = "https://snapforge.web-tasarimci.com",
                             access_token = Sys.getenv("SNAPFORGE_API_KEY", unset = ""),
                             url_secret = NULL,
                             timeout = 60,
                             transport = NULL) {
  base_url <- .sf_normalize_base_url(base_url)
  access_token <- as.character(access_token %||% "")
  url_secret <- as.character(url_secret %||% "")
  if (nzchar(access_token) && nzchar(url_secret)) {
    stop("Choose access_token or url_secret, not both", call. = FALSE)
  }
  timeout <- as.numeric(timeout)
  if (length(timeout) != 1L || !is.finite(timeout) || timeout <= 0) {
    stop("timeout must be a positive number of seconds", call. = FALSE)
  }
  if (!is.null(transport) && !is.function(transport)) {
    stop("transport must be NULL or a function", call. = FALSE)
  }
  structure(list(base_url = base_url, access_token = access_token,
                 url_secret = url_secret, timeout = timeout,
                 transport = transport),
            class = "snapforge_client")
}

print.snapforge_client <- function(x, ...) {
  auth <- if (nzchar(x$access_token)) "bearer" else if (nzchar(x$url_secret)) "url-secret" else "none"
  cat("<snapforge_client>\n", "  base_url: ", x$base_url, "\n", "  auth: ", auth, "\n", sep = "")
  invisible(x)
}

print.snapforge_response <- function(x, ...) {
  cat("<snapforge_response> HTTP ", x$status, "\n", sep = "")
  if (!is.null(x$quota$remaining) || !is.null(x$quota$limit)) {
    cat("  quota: ", x$quota$remaining %||% "?", "/", x$quota$limit %||% "?", " remaining\n", sep = "")
  }
  invisible(x)
}

snapforge_request <- function(client, path, method = "GET", body = NULL,
                              headers = list(), idempotency_key = NULL,
                              timeout = NULL) {
  .sf_assert_client(client)
  path <- .sf_public_path(path)
  method <- toupper(as.character(method))
  if (!method %in% c("GET", "POST", "PUT", "PATCH", "DELETE")) {
    stop("method must be GET, POST, PUT, PATCH, or DELETE", call. = FALSE)
  }
  .sf_api_call(client, method, .sf_endpoint(client, path), body = body,
               headers = headers, idempotency_key = idempotency_key,
               timeout = timeout %||% client$timeout)
}

snapforge_service_info <- function(client) {
  .sf_assert_client(client)
  .sf_api_call(client, "GET", paste0(client$base_url, "/api/v1"))
}

snapforge_capture <- function(client, url, device = "both", full_page = TRUE,
                              delay_ms = 1200L, ttl_seconds = NULL,
                              idempotency_key = NULL) {
  .sf_assert_client(client)
  if (!nzchar(trimws(as.character(url)))) stop("capture requires a url", call. = FALSE)
  device <- match.arg(device, c("desktop", "mobile", "both"))
  body <- list(url = as.character(url), device = device,
               fullPage = isTRUE(full_page), delayMs = as.integer(delay_ms))
  if (!is.null(ttl_seconds)) body$ttlSeconds <- as.integer(ttl_seconds)
  .sf_api_call(client, "POST", .sf_endpoint(client, "/api/v1/screenshot"),
               body = body, idempotency_key = idempotency_key)
}

snapforge_context <- function(client, url, viewport = "desktop",
                              delay_ms = 800L, max_text_chars = NULL,
                              idempotency_key = NULL) {
  .sf_assert_client(client)
  if (!nzchar(trimws(as.character(url)))) stop("context requires a url", call. = FALSE)
  viewport <- match.arg(viewport, c("desktop", "mobile"))
  body <- list(url = as.character(url), viewport = viewport,
               delayMs = as.integer(delay_ms))
  if (!is.null(max_text_chars)) body$maxTextChars <- as.integer(max_text_chars)
  .sf_api_call(client, "POST", .sf_endpoint(client, "/api/v1/page/context"),
               body = body, idempotency_key = idempotency_key)
}

snapforge_get_job <- function(client, job_id) {
  .sf_assert_client(client)
  .sf_nonempty(job_id, "get_job requires a job_id")
  .sf_api_call(client, "GET", .sf_endpoint(client, paste0("/api/screenshots/jobs/", .sf_segment(job_id))))
}

snapforge_download_job <- function(client, job_id) {
  .sf_assert_client(client)
  .sf_nonempty(job_id, "download_job requires a job_id")
  .sf_binary_call(client, "GET",
                  .sf_endpoint(client, paste0("/api/screenshots/jobs/", .sf_segment(job_id), "/download")))
}

snapforge_download_job_file <- function(client, job_id, file_name, download = FALSE) {
  .sf_assert_client(client)
  .sf_nonempty(job_id, "download_job_file requires a job_id")
  .sf_nonempty(file_name, "download_job_file requires a file_name")
  suffix <- if (isTRUE(download)) "?download=1" else ""
  .sf_binary_call(client, "GET",
                  .sf_endpoint(client, paste0("/api/screenshots/jobs/", .sf_segment(job_id),
                                             "/files/", .sf_segment(file_name), suffix)))
}

snapforge_download <- function(client, url) {
  .sf_assert_client(client)
  url <- as.character(url)
  if (startsWith(url, "/")) url <- paste0(client$base_url, url)
  if (!grepl("^https?://", url, ignore.case = TRUE)) {
    stop("download url must be absolute http(s) or root-relative", call. = FALSE)
  }
  same_origin <- identical(url, client$base_url) || startsWith(url, paste0(client$base_url, "/"))
  .sf_binary_call(client, "GET", url, include_auth = same_origin)
}

.sf_api_call <- function(client, method, url, body = NULL, headers = list(),
                         idempotency_key = NULL, timeout = client$timeout,
                         include_auth = TRUE) {
  response <- .sf_perform(client, method, url, body, headers,
                          idempotency_key, timeout, include_auth)
  parsed <- .sf_decode_body(response$body)
  quota <- .sf_quota(response$headers, parsed)
  if (response$status < 200L || response$status >= 300L) {
    .sf_stop_http(client, response$status, parsed, quota)
  }
  structure(list(status = response$status, body = parsed,
                 quota = quota, headers = response$headers),
            class = "snapforge_response")
}

.sf_binary_call <- function(client, method, url, include_auth = TRUE) {
  response <- .sf_perform(client, method, url, body = NULL, headers = list(),
                          idempotency_key = NULL, timeout = client$timeout,
                          include_auth = include_auth)
  quota <- .sf_quota(response$headers, NULL)
  if (response$status < 200L || response$status >= 300L) {
    .sf_stop_http(client, response$status, .sf_decode_body(response$body), quota)
  }
  value <- .sf_as_raw(response$body)
  attr(value, "status") <- response$status
  attr(value, "quota") <- quota
  value
}

.sf_perform <- function(client, method, url, body, headers,
                        idempotency_key, timeout, include_auth) {
  timeout <- as.numeric(timeout)
  if (length(timeout) != 1L || !is.finite(timeout) || timeout <= 0) {
    stop("timeout must be a positive number of seconds", call. = FALSE)
  }
  request_headers <- list(Accept = "application/json")
  headers <- as.list(headers)
  if (length(headers)) {
    header_names <- names(headers)
    if (is.null(header_names) || any(!nzchar(header_names))) {
      stop("headers must be named", call. = FALSE)
    }
    headers <- headers[tolower(header_names) != "authorization"]
    request_headers <- c(request_headers, headers)
  }
  if (isTRUE(include_auth) && nzchar(client$access_token)) {
    request_headers$Authorization <- paste("Bearer", client$access_token)
  }
  if (!is.null(idempotency_key) && nzchar(as.character(idempotency_key))) {
    request_headers[["Idempotency-Key"]] <- as.character(idempotency_key)
  }
  if (!is.null(body)) request_headers[["Content-Type"]] <- "application/json"

  spec <- list(method = method, url = url, headers = request_headers,
               body = body, timeout = timeout)
  if (!is.null(client$transport)) {
    return(.sf_normalize_transport_response(client$transport(spec)))
  }

  req <- httr2::request(url)
  req <- httr2::req_method(req, method)
  if (length(request_headers)) {
    req <- do.call(httr2::req_headers, c(list(req), request_headers))
  }
  if (!is.null(body)) req <- httr2::req_body_json(req, body, auto_unbox = TRUE)
  req <- httr2::req_timeout(req, timeout)
  response <- httr2::req_perform(req)
  list(status = as.integer(httr2::resp_status(response)),
       headers = as.list(httr2::resp_headers(response)),
       body = httr2::resp_body_raw(response))
}

.sf_normalize_transport_response <- function(response) {
  if (!is.list(response) || is.null(response$status)) {
    stop("transport must return a list with status, headers, and body", call. = FALSE)
  }
  status <- as.integer(response$status)
  if (length(status) != 1L || is.na(status)) {
    stop("transport response status must be one integer", call. = FALSE)
  }
  list(status = status, headers = as.list(response$headers %||% list()),
       body = response$body %||% raw())
}

.sf_stop_http <- function(client, status, body, quota) {
  safe_body <- .sf_redact(body, c(client$access_token, client$url_secret))
  detail <- ""
  if (is.list(safe_body) && !is.null(safe_body$error)) {
    detail <- as.character(safe_body$error)
  } else if (is.character(safe_body) && length(safe_body) == 1L) {
    detail <- safe_body
  }
  message <- paste0("SnapForge request failed: HTTP ", status)
  if (nzchar(detail)) message <- paste(message, detail)
  message <- .sf_redact(message, c(client$access_token, client$url_secret))
  condition <- structure(list(message = message, call = NULL,
                              status = as.integer(status), body = safe_body,
                              quota = quota),
                         class = c("snapforge_http_error", "error", "condition"))
  stop(condition)
}

.sf_quota <- function(headers, body) {
  quota <- list(limit = .sf_int(.sf_header(headers, "x-ratelimit-limit")),
                remaining = .sf_int(.sf_header(headers, "x-ratelimit-remaining")),
                reset = .sf_int(.sf_header(headers, "x-ratelimit-reset")),
                used = NULL)
  source <- body
  if (is.list(body) && is.list(body$quota)) source <- body$quota
  if (is.list(source)) {
    for (name in c("limit", "remaining", "reset", "used")) {
      if (!is.null(source[[name]])) quota[[name]] <- .sf_int(source[[name]])
    }
  }
  quota
}

.sf_header <- function(headers, name) {
  if (!length(headers) || is.null(names(headers))) return(NULL)
  index <- match(tolower(name), tolower(names(headers)))
  if (is.na(index)) NULL else headers[[index]]
}

.sf_int <- function(value) {
  if (is.null(value) || !length(value)) return(NULL)
  parsed <- suppressWarnings(as.numeric(value[[1L]]))
  if (!is.finite(parsed)) NULL else parsed
}

.sf_decode_body <- function(body) {
  if (is.null(body)) return(NULL)
  if (is.list(body) && !is.raw(body)) return(body)
  if (is.character(body)) text <- paste(body, collapse = "")
  else if (is.raw(body)) {
    if (!length(body)) return(NULL)
    text <- rawToChar(body)
  } else return(body)
  if (!nzchar(text)) return(NULL)
  parsed <- tryCatch(jsonlite::fromJSON(text, simplifyVector = FALSE),
                     error = function(e) NULL)
  if (is.null(parsed)) text else parsed
}

.sf_as_raw <- function(body) {
  if (is.raw(body)) return(body)
  if (is.null(body)) return(raw())
  if (is.character(body)) return(charToRaw(paste(body, collapse = "")))
  charToRaw(jsonlite::toJSON(body, auto_unbox = TRUE, null = "null"))
}

.sf_endpoint <- function(client, path) {
  if (!nzchar(client$url_secret)) return(paste0(client$base_url, path))
  paste0(client$base_url, "/client/", .sf_segment(client$url_secret), path)
}

.sf_segment <- function(value) utils::URLencode(as.character(value), reserved = TRUE)

.sf_public_path <- function(path) {
  path <- as.character(path)
  if (length(path) != 1L || !startsWith(path, "/api/") ||
      startsWith(path, "//") || grepl("^[A-Za-z][A-Za-z0-9+.-]*:", path)) {
    stop("request path must be a relative public /api/* path", call. = FALSE)
  }
  pathname <- strsplit(path, "?", fixed = TRUE)[[1L]][1L]
  if (".." %in% strsplit(pathname, "/", fixed = TRUE)[[1L]]) {
    stop("request path must not contain parent traversal", call. = FALSE)
  }
  lowered <- tolower(pathname)
  private <- c("/api/admin", "/api/internal", "/api/saas-admin")
  if (any(vapply(private, function(prefix) {
    identical(lowered, prefix) || startsWith(lowered, paste0(prefix, "/"))
  }, logical(1)))) {
    stop("request path is not a public API path", call. = FALSE)
  }
  path
}

.sf_normalize_base_url <- function(value) {
  value <- as.character(value)
  if (length(value) != 1L || !grepl("^https?://[^/]+", value, ignore.case = TRUE)) {
    stop("base_url must be an absolute http(s) URL", call. = FALSE)
  }
  sub("/+$", "", value)
}

.sf_assert_client <- function(client) {
  if (!inherits(client, "snapforge_client")) {
    stop("client must be created with snapforge_client()", call. = FALSE)
  }
  invisible(client)
}

.sf_nonempty <- function(value, message) {
  if (length(value) != 1L || !nzchar(trimws(as.character(value)))) {
    stop(message, call. = FALSE)
  }
  invisible(value)
}

.sf_redact <- function(value, secrets) {
  secrets <- secrets[nzchar(secrets)]
  if (!length(secrets) || is.null(value)) return(value)
  if (is.character(value)) {
    for (secret in secrets) value <- gsub(secret, "[REDACTED]", value, fixed = TRUE)
    return(value)
  }
  if (is.list(value)) return(lapply(value, .sf_redact, secrets = secrets))
  value
}

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
