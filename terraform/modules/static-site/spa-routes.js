// CloudFront Functions runtime 2.0. Runs on every viewer request, before the
// cache: an app route is rewritten to /index.html, a file path passes through.
function handler(event) {
  var request = event.request;
  var last = request.uri.split('/').pop();

  if (last.indexOf('.') === -1) {
    request.uri = '/index.html';
  }

  return request;
}
