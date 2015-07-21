Math.log2 ||= (value) -> Math.log(value) / Math.LN2


class BooleanCodec

  length: 1

  fromByteArray: (bytes, byteIndex, littleEndian) ->
    if bytes[byteIndex] then true else false

  toByteArray: (value) ->
    if value then [1] else [0]


class FloatCodec

  # Oh boy, you're looking at this code, eh?
  #
  # It's a bit difficult to follow, so here's a quick summary of the way
  # IEEE-754 floating point encoding works. The floating point value is
  # deconstructed into three separate values: a signed bit, an exponent, and
  # a significand. These three values can be combined to recreate the original
  # float with the formula: sign * Math.pow(2, exponent) * significand
  #
  # The sign value always gets 1 bit, and the number of bits for the other
  # two depends on the total storage allowed (4 bytes for float32, 8 bytes for
  # float64). For a float32, the significand gets 23 bits and the exponent gets
  # 8. For example, for a big endian float32 value, the components are laid out
  # most significant to least significant like so:
  #
  # - sign (bit 0)
  # - exponent (bits 1..9)
  # - significand (bits 10..32)
  #
  # There are some special cases for representing special values:
  #
  # - NaN has all the exponent and significand bits set.
  # - Infinity has all the exponent bits set, all the significand bits unset,
  #   and the sign bit unset. -Infinity is the same, but the sign bit is set.
  # - An exponent with all the bits unset represents a denormalized value (or
  #   zero, if all the significand bits are also unset).
  # - Anything else is a normalized value.
  #
  # As for the difference between normalized and denormalized values... I'm
  # getting out of my knowledge area here, but normalized values are ones that
  # are representable using both an exponent and a significand component.
  # Denormalized values represent the range between the smallest possible
  # normalized value and zero.
  #
  # So, that is to say, if you had a normalized value with an exponent with the
  # least significant bit set, and a significand with all bits unset, your
  # value is something like 1.17549435E-38. For a denormalized value where all
  # bits of the exponent are unset and all bits of the significand are set is
  # something like 1.1754942E-38 -- just below the smallest normalized value.
  #
  # You'll find a far better explanation here:
  # http://stackoverflow.com/a/15142269/648615
  #
  # This floating point calculator is fun for playing around with bit values:
  # http://www.h-schmidt.net/FloatConverter/IEEE754.html
  #
  # Hopefully that's enough to get you started!

  constructor: (@length, @numSignificandBits, @rt=0) ->
    @numExponentBits = @length * 8 - @numSignificandBits - 1
    @exponentMax = (1 << @numExponentBits) - 1
    @exponentBias = @exponentMax >> 1

  fromByteArray: (bytes, byteIndex, littleEndian) ->
    if littleEndian
      # For little endian, start at the end and read backwards, because we're
      # reading the most significant bytes first.
      i = @length - 1
      increment = -1
    else
      i = 0
      increment = 1

    # For the first byte, the high bit is the signed bit.
    # The rest is part of the exponent.
    signedAndExponent = bytes[byteIndex + i]
    signed = (signedAndExponent >> 7)
    exponent = signedAndExponent & 127
    i += increment

    # Keep reading bytes until we've read the whole exponent.
    remainingExponentBits = @numExponentBits - 7
    while remainingExponentBits > 0
        exponent = exponent * 256 + bytes[byteIndex + i]
        remainingExponentBits -= 8
        i += increment

    # Part of our last byte will be shared between the significand and exponent
    # values, so we need to chop it up like we did with the signed bit. If
    # numBits is -7, then we had 7 bits of the significand in the last byte.
    significand = exponent & ((1 << -remainingExponentBits) - 1)
    exponent >>= -remainingExponentBits
    remainingSignificandBits = @numSignificandBits + remainingExponentBits

    # Keep reading until we've read the whole significand.
    while remainingSignificandBits > 0
      significand = significand * 256 + bytes[byteIndex + i]
      remainingSignificandBits -= 8
      i += increment

    # Handle special cases indicated by the value of exponent.
    switch exponent
      when 0
        # Zero, or denormalized number.
        exponent = 1 - @exponentBias
      when @exponentMax
        # NaN, or +/-Infinity.
        return if significand
          NaN
        else if signed
          -Infinity
        else
          Infinity
      else
        # Normalized number.
        significand += Math.pow(2, @numSignificandBits)
        exponent -= @exponentBias
    return ((if signed then -1 else 1) * significand *
            Math.pow(2, exponent - @numSignificandBits))

  toByteArray: (value, littleEndian) ->
    if isNaN(value)
      signed = 0
      biasedExponent = @exponentMax
      significand = 1
    else if value == Infinity
      signed = 0
      biasedExponent = @exponentMax
      significand = 0
    else if value == -Infinity
      signed = 1
      biasedExponent = @exponentMax
      significand = 0
    else if value == 0
      signed = if 1 / value == -Infinity then 1 else 0
      biasedExponent = 0
      significand = 0
    else
      # Encoding gets a little mathy. I'll try to walk through it. We're trying
      # to calculate exponent and significand such that:
      #
      #     2^x * s = v
      #
      # Where v is the absolute value of the native float that we are encoding,
      # `x` is the exponent, and `s` is the significand.
      #
      # Let's look at exponent first. Remember that a logarithm base 2 of a
      # value gives you the exponent you need to raise 2 to get the value. That
      # is to say, if you ignore the significand, you can solve this formula
      # for `x` like so:
      #
      #     2^x == v
      #     x == log10(v) / log10(2)
      #
      # However, for IEEE 754 encoding, we need the exponent to be a whole
      # number, and most numbers aren't an even power of 2. For example:
      #
      #     > Math.log2(0.1)
      #     -3.321928094887362
      #     > Math.log2(2)
      #     1
      #     > Math.log2(3)
      #     1.584962500721156
      #     > Math.log2(4)
      #     2
      #
      # We end up getting non-integer values. This is where the significand
      # comes in. We need to ensure that the exponent is an integer, and then
      # make the significand `s` where `1 <= s < 2`, and multiplying `pow(2, x)`
      # by `s` gives us `v`. IEEE 754 also makes the whole part (the 1 in 1.23)
      # implicit. So our updated formula for `x` must be:
      #
      #     x = floor(log10(v) / log10(2))
      #
      #  And our formula for `s` is:
      #
      #     2^x * (1 + s) = v
      #     s + 1 = v / 2^x
      #     s + 1 = v * (1 / 2^x)
      #     s + 1 = v * 2^-x
      #     s = (v * 2^-x) - 1
      #
      # Time to take a nap.

      signed = if value < 0 then 1 else 0
      absValue = Math.abs(value)
      exponent = Math.floor(Math.log2(absValue))
      coefficient = Math.pow(2, -exponent)
      if absValue * coefficient < 1
        # Apparently Math.log() isn't 100% reliable? I haven't een a case yet
        # where it doesn't give us the correct value, but the original jspack
        # code had a comment and this logic, so I'll leave it.
        exponent -= 1
        coefficient *= 2

      # NOTE: This is from jspack's original code. I'm still trying to
      # understand exactly why it works.
      #
      # Round by adding 1/2 the significand's least significant digit
      if exponent + @exponentBias >= 1
          # Normalized: numSignificandBits significand digits
          absValue += (@rt / coefficient)
      else
          # Denormalized: <= numSignificandBits significand digits
          absValue += (@rt * Math.pow(2, 1 - @exponentBias))

      if absValue * coefficient >= 2
        # Rounding can mean we need to increment the exponent
        exponent += 1
        coefficient /= 2

      # The exponent's range is limited by the number of bits available to it.
      # In the case of a float64, the exponent has 11 bits, which gives us an
      # unsigned maximum of:
      #
      #     > parseInt('11111111111', 2)
      #     2047
      #
      # But the cases where all the bits are on or off for an exponent have
      # special meaning (all bits off means it's zero or a denormalized number,
      # all on means NaN or Infinity). This means that we need to leave the
      # least significant bit unset for the maximum, which means our maximum
      # and minimum unsigned ranges representable in a float64 exponent are:
      #
      #     > parseInt('11111111110', 2)
      #     2046
      #     > parseInt('00000000001', 2)
      #     1
      #
      # But the exponent is signed. The IEEE 754 way to deal with this is to
      # add a bias of half the maximum to the signed exponent to get it into
      # the unsigned range, which means our *actual* signed exponent range for
      # float64 is:
      #
      #     > bias = 2046 / 2
      #     1023
      #     > parseInt('11111111110', 2) - bias
      #     1023
      #     > parseInt('00000000001', 2) - bias
      #     -1022
      #
      # That's what the logic below is handling.

      biasedExponent = exponent + @exponentBias
      if biasedExponent >= @exponentMax
        # This exponent is too large to be represented by the number of bits
        # that this type of float allows to the exponent. This means the value
        # has overflowed, and will be treated as Infinity instead.
        significand = 0
        biasedExponent = @exponentMax
      else if biasedExponent < 1
        # Denormalized.
        significand = (absValue * Math.pow(2, @exponentBias - 1) *
                       Math.pow(2, @numSignificandBits))
        biasedExponent = 0
      else
        # Normalized, calculate the significand the regular way. Note that term
        # order matters to prevent overflows in this calculation.
        significand = ((absValue * coefficient - 1) *
                       Math.pow(2, @numSignificandBits))

    @_floatPartsToByteArray(signed, biasedExponent, significand, littleEndian)

  # This function does just the byte encoding, after the float has been
  # separated into the component parts required for IEEE-754 encoding.
  _floatPartsToByteArray: (signed, exponent, significand, littleEndian) ->
    if littleEndian
      i = 0
      increment = 1
    else
      # If big endian, start at the end and write backwards, because we're
      # writing the least significant bytes first.
      i = @length - 1
      increment = -1

    # FIXME: This should support passing in an existing array to write into.
    # Adding a no-op byteIndex here for future support.
    bytes = new Array(@length)
    byteIndex = 0

    remainingSignificandBits = @numSignificandBits
    while remainingSignificandBits >= 8
      bytes[byteIndex + i] = significand & 0xff
      significand /= 256
      remainingSignificandBits -= 8
      i += increment

    # We're encoding whole bytes, but the different components aren't byte
    # aligned, so part of the significand can bleed into the exponent. This
    # handles encoding those leftover bits into the exponent's bytes.
    exponent = (exponent << remainingSignificandBits) | significand
    remainingExponentBits = @numExponentBits + remainingSignificandBits
    while remainingExponentBits > 0
      bytes[byteIndex + i] = exponent & 0xff
      exponent /= 256
      remainingExponentBits -= 8
      i += increment

    bytes[byteIndex + i - increment] |= signed * 128

    bytes

class IntegerCodec

  constructor: (@length, {@signed}) ->
    @bitLength = @length * 8
    if @signed
      @signBit = Math.pow(2, @bitLength - 1)
      @minValue = -Math.pow(2, @bitLength - 1)
      @maxValue = Math.pow(2, @bitLength - 1) - 1
    else
      @minValue = 0
      @maxValue = Math.pow(2, @bitLength) - 1

  fromByteArray: (bytes, byteIndex, littleEndian) ->
    if littleEndian
      i = 0
      increment = 1
    else
      i = @length - 1
      increment = -1
    value = 0
    scale = 1
    stop = i + (increment * @length)
    while i != stop
      value += bytes[byteIndex + i] * scale
      i += increment
      scale *= 256
    if @signed and (value & @signBit)
      value -= Math.pow(2, @bitLength)
    value

  toByteArray: (value, littleEndian) ->
    if littleEndian
      i = 0
      increment = 1
    else
      i = @length - 1
      increment = -1
    value = if value < @minValue
      @minValue
    else if value > @maxValue
      @maxValue
    else
      value
    bytes = new Array(@length)
    stop = i + (increment * @length)
    while i != stop
      bytes[i] = value & 255
      i += increment
      value >>= 8
    bytes


class ArrayCodec

  # An array codec is a special case. It wraps a format codec, but prefixes
  # it with a uint32 length value. It will first read the length, then read
  # than many of the values from the byte array.

  lengthCodec: new IntegerCodec(4, signed: false)

  constructor: (@valueType) ->
    @valueCodec = codecs[@valueType]
    unless @valueCodec?
      throw new Exception("Invalid array value type #{valueType}")

  fromByteArray: (bytes, byteIndex, littleEndian) ->
    # First read the number of elements in the array
    length = @lengthCodec.fromByteArray(bytes, byteIndex, littleEndian)
    byteIndex += @lengthCodec.length

    # Then read all the elements
    if length > 0
      values = new Array(length)
      for index in [0...length]
        values[index] = @valueCodec.fromByteArray(bytes, byteIndex,
                                                  littleEndian)
        byteIndex += @valueCodec.length
      @length = @lengthCodec.length + length * @valueCodec.length
      values
    else
      @length = @lengthCodec.length
      []

  toByteArray: (values, littleEndian) ->
    length = values?.length or 0
    bytes = @lengthCodec.toByteArray(length, littleEndian)
    if length > 0
      for value in values
        bytes = bytes.concat(@valueCodec.toByteArray(value, littleEndian))
    bytes


class StringCodec

  # The string codec is another special case. JavaScript strings are UTF-16,
  # which doesn't encode very efficiently for network traffic. The codec first
  # converts the strings to UTF-8, then converts that to a byte array. The
  # byte array is prefixed with the length of the UTF-8 string.
  #
  # FIXME: Could probably do this a bit more efficiently by encoding UTF-8
  # ourselves instead of using encodeURIComponent.

  lengthCodec: new IntegerCodec(4, signed: false)

  fromByteArray: (bytes, byteIndex, littleEndian) ->
    # First read the number of characters in the string
    length = @lengthCodec.fromByteArray(bytes, byteIndex, littleEndian)
    byteIndex += @lengthCodec.length

    # Then read the characters. The string is in UTF-8 format, so we'll need
    # to convert it back into UTF-16.
    if length > 0
      string = ''
      for i in [byteIndex...byteIndex + length]
        string += String.fromCharCode(bytes[i])
      @length = @lengthCodec.length + length
      decodeURIComponent(escape(string))
    else
      @length = @lengthCodec.length
      ''

  toByteArray: (string, littleEndian) ->
    if string
      utf8 = unescape(encodeURIComponent(string))
      length = utf8.length
      bytes = @lengthCodec.toByteArray(length, littleEndian)
      for i in [0...utf8.length]
        bytes.push(utf8.charCodeAt(i))
      bytes
    else
      # Undefined or empty string, just send a zero length
      @lengthCodec.toByteArray(0, littleEndian)


# This is a set of codecs that can be used by fields to convert typed values
# into an array of bytes, and to convert those bytes back into values. Note
# that the "array" type does not have a codec in this object, because
# ArrayCodec objects are created on the fly as needed.
codecs =
  boolean: new BooleanCodec()
  float32: new FloatCodec(4, 23, Math.pow(2, -24) - Math.pow(2, -77))
  float64: new FloatCodec(8, 52, 0)
  int8: new IntegerCodec(1, signed: true)
  int16: new IntegerCodec(2, signed: true)
  int32: new IntegerCodec(4, signed: true)
  string: new StringCodec()
  uint8: new IntegerCodec(1, signed: false)
  uint16: new IntegerCodec(2, signed: false)
  uint32: new IntegerCodec(4, signed: false)


# Return true if the type is *not* one of the allowed types.
isInvalidType = (type) ->
  switch (type)
    when 'array', 'string', 'boolean', 'int8', 'int16', 'int32', 'uint8', \
         'uint16', 'uint32', 'float32', 'float64'
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
    @codec = if @type is 'array'
      if (@valueType is 'array' or @valueType is 'string' or
          isInvalidType(@valueType))
        throw new Error("invalid array value type '#{@valueType}'")
      new ArrayCodec(@valueType)
    else
      codecs[@type]


class Definition

  # Definitions are a grouping of fields, and are used to encode or decode an
  # individual message. They can be grouped into schemas or used standalone.

  constructor: (@fields, {@id, @key, @littleEndian}={}) ->

  fromByteArray: (bytes, byteIndex=0) ->
    values = {}
    for {key, codec} in @fields
      values[key] = codec.fromByteArray(bytes, byteIndex, @littleEndian)
      byteIndex += codec.length
    values

  toByteArray: (object) ->
    bytes = []
    for {key, codec} in @fields
      bytes = bytes.concat(codec.toByteArray(object[key], @littleEndian))
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
    idCodec = codecs[@idType]
    id = idCodec.fromByteArray(bytes, 0)
    unless (definition = @definitionsById[id])?
      throw new Error("'#{id}' is not defined in schema")
    definition.fromByteArray(bytes, idCodec.length)

  stringify: (key, object) ->
    unless (definition = @definitions[key])?
      throw new Error("'#{key}' is not defined in schema")
    idBytes = codecs[@idType].toByteArray(definition.id)
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
exports._codecs = codecs
exports._stringToByteArray = stringToByteArray
exports.createSchema = createSchema
exports.define = define
