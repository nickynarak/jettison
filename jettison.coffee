jspack = require('jspack').jspack


isValidType = (type) ->
  switch (type)
    when 'boolean', 'int8', 'int16', 'int32', 'uint8', 'uint16', 'uint32', \
         'float32', 'float64'
      true
    else
      false


class Field

  constructor: ({@key, @type, @arrayType}) ->
    if not @key
      throw new Error('key is required')
    if not isValidType(@type)
      throw new Error('invalid type "#{@type}"')
    if @type is 'array' and not isValidType(@arrayType)
      throw new Error('invalid array type "#{@arrayType}"')
    @packer = exports.packers[@type]


class Definition

  constructor: (@fields, {@littleEndian}={}) ->
    chunk = []
    @chunks = [chunk]
    for field in @fields
      if field.type == 'array'
        chunk = []
        @chunks.push(chunk)
      chunk.push(field)

  toByteArray: (values) ->
    bytes = []
    index = 0
    for chunk in @chunks
      for field in chunk
        bytes = bytes.concat(field.packer.pack(values[index], @littleEndian))
        index += 1
    bytes

  fromByteArray: (bytes, byteIndex=0) ->
    values = []
    for chunk in @chunks
      for field in chunk
        values.push(field.packer.unpack(bytes, byteIndex, @littleEndian))
        byteIndex += field.packer.length
    values


class FormatPacker

  constructor: (format) ->
    @format = format
    @littleFormat = '<' + @format
    @bigFormat = '>' + @format
    @length = jspack.CalcLength(@format)

  pack: (value, littleEndian) ->
    format = if littleEndian then @littleFormat else @bigFormat
    jspack.Pack(format, [value])

  unpack: (bytes, byteIndex, littleEndian) ->
    format = if littleEndian then @littleFormat else @bigFormat
    jspack.Unpack(format, bytes, byteIndex)[0]


packers =
  boolean:
    length: 1
    pack: (value) ->
      if value then [1] else [0]
    unpack: (bytes, byteIndex, littleEndian) ->
      if bytes[byteIndex] then true else false
  float32: new FormatPacker('f')
  float64: new FormatPacker('d')
  int8: new FormatPacker('b')
  int16: new FormatPacker('h')
  int32: new FormatPacker('i')
  uint8: new FormatPacker('B')
  uint16: new FormatPacker('H')
  uint32: new FormatPacker('I')


# Convert an encoded string into a byte array.
stringToByteArray = (string) ->
  i = 0
  bytes = new Array(string.length)
  while i < string.length
    bytes[i] = string.charCodeAt(i)
    i += 1
  bytes


# Convert a byte array into a string. This can end up being a bit more wasteful
# than the original byte array, but we need to do it this way to send things
# reliably over websockets.
byteArrayToString = (bytes) ->
  string = ''
  for byte in bytes
    string += String.fromCharCode(byte)
  string


define = (fields) ->
  new Definition(fields.map (options) -> new Field(options))


exports.packers = packers
exports.define = define
exports.byteArrayToString = byteArrayToString
exports.stringToByteArray = stringToByteArray
