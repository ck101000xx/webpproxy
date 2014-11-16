http = require 'http'
url = require 'url'
_ = require 'underscore'
sharp = require 'sharp'
zlib = require 'zlib'
net = require 'net'

compress = (maxWidth, quality, format) ->
  sharp()
    .withoutEnlargement()
    .resize(maxWidth)
    .quality(quality)[format]()

server = http.createServer (req, res) ->
  options = _.extend(
    _.pick(url.parse(req.url),
           'auth', 'hostname', 'port', 'path'),
    _.pick(req, 'method', 'headers'))
  req.pipe http.request options, (clientRes) ->
    res.setHeader key, value for key, value of clientRes.headers
    res.statusCode = clientRes.statusCode;
    transformer = switch clientRes.headers['content-type']
      when 'image/png', 'image/jpeg'
        format =
          if req.headers['accept'].indexOf('image/webp') isnt -1 
          then 'webp' else 'jpeg'
        res.setHeader 'content-type', "image/#{format}"
        compress 854, 50, format
    unless transformer?
      clientRes.pipe res
    else
      res.removeHeader 'content-length'
      if clientRes.headers['content-encoding'] is 'gzip'
        transformer =
          zlib.createGunzip()
            .pipe transformer
            .pipe zlib.createGzip()
      transformer.on 'error', (err) -> console.log err
      clientRes.pipe(transformer).pipe(res)

server.addListener 'connect', (request, socket, head) ->
  parsed = url.parse "//#{request.url}", false, true
  version = request.httpVersion;
  proxySocket = net.connect
    port: parseInt(parsed.port || 443)
    host: parsed.hostname
    ->
      proxySocket.write head
      socket.write "HTTP/#{version} 200 Connection established\r\n\r\n"
  proxySocket.on 'error', ->
    socket.write "HTTP/#{version} 500 Connection error\r\n\r\n"
    socket.end()
  socket.on 'error', ->
    proxySocket.end()
  proxySocket.pipe socket
  socket.pipe proxySocket

server.listen 8080
