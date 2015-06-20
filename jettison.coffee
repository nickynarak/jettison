jspack = require('jspack').jspack


class ArrayPacker

  # An array packer is a special case. It wraps a format packer, but prefixes
  # it with a uint32 length value. It will first read the length, then read
  # than many of the values from the byte array.

  constructor: (@valueFormat) ->

  fromByteArray: (bytes, byteIndex, littleEndian) ->
    # First read the number of elements in the array
    lengthFormat = if littleEndian then '<I' else '>I'
    lengthLength = jspack.CalcLength(lengthFormat)
    length = jspack.Unpack(lengthFormat, bytes, byteIndex)
    # Then read all the elements
    if length > 0
      valuesFormat = (if littleEndian then '<' else '>') + length + @valueFormat
      valuesLength = jspack.CalcLength(valuesFormat)
      @length = lengthLength + valuesLength
      jspack.Unpack(valuesFormat, bytes, byteIndex + lengthLength)
    else
      @length = lengthLength
      []

  toByteArray: (values, littleEndian) ->
    length = values?.length or 0
    if length > 0
      format = (if littleEndian then '<' else '>') + 'I' + length + @valueFormat
      jspack.Pack(format, [length].concat(values))
    else
      # Undefined or empty array, just send a 0 length
      [0, 0, 0, 0]


class FormatPacker

  # This class encapsulated jspack. The library uses jspack under the hood for
  # now, but will hopefully its own packing code in the future. jspack does
  # a lot of regexp magic that jettison doesn't really need.

  constructor: (format) ->
    @format = format
    @littleFormat = '<' + @format
    @bigFormat = '>' + @format
    @length = jspack.CalcLength(@format)

  fromByteArray: (bytes, byteIndex, littleEndian) ->
    format = if littleEndian then @littleFormat else @bigFormat
    values = jspack.Unpack(format, bytes, byteIndex)
    throw new Error("Error unpacking format #{format} at byteIndex #{byteIndex}
                     (byte array doesn't have enough elements)") unless values?
    values[0]

  toByteArray: (value, littleEndian) ->
    format = if littleEndian then @littleFormat else @bigFormat
    jspack.Pack(format, [value])


# This is a set of packers that can be used by fields to convert typed values
# into an array of bytes, and to convert those bytes back into values. Note
# that the "array" type does not have a packer in this object, because
# ArrayPacker objects are created on the fly as needed.
packers =
  boolean:
    length: 1
    fromByteArray: (bytes, byteIndex, littleEndian) ->
      if bytes[byteIndex] then true else false
    toByteArray: (value) ->
      if value then [1] else [0]
  float32: new FormatPacker('f')
  float64: new FormatPacker('d')
  int8: new FormatPacker('b')
  int16: new FormatPacker('h')
  int32: new FormatPacker('i')
  uint8: new FormatPacker('B')
  uint16: new FormatPacker('H')
  uint32: new FormatPacker('I')


# Return true is the type is *not* one of the allowed types.
isInvalidType = (type) ->
  switch (type)
    when 'array', 'boolean', 'int8', 'int16', 'int32', 'uint8', 'uint16', \
         'uint32', 'float32', 'float64'
      false
    else
      true


class Field

  # Fields represent a single property in an object. These fields are grouped
  # into definition objects.

  constructor: ({@key, @type, @valueType}) ->
    if not @key
      throw new Error('key is required')
    if isInvalidType(@type)
      throw new Error("invalid type '#{@type}'")
    @packer = if @type is 'array'
      if @valueType is 'array' or isInvalidType(@valueType)
        throw new Error("invalid array value type '#{@valueType}'")
      new ArrayPacker(packers[@valueType].format)
    else
      packers[@type]


class Definition

  # Definitions are a grouping of fields, and are used to encode or decode an
  # individual message. They can be grouped into schemas or used standalone.

  constructor: (@fields, {@id, @key, @littleEndian}={}) ->

  fromByteArray: (bytes, byteIndex=0) ->
    values = {}
    for {key, packer} in @fields
      values[key] = packer.fromByteArray(bytes, byteIndex, @littleEndian)
      byteIndex += packer.length
    values

  toByteArray: (object) ->
    bytes = []
    for {key, packer} in @fields
      bytes = bytes.concat(packer.toByteArray(object[key], @littleEndian))
    bytes

  parse: (string) ->
    @fromByteArray(stringToByteArray(string))

  stringify: (object) ->
    byteArrayToString(@toByteArray(object))


class Schema

  # A schema is a grouping of definitions. It allows you to encode packets
  # by name, in a way that can be decoded automatically by a matching schema
  # on the other end of a connection.
  #
  # Note that this assumes you won't have more than 255 packets, for now.

  constructor: ({@idType}={}) ->
    @definitions = {}
    @definitionsById = {}
    @idType or= 'uint8'
    @nextDefinitionId = 1

  define: (key, fields) ->
    id = @nextDefinitionId++
    definition = new Definition(fields.map((options) -> new Field(options)),
                                id: id, key: key)
    @definitions[key] = definition
    @definitionsById[id] = definition
    definition

  parse: (string) ->
    bytes = stringToByteArray(string)
    idPacker = packers[@idType]
    id = idPacker.fromByteArray(bytes, 0)
    unless (definition = @definitionsById[id])?
      throw new Error("'#{id}' is not defined in schema")
    definition.fromByteArray(bytes, idPacker.length)

  stringify: (key, object) ->
    unless (definition = @definitions[key])?
      throw new Error("'#{key}' is not defined in schema")
    idBytes = packers[@idType].toByteArray(definition.id)
    byteArrayToString(idBytes.concat(definition.toByteArray(object)))


# Convert a byte array into a string. This can end up being a bit more wasteful
# than the original byte array, but we need to do it this way to send things
# reliably over websockets.
byteArrayToString = (bytes) ->
  string = ''
  for byte in bytes
    string += String.fromCharCode(byte)
  string


# Convert an encoded string into a byte array.
stringToByteArray = (string) ->
  i = 0
  bytes = new Array(string.length)
  while i < string.length
    bytes[i] = string.charCodeAt(i)
    i += 1
  bytes


# Create a new Definition object.
define = (fields) ->
  new Definition(fields.map (options) -> new Field(options))


# Create a new Schema object.
createSchema = ->
  new Schema()


exports._byteArrayToString = byteArrayToString
exports._packers = packers
exports._stringToByteArray = stringToByteArray
exports.createSchema = createSchema
exports.define = define
