utf8 = require 'utf8'

polyfill = require './polyfill'


globals = global ? window
if globals? and globals.ArrayBuffer? and globals.DataView?
  config =
    ArrayBuffer: globals.ArrayBuffer
    DataView: globals.DataView
else
  config =
    ArrayBuffer: polyfill.ArrayBufferPolyfill
    DataView: polyfill.DataViewPolyfill


# These codecs are used as simple helpers for getting a value from or setting
# a value on a StreamView object. They handle any clamping that needs to be
# done on the value, and also handle advancing the StreamView's byteOffset.
#
# Codec, BooleanCodec, FloatCodec, and IntegerCodec all have fixed sizes. That
# is, their byteLength is consistent regardless of the values being encoded.
#
# ArrayCodec and StringCodec both have dynamic sizes. Their byte length will
# change depending on the values being encoded. For these codecs, you can get
# the byte length by calling `getByteLength()`.

class Codec

  constructor: ({@byteLength, @getter, @setter}) ->
    unless @byteLength > 0
      throw new Error('byteLength must be a positive integer')
    unless config.DataView.prototype[@getter]?
      throw new Error("getter '#{@getter}' must be a DataView method")
    unless config.DataView.prototype[@setter]?
      throw new Error("setter '#{@setter}' must be a DataView method")

  get: (streamView, littleEndian) ->
    value = streamView.dataView[@getter](streamView.byteOffset, littleEndian)
    streamView.byteOffset += @byteLength
    value

  set: (streamView, value, littleEndian) ->
    streamView.dataView[@setter](streamView.byteOffset, value, littleEndian)
    streamView.byteOffset += @byteLength


class BooleanCodec extends Codec

  # This is just like the uint8 codec, but get() returns true or false values.

  constructor: ->
    super(byteLength: 1, getter: 'getUint8', setter: 'setUint8')

  get: (streamView, littleEndian) ->
    if super(streamView, littleEndian) then true else false

  set: (streamView, value, littleEndian) ->
    super(streamView, (if value then 1 else 0), littleEndian)


class FloatCodec extends Codec

  # Handles IEEE-754 floating point values. Only single and double precision
  # are supported.

  constructor: ({byteLength}) ->
    if byteLength == 4
      super(byteLength: byteLength, getter: 'getFloat32', setter: 'setFloat32')
    else if byteLength == 8
      super(byteLength: byteLength, getter: 'getFloat64', setter: 'setFloat64')
    else
      throw new RangeError('byteLength must be 4 or 8 for floats')


class IntegerCodec extends Codec

  # Handles integer values. Note that set will clamp values that are out of
  # range for the given type (e.g. >= 127 becomes 127 for a signed int8).

  constructor: ({byteLength, signed}) ->
    bitLength = byteLength * 8
    if signed
      @minValue = -Math.pow(2, bitLength - 1)
      @maxValue = Math.pow(2, bitLength - 1) - 1
      getter = "getInt#{bitLength}"
      setter = "setInt#{bitLength}"
    else
      @minValue = 0
      @maxValue = Math.pow(2, bitLength) - 1
      getter = "getUint#{bitLength}"
      setter = "setUint#{bitLength}"
    super byteLength: byteLength, getter: getter, setter: setter

  set: (streamView, value, littleEndian) ->
    if value < @minValue
      value = @minValue
    else if value > @maxValue
      value = @maxValue
    super(streamView, value, littleEndian)


class ArrayCodec

  # An array codec is a special case. It wraps a simple codec, but prefixes
  # it with a uint32 length value. It will first read the length, then read
  # than many of the values from the stream.

  constructor: (valueCodec) ->
    @lengthCodec = codecs.uint32
    if typeof valueCodec == 'string'
      @valueCodec = codecs[valueCodec]
      unless @valueCodec
        throw new Error("Invalid array value type '#{valueCodec}'")
    else
      @valueCodec = valueCodec

  getByteLength: (values) ->
    return 0 unless values?.length > 0
    if @valueCodec.byteLength?
      # The value codec has a fixed byte length.
      @lengthCodec.byteLength + values.length * @valueCodec.byteLength
    else
      # The value codec has a dynamic byte lenth (e.g. an array of strings of
      # different lengths), so we need to get the size of each value on the fly.
      byteLength = @lengthCodec.byteLength
      for value in values
        byteLength += @valueCodec.getByteLength(value)
      byteLength

  get: (streamView, littleEndian) ->
    # First read the number of elements, then read the elements
    length = @lengthCodec.get(streamView, littleEndian)
    if length > 0
      values = new Array(length)
      for index in [0...length]
        values[index] = @valueCodec.get(streamView, littleEndian)
      values
    else
      []

  set: (streamView, values, littleEndian) ->
    length = values?.length or 0
    @lengthCodec.set(streamView, length, littleEndian)
    if length > 0
      for value in values
        @valueCodec.set(streamView, value, littleEndian)


class StringCodec

  # The string codec is another special case. JavaScript strings are UTF-16,
  # which doesn't encode very efficiently for network traffic. The codec first
  # converts the strings to UTF-8, then converts that to a byte array. The
  # byte array is prefixed with the length of the UTF-8 string.
  #
  # FIXME: Could probably do this a bit more efficiently by encoding UTF-8
  # ourselves instead of using encodeURIComponent.

  constructor: ->
    @lengthCodec = codecs.uint32
    @valueCodec = codecs.uint8

  getByteLength: (value) ->
    # FIXME: This sucks, shouldn't need to encode strings twice.
    value = utf8.encode(value) if value
    @lengthCodec.byteLength + @valueCodec.byteLength * value.length

  get: (streamView, littleEndian) ->
    # First read the number of characters, then the characters
    length = @lengthCodec.get(streamView, littleEndian)
    if length > 0
      string = ''
      for _ in [0...length]
        string += String.fromCharCode(@valueCodec.get(streamView, littleEndian))
      # The string is in UTF-8 format, convert it back to UTF-16
      utf8.decode(string)
    else
      ''

  set: (streamView, value, littleEndian) ->
    if value
      # Convert the string to UTF-8 to save space
      utf8String = utf8.encode(value)
      @lengthCodec.set(streamView, utf8String.length, littleEndian)
      for i in [0...utf8String.length]
        @valueCodec.set(streamView, utf8String.charCodeAt(i), littleEndian)
    else
      # Undefined or empty string, just send a zero length
      @lengthCodec.set(streamView, 0, littleEndian)


# This is a set of codecs that can be used by fields to convert typed values
# into an array of bytes, and to convert those bytes back into values. Note
# that the "array" type does not have a codec in this object, because
# ArrayCodec objects are created on the fly as needed.

codecs =
  boolean: new BooleanCodec
  float32: new FloatCodec(byteLength: 4)
  float64: new FloatCodec(byteLength: 8)
  int8: new IntegerCodec(byteLength: 1, signed: true)
  int16: new IntegerCodec(byteLength: 2, signed: true)
  int32: new IntegerCodec(byteLength: 4, signed: true)
  uint8: new IntegerCodec(byteLength: 1, signed: false)
  uint16: new IntegerCodec(byteLength: 2, signed: false)
  uint32: new IntegerCodec(byteLength: 4, signed: false)

# Create this last, because it refers to the uint32 and uint8 codecs internally.
codecs.string = new StringCodec()


class StreamView

  constructor: (@dataView, @arrayBuffer) ->
    @byteOffset = 0

  toArray: ->
    array = new Array(@dataView.byteLength)
    for byteOffset in [0...@dataView.byteLength]
      array[byteOffset] = @dataView.getUint8(byteOffset)
    array

  toString: ->
    string = ''
    for byteOffset in [0...@dataView.byteLength]
      string += String.fromCharCode(@dataView.getUint8(byteOffset))
    string

  @create: (byteLength) ->
    arrayBuffer = new config.ArrayBuffer(byteLength)
    dataView = new config.DataView(arrayBuffer)
    new StreamView(dataView, arrayBuffer)

  @createFromString: (string) ->
    codec = codecs.uint8
    streamView = @create(string.length)
    for index in [0...string.length]
      codec.set(streamView, string.charCodeAt(index))
    streamView.byteOffset = 0
    streamView


# Return true if the type is one of the allowed types.
isValidType = (type) ->
  switch (type)
    when 'array', 'string', 'boolean', 'int8', 'int16', 'int32', 'uint8', \
         'uint16', 'uint32', 'float32', 'float64'
      true
    else
      false


class Field

  # Fields represent a single property in an object. These fields are grouped
  # into definition objects.

  constructor: ({@key, @type, @valueType}) ->
    if not @key
      throw new Error('key is required')
    if not isValidType(@type)
      throw new Error("Invalid type '#{@type}'")
    @codec = if @type is 'array'
      if (@valueType is 'array' or @valueType is 'string' or
          not isValidType(@valueType))
        throw new Error("Invalid array value type '#{@valueType}'")
      new ArrayCodec(@valueType)
    else
      codecs[@type]


class Definition

  # Definitions are a grouping of fields, and are used to encode or decode an
  # individual message. They can be grouped into schemas or used standalone.

  constructor: (@fields, {@id, @key, @littleEndian}={}) ->

  getByteLength: (object) ->
    return @byteLength if @byteLength?
    byteLength = 0
    fixedByteLength = true
    for {key, codec} in @fields
      if codec.byteLength?
        byteLength += codec.byteLength
      else
        byteLength += codec.getByteLength(object[key])
        fixedByteLength = false
    @byteLength = byteLength if fixedByteLength
    byteLength

  get: (streamView) ->
    values = {}
    for {key, codec} in @fields
      values[key] = codec.get(streamView, @littleEndian)
    values

  set: (streamView, object) ->
    for {key, codec} in @fields
      codec.set(streamView, object[key], @littleEndian)

  parse: (string) ->
    @get(StreamView.createFromString(string))

  stringify: (object) ->
    streamView = StreamView.create(@getByteLength(object))
    @set(streamView, object)
    streamView.toString()


class Schema

  # A schema is a grouping of definitions. It allows you to encode packets
  # by name, in a way that can be decoded automatically by a matching schema
  # on the other end of a connection.
  #
  # Note that this assumes you won't have more than 255 packets, for now. If
  # you need more than that, you can pass an idType: option to the constructor.

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
    streamView = StreamView.createFromString(string)
    idCodec = codecs[@idType]
    id = idCodec.get(streamView)
    unless (definition = @definitionsById[id])?
      throw new Error("'#{id}' is not defined in schema")
    definition.get(streamView)

  stringify: (key, object) ->
    unless (definition = @definitions[key])?
      throw new Error("'#{key}' is not defined in schema")
    idCodec = codecs[@idType]
    streamView = StreamView.create(idCodec.byteLength +
                                   definition.getByteLength(object))
    idCodec.set(streamView, definition.id)
    definition.set(streamView, object)
    streamView.toString()


# Create a new Definition object.
define = (fields) ->
  new Definition(fields.map (options) -> new Field(options))


# Create a new Schema object.
createSchema = ->
  new Schema()


exports._codecs = codecs
exports._config = config
exports._polyfill = polyfill
exports._StreamView = StreamView
exports.createSchema = createSchema
exports.define = define
