\name{snapforge}
\alias{snapforge}
\alias{snapforge_client}
\alias{snapforge_request}
\alias{snapforge_service_info}
\alias{snapforge_capture}
\alias{snapforge_context}
\alias{snapforge_get_job}
\alias{snapforge_download_job}
\alias{snapforge_download_job_file}
\alias{snapforge_download}
\title{Official R client for the SnapForge API}
\description{
Create a client for the hosted SnapForge service or an explicitly configured
self-hosted endpoint, then capture screenshots, read page context, inspect
persisted jobs, download artifacts, or call compatible public API endpoints.
}
\usage{
snapforge_client(
  base_url = "https://snapforge.web-tasarimci.com",
  access_token = Sys.getenv("SNAPFORGE_API_KEY", unset = ""),
  url_secret = NULL,
  timeout = 60,
  transport = NULL
)
snapforge_request(client, path, method = "GET", body = NULL,
  headers = list(), idempotency_key = NULL, timeout = NULL)
snapforge_service_info(client)
snapforge_capture(client, url, device = "both", full_page = TRUE,
  delay_ms = 1200L, ttl_seconds = NULL, idempotency_key = NULL)
snapforge_context(client, url, viewport = "desktop", delay_ms = 800L,
  max_text_chars = NULL, idempotency_key = NULL)
snapforge_get_job(client, job_id)
snapforge_download_job(client, job_id)
snapforge_download_job_file(client, job_id, file_name, download = FALSE)
snapforge_download(client, url)
}
\arguments{
\item{client}{A client returned by \code{snapforge_client()}.}
\item{base_url}{Hosted or explicit self-hosted base URL.}
\item{access_token}{Bearer token. Defaults to \code{SNAPFORGE_API_KEY}.}
\item{url_secret}{Optional URL-secret authentication value.}
\item{timeout}{Request timeout in seconds.}
\item{transport}{Optional custom transport function, primarily for testing.}
\item{path}{Relative public \code{/api/*} path. Private/admin paths are rejected.}
\item{method}{HTTP method.}
\item{body}{Optional JSON-compatible request body.}
\item{headers}{Optional named headers. Authorization cannot be overridden.}
\item{idempotency_key}{Optional idempotency key.}
\item{url}{Target URL.}
\item{device}{One of \code{desktop}, \code{mobile}, or \code{both}.}
\item{full_page}{Whether to capture the full page.}
\item{delay_ms}{Delay before capture/context collection in milliseconds.}
\item{ttl_seconds}{Optional screenshot artifact TTL.}
\item{viewport}{One of \code{desktop} or \code{mobile}.}
\item{max_text_chars}{Optional visible-text limit.}
\item{job_id}{Persisted screenshot job identifier.}
\item{file_name}{Artifact filename.}
\item{download}{Whether to add \code{download=1}.}
}
\value{
API helpers return a \code{snapforge_response} containing HTTP status, parsed
body, quota metadata and response headers. Download helpers return a raw vector
with \code{status} and \code{quota} attributes.
}
\details{
HTTP failures raise a structured \code{snapforge_http_error} condition with
\code{status}, redacted \code{body}, and \code{quota} fields. Credentials are
not included in diagnostics. Bearer credentials are never forwarded when
\code{snapforge_download()} is given an explicit third-party artifact URL.
}
\examples{
client <- snapforge_client(access_token = "example-not-a-real-token")
\dontrun{
result <- snapforge_capture(client, "https://example.com")
result$body
}
}
