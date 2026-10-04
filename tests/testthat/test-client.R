fake_transport <- function(status = 200L,
                           headers = list("Content-Type" = "application/json",
                                          "X-RateLimit-Limit" = "500",
                                          "X-RateLimit-Remaining" = "499"),
                           body = charToRaw('{"ok":true}')) {
  state <- new.env(parent = emptyenv())
  state$requests <- list()
  fn <- function(request) {
    state$requests[[length(state$requests) + 1L]] <- request
    list(status = status, headers = headers, body = body)
  }
  attr(fn, "state") <- state
  fn
}

last_request <- function(transport) {
  state <- attr(transport, "state")
  state$requests[[length(state$requests)]]
}

test_that("hosted auth, idempotency, timeout and quota are preserved", {
  transport <- fake_transport()
  client <- snapforge_client(access_token = "token-1", transport = transport)
  result <- snapforge_request(
    client, "/api/v1/future-endpoint", method = "POST",
    body = list(hello = "world"),
    headers = list("X-Trace" = "trace-1", Authorization = "malicious"),
    idempotency_key = "idem-1", timeout = 4.25
  )
  seen <- last_request(transport)
  expect_equal(seen$url, "https://snapforge.web-tasarimci.com/api/v1/future-endpoint")
  expect_equal(seen$headers$Authorization, "Bearer token-1")
  expect_equal(seen$headers[["Idempotency-Key"]], "idem-1")
  expect_equal(seen$headers[["X-Trace"]], "trace-1")
  expect_equal(seen$timeout, 4.25)
  expect_equal(result$quota$limit, 500)
  expect_equal(result$quota$remaining, 499)
  expect_true(result$body$ok)
})

test_that("URL-secret mode encodes secrets and core routes", {
  transport <- fake_transport()
  client <- snapforge_client(base_url = "http://localhost:3010/",
                             access_token = "",
                             url_secret = "client secret/+",
                             transport = transport)
  snapforge_capture(client, "https://example.com", idempotency_key = "cap-1")
  seen <- last_request(transport)
  expect_equal(seen$url,
               "http://localhost:3010/client/client%20secret%2F%2B/api/v1/screenshot")
  expect_null(seen$headers$Authorization)
  expect_equal(seen$headers[["Idempotency-Key"]], "cap-1")

  snapforge_context(client, "https://example.com")
  expect_match(last_request(transport)$url, "/api/v1/page/context$")
  snapforge_get_job(client, "job/id")
  expect_match(last_request(transport)$url, "/api/screenshots/jobs/job%2Fid$")
})

test_that("raw request blocks private paths and traversal", {
  client <- snapforge_client(transport = fake_transport())
  paths <- c("/api/admin/users", "/api/internal/x", "/api/saas-admin/x",
             "/api/v1/../admin", "https://evil.example/api/v1")
  for (path in paths) expect_error(snapforge_request(client, path))
})

test_that("quota errors are structured and credentials are redacted", {
  payload <- charToRaw(
    '{"error":"quota exhausted for top-secret","quota":{"limit":500,"remaining":0,"reset":1234,"used":500}}'
  )
  transport <- fake_transport(status = 429L,
                              headers = list("Content-Type" = "application/json"),
                              body = payload)
  client <- snapforge_client(access_token = "top-secret", transport = transport)
  error <- tryCatch(snapforge_capture(client, "https://example.com"),
                    snapforge_http_error = identity)

  expect_s3_class(error, "snapforge_http_error")
  expect_equal(error$status, 429L)
  expect_equal(error$quota$limit, 500)
  expect_equal(error$quota$remaining, 0)
  expect_equal(error$quota$used, 500)
  expect_false(grepl("top-secret", error$message, fixed = TRUE))
  expect_false(grepl("top-secret",
                     jsonlite::toJSON(error$body, auto_unbox = TRUE),
                     fixed = TRUE))
  expect_match(error$message, "[REDACTED]", fixed = TRUE)
})

test_that("downloads never leak bearer auth to third-party origins", {
  transport <- fake_transport(
    body = as.raw(c(1, 2, 3)),
    headers = list("Content-Type" = "application/octet-stream")
  )
  client <- snapforge_client(access_token = "must-not-leak", transport = transport)

  external <- snapforge_download(client, "https://cdn.example.test/file")
  expect_equal(as.vector(external), as.vector(as.raw(c(1, 2, 3))))
  expect_null(last_request(transport)$headers$Authorization)

  local <- snapforge_download(client, "/api/screenshots/jobs/abc/download")
  expect_equal(as.vector(local), as.vector(as.raw(c(1, 2, 3))))
  expect_equal(last_request(transport)$headers$Authorization, "Bearer must-not-leak")
})

test_that("bundled conformance fixture contains every core route", {
  fixture_path <- system.file("conformance", "public-api-v1-legacy.json",
                              package = "snapforge")
  expect_true(nzchar(fixture_path))
  fixture <- jsonlite::fromJSON(fixture_path, simplifyVector = FALSE)
  paths <- vapply(fixture$operations, function(item) item$path, character(1))
  expect_true(all(c(
    "/api/v1",
    "/api/v1/screenshot",
    "/api/v1/page/context",
    "/api/screenshots/jobs/{jobId}/download",
    "/api/screenshots/jobs/{jobId}/files/{fileName}"
  ) %in% paths))
})
